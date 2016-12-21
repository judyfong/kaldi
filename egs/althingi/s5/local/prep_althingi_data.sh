#!/bin/bash -eu

set -o pipefail

# Get the Althingi data on a proper format for kaldi
# 2016 Inga Rún

. ./path.sh
. ./cmd.sh

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

if [ $# -ne 2 ]; then
    echo "Usage: $0 <path-to-original-data> <output-data-dir>" >&2
    echo "Eg. $0 ~/data/local/corpus data/all" >&2
    exit 1;
fi

nj=25
stage=2
#datadir=data/local/corpus
#outdir=data/all
datadir=$(readlink -f $1); shift
outdir=$1; shift
mkdir -p $outdir

#iconv -f ISO-8859-1 -t UTF-8 ${datadir}/metadata.csv > ${datadir}/metadata_u8.csv

name_id_file=${datadir}/name_id_gender.tsv
meta=${datadir}/metadata.csv

# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing
#wav_cmd="sox -tmp3 - -c1 -esigned -r$samplerate -G -twav - "
wav_cmd="sox -tflac - -c1 -esigned -twav - "

if [ $stage -le 0 ]; then
    
    echo "a) spk2gender" # I use the abbreviation of parliament members' names as speaker IDs
    #cut -f2- ${datadir}/spk_name_gender.tsv | sed -e 's/\(.*\)/\L\1/' > spk2gender
    cut -f2- $name_id_file > ${outdir}/spk2gender

    echo "b) utt2spk" # Connect each utterance to a speaker.
    echo "c) wav.scp" # Connect every utterance with an audio file
    cut -d"," -f1,6 ${meta} | tr "," "\t" | LC_ALL=C sort > spkname_filename.tmp

    rm ${outdir}/utt2spk ${outdir}/filename_uttID.txt ${outdir}/wav.scp
    IFS=$'\n' # Want to separate on new lines
    for line in $(cat spkname_filename.tmp)
    do
	filename=$(echo $line | cut -f2)
	spkname=$(echo $line | cut -f1)
	spkID=$(grep $spkname ${name_id_file} | cut -f2)

	# Print to utt2spk
	printf "%s %s\n" ${spkID}-${filename} ${spkID} | tr -d $'\r' >> ${outdir}/utt2spk

	# Make a helper file with mapping between the filenames and uttID
	echo -e ${filename} ${spkID}-${filename} | tr -d $'\r' | LC_ALL=C sort -n >> ${outdir}/filename_uttID.txt
	
	#Print to wav.scp
	#echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f ${datadir}/audio/${filename}".mp3")" |" | tr -d $'\r' >> ${outdir}/wav.scp
	echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f ${datadir}/audio/${filename}".flac")" |" | tr -d $'\r' >> ${outdir}/wav.scp
    done
    rm spkname_filename.tmp

    echo "d) spk2utt"
    utils/utt2spk_to_spk2utt.pl < ${outdir}/utt2spk > ${outdir}/spk2utt
fi

if [ $stage -le 1 ]; then

    echo "e) text" # Each line is utterance ID and the utterance itself

    for n in bb endanlegt; do
        export xmldir=${datadir}/text_${n} #text_bb
        python3 -c "
import glob
import os
import re
xmlpaths = glob.glob(os.path.join(os.environ['xmldir'],'*.xml'))
fout = open('${outdir}/text_orig_${n}.txt','w')
for file in xmlpaths:
    file_base = os.path.splitext(os.path.basename(file))[0]
    with open(file, 'r',encoding='utf-8') as myfile:
        data=myfile.read().replace('\n', ' ')
        body_txt = re.search('<ræðutexti>(.*)</ræðutexti>',data).group()
    text = ' '.join([file_base, body_txt]).strip().replace('\n', ' ')
    print(text, file=fout)
fout.close()
"
    done
    unset xmldir

    ## The following cleans the text of all xml-tags. But I can't use it because
    ## there is so often no space around the tags which leaves the words around
    ## chrushed together
    # python -c "
    # import xml.etree.ElementTree as ET
    # import glob
    # import os 
    # xmlpaths = glob.glob(os.path.join(os.environ['xmldir'],'*.xml'))
    # fout = open(os.path.join(os.environ['outdir'],'text_orig.txt'),'w')
    # for file in xmlpaths:
    #     file_base = os.path.splitext(os.path.basename(file))[0]  
    #     tree = ET.parse(file)
    #     root = tree.getroot()
    #     ntextlines = len(root[1])
    #     textlist = [file_base]
    #     for line in xrange(ntextlines):
    #         textlist.append(ET.tostring(root[1][line], encoding='utf-8', method='text'))

    #     text = ' '.join(textlist).strip().replace('\n', ' ')
    #     print >>fout, text

    # fout.close()
    # "
