#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Get the Althingi data on a proper format for kaldi.

# NOTE! Talk to Judy about the format of the input before continuing

stage=-1
nj=10

. ./path.sh # Needed for KALDI_ROOT and ASSET_ROOT
. ./cmd.sh
. parse_options.sh || exit 1;
. ./conf/path.conf
. ./local/utils.sh

utf8syms=$root_listdir/utf8.syms
norm_listdir=$root_text_norm_listdir # All root_* variables are defined in path.conf
cap_listdir=$root_capitalization
abbr_list=$(ls -t $norm_listdir/abbreviation_list.*.txt | head -n1)
abbr_acro_as_letters=$(ls -t $norm_listdir/abbr_acro_as_letters.*.txt | head -n1)
acronyms_as_words=$(ls -t $cap_listdir/acronyms_as_words.*.txt | head -n1)
prondict=$(ls -t $root_lexicon/prondict.*.txt | head -n1)

if [ $# -ne 2 ]; then
  echo "This script cleans Icelandic parliamentary data, as obtained from the parliament."
  echo "It is assumed that the text data provided consists of two sets of files,"
  echo "the intermediate text and the final text. The texts in cleaned and normalized and"
  echo "Kaldi directories are created, containing the following files:"
  echo "utt2spk, spk2utt, wav.scp and text"
  echo ""
  echo "Usage: $0 <path-to-original-data> <output-data-dir>" >&2
  echo "e.g.: $0 /data/local/corpus data/all" >&2
  exit 1;
fi

corpusdir=$(readlink -f $1); shift
outdir=$1; shift
intermediate=$outdir/intermediate
mkdir -p $intermediate

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

[ ! -d $corpusdir ] && echo "$0: expected $corpusdir to exist" && exit 1
for f in $abbr_acro_as_letters $acronyms_as_words; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

meta=${corpusdir}/metadata.csv
name_id_file=${corpusdir}/name_id.tsv # created
if [ -e $name_id_file ]; then rm $name_id_file; fi

audiofile=$(ls ${corpusdir}/audio/ | head -n1)
extension="${audiofile##*.}"

# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing
wav_cmd="sox -t$extension - -c1 -esigned -r$samplerate -G -twav - "
#wav_cmd="sox -tflac - -c1 -esigned -twav - " # I had also files converted to flac that were already downsampled

# Make a name-id file (remember to remove the carriage return):
cut -d"," -f1 $meta | sort -u > $tmp/name.tmp
IFS=$'\n'
for name in $(cat ${tmp}/name.tmp); do
  speech=$(grep -m 1 $name $meta | cut -d"," -f6 | tr -d '\r')
  id=$(perl -ne 'print "$1\n" if /\bskst=\"([^\"]+)/' ${corpusdir}/text_endanlegt/${speech}.xml)
  echo -e $name'\t'$(echo $id | cut -d" " -f1) >> $name_id_file
done

if [ $stage -le 0 ]; then
  
  echo "a) utt2spk" # Connect each utterance to a speaker.
  echo "b) wav.scp" # Connect every utterance with an audio file
  for s in ${outdir}/utt2spk ${outdir}/wav.scp ${outdir}/filename_uttID.txt; do
    if [ -f ${s} ]; then rm ${s}; fi
  done

  IFS=$'\n' # Want to separate on new lines
  for line in $(LC_ALL=C sort ${meta})
  do
    filename=$(echo $line | cut -d"," -f6)
    spkname=$(echo $line | cut -d"," -f1)
    spkID=$(grep $spkname ${name_id_file} | cut -f2)

    # Print to utt2spk
    printf "%s %s\n" ${spkID}-${filename} ${spkID} | tr -d $'\r' >> ${outdir}/utt2spk

    # Make a helper file with mapping between the filenames and uttID
    echo -e ${filename} ${spkID}-${filename} | tr -d $'\r' | LC_ALL=C sort -n >> ${outdir}/filename_uttID.txt
    
    #Print to wav.scp
    echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f ${corpusdir}/audio/${filename}".$extension")" |" | tr -d $'\r' >> ${outdir}/wav.scp
  done

  echo "c) spk2utt"
  utils/utt2spk_to_spk2utt.pl < ${outdir}/utt2spk > ${outdir}/spk2utt