fi

if [ $stage -le 2 ]; then

    echo "Remove xml-tags and comments"

    # As a first analysis I remove <frammíkall>, <truflun> and <atburður>. Switch out for a silence/noise model later!! NOTE!
    # I remove also the "forseti"-tag. Should I keep that in some way to note that it is a different speaker?
    # In the following I separate the numbers on "|":
    # 1) removes comments on the form "<mgr>//....//</mgr>"
    # 2) removes comments on the form "<!--...-->"
    # 3) removes links that were not written like 2)
    # 4) removes f.ex. <mgr>::afritun af þ. 287::</mgr>
    # 5) removes comments on the form "<mgr>....//</mgr>"
    # 6-7) removes comments before the beginning of speeches
    # 8-11) removes comments like "<truflun>Kliður í salnum.</truflun>"
    # 12) (in a new line) Rewrite fractions
    # 13-15) Rewrite law numbers
    # 16-19) Remove comments in a) parentheses, b) left: "(", right "/" or "//", c) left: "/", right one or more ")" and maybe a "/", d) left and right one or more "/"
    # 20-21) Remove the remaining tags and reduce the spacing to one between words
    perl -pe 's/<mgr>\/\/[^\/<]*?\/\/<\/mgr>|<!--[^>]*?-->|<[^>]*?>[^<]*?http[^<]*?<\/[^>]*?>|<[^>]*?>:[^<]*?ritun[^<]*?<\/[^>]*?>|<mgr>[^\/]*?\/\/<\/mgr>|<ræðutexti> +<mgr>[^\/]*?\/<\/mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+<\/mgr>|<truflun>[^<]*?<\/truflun>|<atburður>[^<]*?<\/atburður>|<málsheiti>[^<]*?<\/málsheiti>/ /g' ${outdir}/text_orig_bb.txt \
	    | perl -pe 's/\b([0-9])\/([0-9]{1,2})\b/$1 $2\./g' \
	    | perl -pe 's/\/?([0-9]+)\/([0-9]+)/ $1 $2/g' | perl -pe 's/([0-9]+)\/([A-Z]{2,})/$1 $2/g' | perl -pe 's/([0-9])\/ ([0-9])/$1 $2/g' \
	    | perl -pe 's/\([^\/\(<>]*?\)/ /g' | perl -pe 's/\([^\/<>\)]*?\/+/ /g' | perl -pe 's/\/[^\/<>\)]*?\)+\/?/ /g' | perl -pe 's/\/+[^\/<>\)]*?\/+/ /g'\
	    | perl -pe 's/<[^<>]*?>/ /g' | sed -e "s/[[:space:]]\+/ /g" > ${outdir}/text_noXML_bb.txt	

    perl -pe 's/<!--[^>]*?-->|<truflun>[^<]*?<\/truflun>|<atburður>[^<]*?<\/atburður>|<málsheiti>[^<]*?<\/málsheiti>|\([^\(\)<>]*?\)|<[^>]*?>/ /g' ${outdir}/text_orig_endanlegt.txt | sed -e "s/[[:space:]]\+/ /g" > ${outdir}/text_noXML_endanlegt.txt

fi

#perl -pe 's/<!--.*?-->|<[^>]*?>[^<]*?http[^<]*?<\/.*?[^>]>|<[^>]*?>:[^<]*?<\/.*?[^>]>|<ræðutexti>|<\/ræðutexti>|<frammíkall.*?>.*?<\/frammíkall>|<frammíkall\/>|<truflun>.*?<\/truflun>|<truflun\/>|<forseti.*?>|<\/forseti>|<línubil\/>|<mgr jöfnun=.*?>|<mgr\/>|<atburður>.*?<\/atburður>|<vísa>|<\/vísa>|<skáletrað>|<\/skáletrað>|<skáletrað\/>|<feitletrað>|<\/feitletrað>|<feitletrað\/>//g' ${outdir}/text_orig_${n}.txt | perl -pe 's/<mgr>|<\/mgr>|<lína>|<\/lína>|<brot.*?>|<\/brot>|<erindi>|<\/erindi>|<bjalla\/>/ /g' > ${outdir}/text_noXML_${n}.txt

if [ $stage -le 3 ]; then
    
    echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
    # Luckily noones middlename is written I. or V.
    for n in bb endanlegt; do
	perl -pe 's/([A-Z]\.?)–([A-Z])/$1 til $2/g' ${outdir}/text_noXML_${n}.txt > tmp && mv tmp ${outdir}/text_noXML_${n}.txt
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

    echo "Rewrite and remove punctuations"
    # 1) Change from utterance filename to uttID,
    # 2) Remove comments that appear at the end of certain speeches (still here because contained <skáletrað> in original text)
    # 3) Remove punctuations which is safe to remove
    # 4) Rewrite time and remove ":" before space because need to do that before I remove periods,
    # 5) Rewrite fractions
    # 6) Rewrite law numbers, f.ex. "2011/77/ESB" to "2011 77 ESB" and "lög nr 77/2011" to "lög nr 77 2011"
    # 7) Add missing space between sentences and after comments,
    # 8) Rewrite ".is" to " punktur is "
    # 9) In an itemized list, lowercase what comes after the numbering.
    # 10) Rewrite en dash (x96) and regular dash to " til ", if sandwitched between words or numbers,
    # 11) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
    # 12 Rewrite vulgar fractions
    # 13) Remove "," when not followed by a number, turn words containing non-Icelandic characters or punctuations that have not yet been cleared away to <unk>, change spaces to one between words
    for n in bb endanlegt; do
	join -j 1 <(sort -k1 ${outdir}/filename_uttID.txt) <(sort -k1 ${outdir}/text_noRoman_${n}.txt) | cut -d" " -f2- \
	    | perl -pe 's/\[Þingmenn risu úr sætum.*?]/ /g' \
	    | perl -pe 's/!|\+|\*|×|…|\(|\)|\]|\[|\.\.\.|\.\.|,,|”|“|„|\"|´|__+|\x27|<U+0090>|­||«|»|¬|<U+2015>//g' \
	    | perl -pe 's/([0-9]):([0-9][0-9])/$1 $2/g' | perl -pe 's/&amp;/og/g' | perl -pe 's/\?|:|;| | \./ /g' \
	    | perl -pe 's/\b([0-9])\/([0-9]{1,2})\b/$1 $2\./g' \
	    | perl -pe 's/\/?([0-9]+)\/([0-9]+)\/?/ $1 $2 /g' \
	    | sed -e 's/\([a-záðéíóúýþæö0-9][\.\/%]\)\([A-ZÁÐÉÍÓÚÝÞÆÖ\/]\)/\1 \2/g' \
	    | perl -pe 's/\.(is|net|com)(\W)/ punktur $1$2/g' | perl -pe 's/([0-9]\.)([a-záðéíóúýþæö])/$1 $2/g' | perl -pe 's/([a-záðéíóúýþæö]\.)([0-9])/$1 $2/g'\
	    | sed -e 's/ \+\([0-9]\.\) \+\([A-ZÁÐÉÍÓÚÝÞÆÖ]\)/ \1 \L\2/g' \
	    | perl -pe 's/([^ ])–([^ ])/$1 til $2/g' | perl -pe 's/(\d)tilstr\w*?\.?(\d)/$1 til $2/g' | perl -pe 's/([0-9\.%])-([0-9])/$1 til $2/g' \
	    | perl -pe 's/([0-9]+),([0-46-9])/$1 komma $2/g' | perl -pe 's/([0-9]+),5([0-9])/$1 komma $2/g' | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
	    | perl -pe 's/¼/ einn fjórði/g' | perl -pe 's/¾/ þrír fjórðu/g' | perl -pe 's/(\d)½/$1,5 /g' | perl -pe 's/ ½/ 0,5 /g' \
	    | perl -pe 's/,([^0-9])/$1/g' | perl -pe 's/\b[^ ]*([^a-yáðéíóúýþæöA-YÁÉÍÓÚÝÞÆÖ0-9%‰°º\., ]|[cqw])[^ ]*\b/<unk>/g' | sed -e "s/[[:space:]]\+/ /g" > ${outdir}/text_noPuncts1_${n}.txt
    done
fi