fi

if [ $stage -le 1 ]; then

  echo "d) text" # Each line is utterance ID and the utterance itself
  for n in bb endanlegt; do
    utils/slurm.pl --time 0-06:00 $outdir/log/extract_text_${n}.log python3 local/extract_text.py $corpusdir/text_${n} $outdir/text_orig_${n}.txt &
  done
  
fi

if [ $stage -le 2 ]; then

  echo "Remove xml-tags and comments"

  # In the following I separate the numbers on "|":
  # 1) removes comments on the form "<mgr>//....//</mgr>"
  # 2) removes comments on the form "<!--...-->"
  # 3) removes links that were not written like 2)
  # 4) removes f.ex. <mgr>::afritun af þ. 287::</mgr>
  # 5) removes comments on the form "<mgr>....//</mgr>"
  # 6-7) removes comments before the beginning of speeches
  # 8-11) removes comments like "<truflun>Kliður í salnum.</truflun>"
  # 12) removes comments in parentheses
  # 13) (in a new line) Rewrite fractions
  # 14-16) Rewrite law numbers
  # 17-19) Remove comments in a) parentheses, b) left: "(", right "/" or "//", c) left: "/", right one or more ")" and maybe a "/", d) left and right one or more "/"
  # 20) Remove comments on the form "xxxx", used when they don't hear what the speaker said
  # 21-22) Remove the remaining tags and reduce the spacing to one between words
  sed -re 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
      -e 's:\(+[^/()<>]*?\)+: :g' \
      -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
      -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
      -e 's:\([^/<>)]*?/+: :g' -e 's:/[^/<>)]*?\)+/?: :g' -e 's:/+[^/<>)]*?/+: :g' \
      -e 's:xx+::g' \
      -e 's:<[^<>]*?>: :g' -e 's:[[:space:]]+: :g' <${outdir}/text_orig_bb.txt > ${outdir}/text_noXML_bb.txt	

  sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>|<[^>]*?>: :g' \
      -e 's:\([^/()<>]*?\)+: :g' \
      -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
      -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
      -e 's:[[:space:]]+: :g' ${outdir}/text_orig_endanlegt.txt > ${outdir}/text_noXML_endanlegt.txt

  # Sometimes some of the intermediatary text files are empty.
  # I remove the empty files and add corresponding final-text-files in the end
  egrep -v "rad[0-9][^ ]+ *$" ${outdir}/text_noXML_bb.txt > $tmp/tmp && mv $tmp/tmp ${outdir}/text_noXML_bb.txt

  # Remove files that exist only in the intermediate text
  comm -12 <(cut -d" " -f1 ${outdir}/text_noXML_bb.txt | sort -u) <(cut -d" " -f1 ${outdir}/text_noXML_endanlegt.txt | sort -u) > ${tmp}/common_ids.tmp
  join -j1 ${tmp}/common_ids.tmp ${outdir}/text_noXML_bb.txt > $tmp/tmp && mv $tmp/tmp ${outdir}/text_noXML_bb.txt

fi


if [ $stage -le 3 ]; then
  
  echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
  # Might clash with someones middle name. # The module roman comes from Dive into Python
  for n in bb endanlegt; do
    sed -i -r 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' ${outdir}/text_noXML_${n}.txt
    python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${outdir}/text_noXML_${n}.txt', 'r')