if [ $stage -le 5 ]; then

    echo "Lowercase, rewrite and remove punctuations"
    # The following are a bit changed because of the effect of tagging and untagging the text
    # 1-2) Remove final period (mostly to distinguish between numbers and ordinals) and period after letters,
    # 3) Lowercase text (not uttID) and rewrite "/a " to "á ári" and "/s " to "á sekúndu"
    # 4) Rewrite thousands and millions, f.ex. 3.500 to 3500,
    # 5) Rewrite chapter and clause numbers and time, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
    # 6) Add spaces between letters and numbers in alpha-numeric words,
    ## 7) Remove comments on what to add in text endanlegt f.ex "/í skj.: til að/" and "/dittó/",
    # 8) Swap "-" and "/" out for a space when sandwitched between words, f.ex. "suður-kórea" and "svart/hvítt",
    ## 9) Remove comments on what to add in text endanlegt f.ex "/þ. 278/"
    # 10) Remove remaining punctuations, fix some leftover stuff, and change spaces to one between words and write.
    for n in bb endanlegt; do
	sed -e 's/\.\( \+[A-ZÁÐÉÍÓÚÝÞÆÖ]\|$\)/\1/g' ${outdir}/text_noPuncts1_${n}.txt \
	    | perl -pe 's/([^0-9])\./$1/g' | perl -pe 's/([0-9]{4})\.(\s+|$)/$1$2/g' \
	    | sed 's/ .\+/\L&/g' | perl -pe 's/\/a( |$)/ á ári$1/g' | perl -pe 's/\/kg( |$)/ á kíló$1/g' | perl -pe 's/\/s( |$)/ á sekúndu$1/g' \
	    | perl -pe 's/([0-9]+)\.([0-9]{3})\.?/$1$2/g' \
	    | perl -pe 's/(\d{1,2})\.(\d{1,2})((\.(\d{1,2}|( |$)))| )\.?/$1 $2 $5$6/g' \
	    | perl -pe 's/( [a-záðéíóúýþæö]+)-?([0-9]+)(\W)/$1 $2$3/g' | perl -pe 's/( [0-9,]+%?)-?([a-záðéíóúýþæö]+)(\W)/$1 $2$3/g' \
	    | perl -pe 's/([a-záðéíóúýþæö])-([a-záðéíóúýþæö])/$1 $2/g' \
	    | perl -pe 's/—|–|-|\/|&lt|&gt|tilstr\w*?\.?/ /g' | perl -pe 's/&/ og /g' | perl -pe 's/([0-9]+)\.([0-9]+%?)/$1 $2/g' | perl -pe 's/, / /g' | perl -pe 's/ %/%/g'| sed -e "s/[[:space:]]\+/ /g" > ${outdir}/text_noPuncts_${n}.txt
    done
fi

# Line 7: | perl -pe 's/\/í s.*?\// /g' | perl -pe 's/\/[a-záðéíóúýþæö]*? ?[a-záðéíóúýþæö]+\// /g' \
# Line 9: | perl -pe 's/\/[0-9\. ]+\// /g' | perl -pe 's/\/[ a-záðéíóúýþæö0-9\.&-]+?\/\/?/ /g' \

# I have the problem that tagging and untagging the text changes it with regard to punctuations. Hence I need to split up the
# punctuation removal. Tagging the text works way worse after periods have been removed.
if [ $stage -le 5 ]; then
    echo "Expand some abbreviations, incl. 'hv.' and 'þm.'" # Should I expand the acronyms after the spelling check. OR What? NOTE!
    for n in bb endanlegt; do
	python3 local/replace_abbr_acro2.py ${outdir}/text_noPuncts_${n}.txt ${outdir}/text_exp1_${n}.txt # Switch out for a nicer solution
	# Use IceNLP and Anna's code
	python3 local/althingi_replace_plain_text2.py ${outdir}/text_exp1_${n}.txt ${outdir}/text_exp2_${n}.txt
	#cat ${outdir}/text_exp2_${n}.txt | local/iceNLPtagger.sh > ${outdir}/text_exp2_${n}_tagged.txt
	#python3 local/althingi_replace_tagged_text.py ${outdir}/text_exp2_${n}_tagged.txt ${outdir}/text_exp3_${n}.txt
    done
fi

# if [ $stage -le 6 ]; then