text_out = open('${outdir}/text_noRoman_${n}.txt', 'w')
for line in text:
    match_list = re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', line, flags=0)
    match_list = [elem for elem in match_list if len(elem)>0]
    match_list = list(set(match_list))
    match_list.sort(key=len, reverse=True) # Otherwise it will substitute parts of roman numerals
    line = line.split()
    tmpline=[]
    for match in match_list:
        for word in line:
            number = [re.sub(match,str(roman.fromRoman(match)),word) for elem in re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', word) if len(elem)>0]
            if len(number)>0:
                tmpline.extend(number)
            else:
                tmpline.append(word)
        line = tmpline
        tmpline=[]
    print(' '.join(line), file=text_out)

text.close()
text_out.close()
"
  done
fi

if [ $stage -le 4 ]; then

  # Make the abbreviation regex pattern used in step 18
  cat $abbr_list <(sed -r 's:.*:\u&:' $abbr_list) | sort -u | tr "\n" "|" | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > $tmp/abbr_pattern.tmp
  
  echo "Rewrite and remove punctuations"
  # 1) Remove comments that appear at the end of certain speeches (still here because contained <skáletrað> in original text)
  # 2) Rewrite time,
  # 3) Change "&amp;" to "og"
  # 4) Remove punctuations which is safe to remove and deal with double punctuations
  # 5) Cahnge "..." -> "." and a double punctuation to only the latter one with a space in front
  # 6) Remove "ja" from numbers written like "22ja",
  # 7) Rewrite [ck]?m[23] to [ck]?m[²³] and "kV" to "kw"
  # 8) Fix spelling errors like "be4stu" and "o0g",
  # 9) Rewrite website names,
  # 10) In an itemized list, lowercase what comes after the numbering.
  # 11) Rewrite en dash (x96), regular dash and "tilstr(ik)" to " til ", if sandwitched between words or numbers,
  # 12-13) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
  # 14) Rewrite vulgar fractions
  # 15) Add space before "," when not followed by a number and before ";"
  # 16) Remove the period in abbreviated middle names
  # 17) For a few abbreviations that often stand at the end of sentences, add space before the period
  # 18) Remove periods inside abbreviation
  # 19) Move EOS punctuation away from the word and lowercase the next word, if the previous word is a number or it is the last word.
  # 20) Remove the abbreviation periods
  # 21) Move remaining EOS punctuation away from the word and lowercase next word
  # 22) Lowercase the first word in a speech
  # 22) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
  # 23) Switch dashes (exept in utt filenames) and remaining slashes out for space
  # 24) Rewrite thousands and millions, f.ex. 3.500 to 3500,
  # 25) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
  # 26) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
  # 27) Fix spacing around % and degrees celsius and add space in a number starting with a zero
  # 28) Remove "lauk á fyrri spólu"
  # 29) Remove punctuations that we don't want to learn, map remaining weird words to <unk> and fix spacing
  for n in bb endanlegt; do
    sed -re 's:\[[^]]*?\]: :g' \
	-e 's/([0-9]):([0-9][0-9])/\1 \2/g' \
	-e 's/&amp;/og/g' \
	-e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |__+: :g' \
	-e 's:\.\.\.:.:g' -e 's:\b([^0-9]{1,3})([.,:;?!])([.,:;?!]):\1 \3 :g' -e 's:\b([0-9]{1,3}[.,:;?!])([.,:;?!]):\1 \2 :g' -e 's:\b(,[0-9]+)([.,:;?!]):\1 \2 :g' \
	-e 's:([0-9]+)ja\b:\1:g' \
	-e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: kV : kw :g' -e 's:Wst:\L&:g' \
	-e 's:\b([a-záðéíóúýþæö]+)[0-9]([a-záðéíóúýþæö]+):\1\2:g' \
	-e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
	-e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
	-e 's:([^ 0-9])–([^ 0-9]):\1 \2:g' -e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9]\.?)tilstr[^ 0-9]*?\.?([0-9]):\1 til \2:g' -e 's:([0-9\.%])-+([0-9]):\1 til \2:g' \
	-e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
	< ${outdir}/text_noRoman_${n}.txt \
      | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
      | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
            -e 's:([,;])([^0-9]|\s*$): \1 \2:g' -e 's:([^0-9]),:\1 ,:g' \
            -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
            -e 's: (gr|umr|sl|millj|nk|mgr|kr)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
            -e 's:\.([a-záðéíóúýþæö]):\1:g' \
            -e 's:([0-9,.]{3,})([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) *:\1 \2 :g' -e 's:([.:?!]+)\s*$: \1:g' \
            -e "s:(\b$(cat $tmp/abbr_pattern.tmp))\.:\1:g" \
            -e 's:([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([^0-9])([.:?!]+)([0-9]):\1 \2 \3:g' -e 's:([^0-9])([.:?!]+):\1 \2:g' \
            -e 's:(^[^ ]+) ([^ ]+):\1 \l\2:' \
            -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
            -e 's:—|–|/|tilstr[^ 0-9]*?\.?: :g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
            -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
            -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
            -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
            -e 's: *%:% :g' -e 's:([°º]) c :\1c :g' -e 's: 0([0-9]): 0 \1:g' \
	    -e 's:lauk á (f|fyrri) ?sp.*::' \
            -e 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9\.,?!:; %‰°º²³]+//g' -e 's/ [^ ]*[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+[0-9]+[^ ]*/ <unk>/g' -e 's: [0-9]{10,}: <unk>:g' -e 's/ +/ /g' \
            > ${outdir}/text_noPuncts_${n}.txt || error 13 ${error_array[13]};
  done
  
fi

if [ $stage -le 5 ]; then
  echo "Expand some abbreviations, incl. 'hv.' and 'þm.' in certain circumstances"
  for n in bb endanlegt; do
    # Start with expanding some abbreviations using regex
    sed -re 's:\bamk\b:að minnsta kosti:g' \
	-e 's:\bdr\b:doktor:g' \
	-e 's:\betv\b:ef til vill:g' \
	-e 's:\bfrh\b:framhald:g' \
	-e 's:\bfyrrv\b:fyrrverandi:g' \
	-e 's:\bheilbrrh\b:heilbrigðisráðherra:g' \
	-e 's:\biðnrh\b:iðnaðarráðherra:g' \
	-e 's:\binnanrrh\b:innanríkisráðherra:g' \
	-e 's:\blandbrh\b:landbúnaðarráðherra:g' \
	-e 's:\bmas\b:meira að segja:g' \
	-e 's:\bma\b:meðal annars:g' \
	-e 's:\bmenntmrh\b:mennta og menningarmálaráðherra:g' \
	-e 's:\bmkr\b:millj kr:g' \
	-e 's:\bnk\b:næstkomandi:g' \
	-e 's:\bnr\b:númer:g' \
	-e 's:\bnúv\b:núverandi:g' \
	-e 's:\bosfrv\b:og svo framvegis:g' \
	-e 's:\boþh\b:og þess háttar:g' \
	-e 's:\bpr\b:per:g' \
	-e 's:\bsbr\b:samanber:g' \
	-e 's:\bskv\b:samkvæmt:g' \
	-e 's:\bss\b:svo sem:g' \
	-e 's:\bstk\b:stykki:g' \
	-e 's:\btd\b:til dæmis:g' \
	-e 's:\btam\b:til að mynda:g' \
	-e 's:\buþb\b:um það bil:g' \
	-e 's:\butanrrh\b:utanríkisráðherra:g' \
	-e 's:\bviðskrh\b:viðskiptaráðherra:g' \
	-e 's:\bþáv\b:þáverandi:g' \
	-e 's:\bþús\b:þúsund:g' \
	-e 's:\bþeas\b:það er að segja:g' \
	< ${outdir}/text_noPuncts_${n}.txt > ${outdir}/text_exp1_${n}.txt
  done

  for n in bb endanlegt; do
    
    # Capitalize acronyms which are pronounced as words (some are incorrectly written capitalized, e.g. IKEA as Ikea)
    # Make the regex pattern
    tr "\n" "|" < $acronyms_as_words | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${tmp}/acronyms_as_words_pattern.tmp

    # Capitalize 
    srun sed -re 's:(\b'$(cat ${tmp}/acronyms_as_words_pattern.tmp)'\b):\U\1:g' -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ]):\u\1:g' ${outdir}/text_exp1_${n}.txt > ${outdir}/text_exp1_${n}_acroCS.txt
    
    # Use Anna's code to expand many instances of hv, þm og hæstv
    python3 local/althingi_replace_plain_text.py ${outdir}/text_exp1_${n}_acroCS.txt ${outdir}/text_exp2_${n}.txt
  done
  
  # I don't want to expand acronyms pronounced as letters in the punctuation training text
  echo "make a special text version for the punctuation training texts"
  cp ${outdir}/text_exp2_endanlegt.txt ${intermediate}/text_exp2_forPunct.txt

  for n in bb endanlegt; do
    # Add spaces into acronyms pronounced as letters
    egrep -o "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" ${outdir}/text_exp2_${n}.txt | sort -u > $tmp/acro.tmp
    egrep "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" $tmp/asletters.tmp
    cat $tmp/asletters.tmp $abbr_acro_as_letters | sort -u > $tmp/asletters_tot.tmp

    # Create a table where the 1st col is the acronym and the 2nd one is the acronym with with spaces between the letters
    paste <(cat $tmp/asletters_tot.tmp | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2) <(cat $tmp/asletters_tot.tmp | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2 | sed -re 's/./\l& /g' -e 's/ +$//') | tr '\t' ' ' | sed -re 's: +: :g' > $tmp/insert_space_into_acro.tmp
    
    # Create a sed pattern file: Change the first space to ":"
    sed -re 's/ /\\b:/' -e 's/^.*/s:\\b&/' -e 's/$/:gI/g' < $tmp/insert_space_into_acro.tmp > $tmp/acro_sed_pattern.tmp
    /bin/sed -f $tmp/acro_sed_pattern.tmp ${outdir}/text_exp2_${n}.txt > ${outdir}/text_exp3_${n}.txt

  done