#     echo "Rewrite and remove punctuations"
#     # The following are a bit changed because of the effect of tagging and untagging the text
#     # 1) Remove final period (mostly to distinguish between numbers and ordinals) and period after letters,
#     # 2) Reverse some of the changes made when tagging and untagging.
#     # 3) Lowercase text (not uttID) and rewrite "/a " to "á ári" and "/s " to "á sekúndu"
#     # 4) Rewrite thousands and millions, f.ex. 3.500 to 3500,
#     # 5) Rewrite chapter and clause numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3",
#     # 6) Add spaces between letters and numbers in alpha-numeric words,
#     # 7) Remove comments on what to add in text endanlegt f.ex "/í skj.: til að/" and "/dittó/",
#     # 8) Swap "-" and "/" out for a space when sandwitched between words, f.ex. "suður-kórea" and "svart/hvítt",
#     # 9) Remove comments on what to add in text endanlegt f.ex "/þ. 278/"
#     # 10) Remove remaining punctuations, fix some leftover stuff, and change spaces to one between words and write.
#     for n in bb endanlegt; do
# 	sed -e 's/\.\( \+[A-ZÁÐÉÍÓÚÝÞÆÖ]\|$\)/\1/g' ${outdir}/text_exp3_${n}.txt \
# 	    | perl -pe 's/\x27//g' | perl -pe 's/< bjalla \/ >/<bjalla\/>/g' \
# 	    | perl -pe 's/([^0-9])\./$1/g' | perl -pe 's/([0-9]{4})\.(\s+|$)/$1$2/g' \
# 	    | sed 's/ .\+/\L&/g' | perl -pe 's/ \/ a( |$)/ á ári$1/g' | perl -pe 's/ \/ s( |$)/ á sekúndu$1/g' \
# 	    | perl -pe 's/([0-9]+)\.([0-9]{3})\.?/$1$2/g' \
# 	    | perl -pe 's/(\d{1,2})\.(\d{1,2})((\.(\d{1,2}| ))| )\.?/$1 $2 $5/g' \
# 	    | perl -pe 's/( [a-záðéíóúýþæö]+)-?([0-9]+)(\W)/$1 $2$3/g' | perl -pe 's/( [0-9]+%?)-?([a-záðéíóúýþæö]+)(\W)/$1 $2$3/g' \
# 	    | perl -pe 's/\/ ?í s.*? ?\// /g' | perl -pe 's/\/ ?[a-záðéíóúýþæö]*? ?[a-záðéíóúýþæö]+ ?\// /g' \
# 	    | perl -pe 's/([a-záðéíóúýþæö])-([a-záðéíóúýþæö])/$1 $2/g' \
# 	    | perl -pe 's/\/[0-9\. ]+\// /g' | perl -pe 's/\/[ a-záðéíóúýþæö0-9\.&-]+?\/ \/?/ /g' \
# 	    | perl -pe 's/—|–|-|­|\/|&lt|&gt//g' | perl -pe 's/ ²/²/g' | perl -pe 's/&/ og /g' | perl -pe 's/[0-9]+\.[0-9]+%?/<unk>/g' | perl -pe 's/, / /g' | sed -e "s/[[:space:]]\+/ /g" > ${outdir}/text_noPuncts_${n}.txt
#     done
# fi

if [ $stage -le 7 ]; then
    
    echo "Fix spelling errors"
    cut -d" " -f2- ${outdir}/text_exp2_endanlegt.txt | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${outdir}/words_text_endanlegt.txt
    if [ -f ${outdir}/text_bb_SpellingFixed.txt ]; then
	rm ${outdir}/text_bb_SpellingFixed.txt
    fi

    #for speech in $(grep "ÓÞ_rad20151116T174412" ${outdir}/text_noPuncts_bb.txt)
    IFS=$'\n' # IMPORTANT
    for speech in $(cat ${outdir}/text_exp2_bb.txt)
    do
        uttID=$(echo $speech | cut -d" " -f1)
	echo $speech | cut -d" " -f2- | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > vocab_speech.tmp
	
	# Find words that are not in any text_endanlegt speech 
	comm -23 <(cat vocab_speech.tmp) <(cat  ${outdir}/words_text_endanlegt.txt) > vocab_speech_only.tmp
	
	grep $uttID ${outdir}/text_exp2_endanlegt.txt > text_endanlegt_speech.tmp
	cut -d" " -f2- text_endanlegt_speech.tmp | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > vocab_text_endanlegt_speech.tmp

	# Find an approximate match in the vocab_text_endanlegt_speech
	# Substitute $word and the match in $speech
	python3 local/MinEditDist.py "$speech" ${outdir}/text_bb_SpellingFixed.txt vocab_speech_only.tmp vocab_text_endanlegt_speech.tmp
    done
    rm *.tmp
    