fi

if [ $stage -le 6 ]; then
    
    echo "Fix spelling errors"
    cut -d" " -f2- ${outdir}/text_exp2_endanlegt.txt | sed -e 's/[0-9\.,%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${outdir}/words_text_endanlegt.txt
    if [ -f ${outdir}/text_bb_SpellingFixed.txt ]; then
	rm ${outdir}/text_bb_SpellingFixed.txt
    fi
    
    # Split into subfiles and correct them in parallel
    mkdir -p ${outdir}/split${nj}/log
    total_lines=$(wc -l ${outdir}/text_exp2_bb.txt | cut -d" " -f1)
    ((lines_per_file = (total_lines + num_files - 1) / num_files))
    split --lines=${lines_per_file} ${outdir}/text_exp2_bb.txt ${outdir}/split${nj}/text_exp2_bb.

    source py3env/bin/activate
    IFS=$'\n' # Important
    for ext in $(ls ${outdir}/split${nj}/text_exp2_bb.* | cut -d"." -f2); do
        sbatch --get-user-env --time=0-12 --job-name=correct_spelling --output=${outdir}/split${nj}/log/spelling_fixed.${ext}.log --wrap="srun local/correct_spelling.sh --nj=$nj --ext=$ext ${outdir}/words_text_endanlegt.txt $outdir"
    done
    deactivate

    cat ${outdir}/split${nj}/text_bb_SpellingFixed.*.txt > ${outdir}/text_bb_SpellingFixed.txt
        
fi

if [ $stage -le 7 ]; then

    # If the intermediate text file is empty or does not exist, use the final one instead
    egrep "^rad[0-9][^ ]+ *$" ${outdir}/text_bb_SpellingFixed.txt > ${tmp}/empty_text_bb.tmp
    if [ -s ${tmp}/empty_text_bb.tmp ]; then
	echo "Empty text_bb files"
	echo "Insert text from text_endanlegt"
	for file in $(cat ${tmp}/empty_text_bb.tmp); do
	    sed -i -r "s#${file}#$(grep $file ${outdir}/text_exp2_endanlegt.txt)#" ${outdir}/text_bb_SpellingFixed.txt
	done
    fi

    # If the intermediate file did not exist at all, I use the final text instead
    comm -13 <(cut -d" " -f1 ${outdir}/text_bb_SpellingFixed.txt | sort -u) <(cut -d" " -f1 ${outdir}/text_exp2_endanlegt.txt | sort -u) > ${tmp}/ids_only_in_text_endanlegt.tmp
    join -j1 ${tmp}/ids_only_in_text_endanlegt.tmp ${outdir}/text_exp2_endanlegt.txt >> ${outdir}/text_bb_SpellingFixed.txt
    sort -u ${outdir}/text_bb_SpellingFixed.txt > $tmp/tmp && mv $tmp/tmp ${outdir}/text_bb_SpellingFixed.txt

fi

if [ $stage -le 8 ]; then
  echo "Fix the casing of words in the text and extract new vocabulary"

  #Lowercase what only exists in lc in the prondict and uppercase what only exists in uppercase in the prondict

  # Find the vocabulary that appears in both cases in text
  cut -f1 $prondict | sort -u \
    | sed -re "s:.+:\l&:" \
    | sort | uniq -d \
    > ${tmp}/prondict_two_cases.tmp || exit 1;

  # Find words that only appear in upper case in the pron dict
  comm -13 <(sed -r 's:.*:\u&:' ${tmp}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]" | sort -u) \
       > ${tmp}/propernouns_prondict.tmp || exit 1;
  
  comm -13 <(sort -u ${tmp}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[a-záðéíóúýþæö]" | sort -u) \
       > ${tmp}/only_lc_prondict.tmp || exit 1;

  # Find words in the new text that are not in the pron dict
  comm -23 <(cut -d' ' -f2- ${outdir}/text_bb_SpellingFixed.txt \
    | tr ' ' '\n' | egrep -v '[0-9%‰°º²³,.:;?! ]' \
    | egrep -v "\b$(cat $tmp/abbr_pattern.tmp)\b" | sort -u) \
    <(cut -f1 $prondict | sort -u) | egrep -v "Binary file" \
    > $tmp/new_vocab_all.txt || exit 1;

  # Find the ones that probably have the incorrect case
  comm -12 $tmp/new_vocab_all.txt \
       <(sed -r 's:.+:\l&:' ${tmp}/propernouns_prondict.tmp) \
       > $intermediate/to_uppercase.tmp || exit 1;
  
  comm -12 $tmp/new_vocab_all.txt \
       <(sed -r 's:.+:\u&:' ${tmp}/only_lc_prondict.tmp) \
       > $intermediate/to_lowercase.tmp || exit 1;

  # Lowercase a few words in the text before capitalizing
  tr "\n" "|" < $intermediate/to_lowercase.tmp \
    | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
    > $tmp/to_lowercase_pattern.tmp || exit 1;

  sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
      < ${outdir}/text_bb_SpellingFixed.txt > ${intermediate}/text_case1.txt || exit 1;
  
  # Capitalize
  tr "\n" "|" < $intermediate/to_uppercase.tmp \
  | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
  | sed 's:.*:\L&:' > $tmp/to_uppercase_pattern.tmp || exit 1;

  sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
      < ${intermediate}/text_case1.txt > ${outdir}/text_bb_SpellingFixed_CasingFixed.txt || exit 1;

  # Do the same for the punctuation text
  sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
      < ${intermediate}/text_exp2_forPunct.txt > ${intermediate}/text_case1_forPunct.txt || exit 1;
  sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
      < ${intermediate}/text_case1_forPunct.txt > ${outdir}/text_PunctuationTraining.txt || exit 1;
  
  # NOTE! But if I do this I should also use the named entity lists
  
fi

if [ $stage -le 8 ]; then
    # Join the utterance names with the spkID to make the uttIDs
    join -j 1 <(sort -k1,1 ${outdir}/filename_uttID.txt) <(sort -k1,1 ${outdir}/text_bb_SpellingFixed_CasingFixed.txt) | cut -d" " -f2- > ${outdir}/text_bb_uttID.txt

    if [ -e ${outdir}/text ] ; then
	# we don't want to overwrite old stuff, ask the user to delete it.
	echo "$0: ${outdir}/text already exists: "
	echo "Are you sure you want to proceed?"
	echo "It will overwrite the file"
	echo ""
        echo "  If so, please delete and then rerun"
	exit 1;
    fi

    cp ${outdir}/text_bb_uttID.txt ${outdir}/text
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir}
fi

exit 0