fi

if [ $stage -le 8 ]; then
    
    echo "Expand abbreviations and numbers in text"
    # # ./local/train_LM.sh
    # Nothing should be mapped to <unk> in the following
    cat ${outdir}/text_bb_SpellingFixed.txt \
        | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30.txt \
        | utils/int2sym.pl -f 2- text_norm/text/words30.txt > ${outdir}/text_bb_SpellingFixed_noOOV.txt
    # We want to process it in parallel.
    nj=40
    mkdir -p ${outdir}/split$nj/
    IFS=$' \t\n'
    split_text=$(for j in `seq 1 $nj`; do printf "${outdir}/split%s/text_bb_SpellingFixed_noOOV.%s.txt " $nj $j; done)
    utils/split_scp.pl ${outdir}/text_bb_SpellingFixed_noOOV.txt $split_text # problem with using $split_text if the field separator is not correct
    # Expand
    utils/slurm.pl JOB=1:$nj ${outdir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30.txt ark,t:${outdir}/split${nj}/text_bb_SpellingFixed_noOOV.JOB.txt text_norm/expand_to_words30.fst text_norm/text/numbertext_2g.fst ark,t:${outdir}/split${nj}/text_expanded.JOB.txt &

    # # Put all expanded text into one file
    if [ -f ${outdir}/text_bb_expanded.txt ]; then
        mv ${outdir}/{,.backup/}text_bb_expanded.txt
    fi
    cat ${outdir}/split${nj}/text_expanded.*.txt > ${outdir}/text_bb_expanded.txt

    cp ${outdir}/text_bb_expanded.txt ${outdir}/text

    # ################################
    # # #### Just a temporary fix ####
    # grep -o "[^0-9 ]*_rad20[0-9]*T[0-9]*" ${outdir}/log/expand-numbers.*.log | cut -d":" -f2 | sort -u > ${outdir}/speeches_notExpanded.txt # Find speeches not expanded

    # # Obtain the text NOT expanded
    # if [ -f ${outdir}/text_bb_NOT_expanded.txt ]; then
    #    rm ${outdir}/text_bb_NOT_expanded.txt
    # fi

    # for uttID in $(cat ${outdir}/speeches_notExpanded.txt)
    # do
    #     grep $uttID ${outdir}/text_bb_SpellingFixed.txt >> ${outdir}/text_bb_NOT_expanded.txt 
    # done
    # cat ${outdir}/text_bb_NOT_expanded.txt \
    #         | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30.txt \
    #         | utils/int2sym.pl -f 2- text_norm/text/words30.txt > ${outdir}/text_bb_NOT_expanded_no_OOV.txt
    # mv ${outdir}/text_bb_NOT_expanded_no_OOV.txt ${outdir}/text_bb_NOT_expanded.txt

    # # Put all expanded text into one file
    # #cat ${outdir}/text_expanded.*.txt > ${outdir}/text_bb_expanded.txt
    # # Remove uttID of speeches not expanded. (Directly modify the file and create a backup)
    # for uttID in $(cat ${outdir}/speeches_notExpanded.txt)
    # do
    #     sed -i.bak "/$uttID/d" ${outdir}/text_bb_expanded.txt
    # done

    # # Expand the not expanded again. I fixed the problem
    # nj=2
    # mkdir -p ${outdir}/split${nj}/
    # split_text=$(for j in `seq 1 $nj`; do printf "${outdir}/split%s/text_bb_NOT_expanded.%s.txt " $nj $j; done)
    # utils/split_scp.pl ${outdir}/text_bb_NOT_expanded.txt $split_text # problem with using $split_text
    # # Expand
    # utils/slurm.pl JOB=1:$nj ${outdir}/log/expand-numbers_temp.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30.txt ark,t:${outdir}/split${nj}/text_bb_NOT_expanded.JOB.txt text_norm/expand_to_words30.fst text_norm/text/numbertext_2g.fst ark,t:${outdir}/split${nj}/text_expanded_try3.JOB.txt &

    ####################################
fi

# echo "f) corpus.txt" # Contains only the utterances
#cut -d" " -f2- ${outdir}/text > ${outdir}/../local/corpus.txt

if [ $stage -le 8 ]; then
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir}
fi

IFS=$' \t\n'
exit 0
