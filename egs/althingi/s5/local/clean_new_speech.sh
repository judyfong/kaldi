#!/bin/bash -e

set -o pipefail

# This script cleans up text, which can later be processed further to be used in AMs, LMs or punctuation models.

stage=-1

. ./path.sh
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

if [ $# != 5 ]; then
  echo "Usage: local/clean_new_speech.sh [options] <input-text> <regex-pattern-of-abbreviations> <pron-dict> <text-out> <new-vocab>"
  echo "... where the regex pattern is created in extract_new_vocab_and_text.sh, "
  echo "from which this script is run"
  echo "a --stage option can be given to not run the whole script"
  exit 1;
fi
  
textin=$1 # contains the xml files 
abbr_pattern=$2
prondict=$3
ofile=$4
new_vocab=$5
outdir=$(dirname $ofile)
intermediate=$outdir/intermediate
mkdir -p $outdir/{intermediate,log}

bundle=$ASSET_ROOT/bundle/latest
abbr_acro=$bundle/initialisms

if [ $stage -le 1 ]; then
  
  echo "Remove xml-tags and comments"
  # If my input is from the old scraped althingi set I need to start by removing newlines
  tr '\n' ' ' < $textin \
      | sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>|<[^>]*?>: :g' \
      -e 's:\([^/()<>]*?\)+: :g' \
      -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
      -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
      -e 's:[[:space:]]+: :g' > ${intermediate}/text_noXML.txt || error 13 ${error_array[13]};
fi
  
if [ $stage -le 2 ]; then
  echo "Rewrite roman numerals"
  sed -i -r 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' ${intermediate}/text_noXML.txt
  python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${intermediate}/text_noXML.txt', 'r')
text_out = open('${intermediate}/text_noRoman.txt', 'w')
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
" || exit 1;

fi

if [ $stage -le 3 ]; then

  echo "Rewrite and remove punctuations"
  # 1) Remove comments that appear at the end of certain speeches (still here because contained <skáletrað> in original text)
  # 2) Rewrite time,
  # 3) Change "&amp;" to "og"
  # 4) Remove punctuations which is safe to remove
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
  # 28) Fix if the first letter in an acronym has been lowercased.
  # 29) Remove punctuations that we don't want to learn, map remaining weird words to <unk> and fix spacing
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
      < ${intermediate}/text_noRoman.txt \
    | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
    | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
          -e 's:([,;])([^0-9]|\s*$): \1 \2:g' -e 's:([^0-9]),:\1 ,:g' \
          -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
          -e 's: (gr|umr|sl|millj|nk|mgr|kr)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
          -e 's:\.([a-záðéíóúýþæö]):\1:g' \
          -e 's:([0-9,.]{3,})([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) *:\1 \2 :g' -e 's:([.:?!]+)\s*$: \1:g' \
          -e "s:(\b$(cat $abbr_pattern))\.:\1:g" \
          -e 's:([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([^0-9])([.:?!]+)([0-9]):\1 \2 \3:g' -e 's:([^0-9])([.:?!]+):\1 \2:g' \
          -e 's:(^[^ ]+) ([^ ]+):\1 \l\2:' \
          -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
          -e 's:—|–|/|tilstr[^ 0-9]*?\.?: :g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
         -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
         -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
         -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
         -e 's: *%:% :g' -e 's:([°º]) c :\1c :g' -e 's: 0([0-9]): 0 \1:g' \
         -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ]):\u\1:g' \
         -e 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9\.,?!:; %‰°º²³]+//g' -e 's/ [^ ]*[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+[0-9]+[^ ]*/ <unk>/g' -e 's: [0-9]{10,}: <unk>:g' -e 's/ +/ /g' \
         > ${intermediate}/text_noPuncts.txt || error 13 ${error_array[13]};

fi

if [ $stage -le 4 ]; then
  
  echo "Expand some abbreviations, incl. 'hv.' and 'þm.' in certain circumstances"
  # Start with expanding some abbreviations using regex
  sed -re 's:\bamk\b:að minnsta kosti:g' \
      -e 's:\bdómsmrh\b:dómsmálaráðherra:g' \
      -e 's:\bdr\b:doktor:g' \
      -e 's:\betv\b:ef til vill:g' \
      -e 's:\bfjmrh\b:fjármálaráðherra:g' \
      -e 's:\bforsrh\b:forsætisráðherra:g' \
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
      -e 's:\bsamgrh\b:samgönguráðherra:g' \
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
      < ${intermediate}/text_noPuncts.txt > ${intermediate}/text_exp1.txt || error 13 ${error_array[13]};

  # Use Anna's code to expand hv, hæstv and þm, where there is no ambiguity about the expanded form.
  python3 local/althingi_replace_plain_text.py ${intermediate}/text_exp1.txt ${intermediate}/text_exp2.txt || exit 1;

fi

if [ $stage -le 5 ]; then
  
  echo "Fix the casing of words in the text and extract new vocabulary"

  #Lowercase what only exists in lc in the prondict and uppercase what only exists in uppercase in the prondict

  # Find the vocabulary that appears in both cases in text
  cut -f1 $prondict | sort -u \
    | sed -re "s:.+:\l&:" \
    | sort | uniq -d \
    > ${intermediate}/prondict_two_cases.tmp || exit 1;

  # Find words that only appear in upper case in the pron dict
  comm -13 <(sed -r 's:.*:\u&:' ${intermediate}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]" | sort -u) \
       > ${intermediate}/propernouns_prondict.tmp || exit 1;
  
  comm -13 <(sort -u ${intermediate}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[a-záðéíóúýþæö]" | sort -u) \
       > ${intermediate}/only_lc_prondict.tmp || exit 1;

  # Find words in the new text that are not in the pron dict
  comm -23 <(cut -d' ' -f2- ${intermediate}/text_exp2.txt \
    | tr ' ' '\n' | egrep -v '[0-9%‰°º²³,.:;?! ]' \
    | egrep -v "\b$(cat $abbr_pattern)\b" | sort -u) \
    <(cut -f1 $prondict | sort -u) | egrep -v "Binary file" \
    > $intermediate/new_vocab_all.txt || exit 1;

  # Find the ones that probably have the incorrect case
  comm -12 $intermediate/new_vocab_all.txt \
       <(sed -r 's:.+:\l&:' ${intermediate}/propernouns_prondict.tmp) \
       > $intermediate/to_uppercase.tmp || exit 1;
  
  comm -12 $intermediate/new_vocab_all.txt \
       <(sed -r 's:.+:\u&:' ${intermediate}/only_lc_prondict.tmp) \
       > $intermediate/to_lowercase.tmp || exit 1;

  # Lowercase a few words in the text before capitalizing
  tr "\n" "|" < $intermediate/to_lowercase.tmp \
    | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
    > $intermediate/to_lowercase_pattern.tmp || exit 1;

  sed -r 's:(\b'$(cat $intermediate/to_lowercase_pattern.tmp)'\b):\l\1:g' \
       < ${intermediate}/text_exp2.txt > ${intermediate}/text_case1.txt || exit 1;

  # Capitalize
  tr "\n" "|" < $intermediate/to_uppercase.tmp \
  | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
  | sed 's:.*:\L&:' > $intermediate/to_uppercase_pattern.tmp || exit 1;

  sed -r 's:(\b'$(cat $intermediate/to_uppercase_pattern.tmp)'\b):\u\1:g' \
       < ${intermediate}/text_case1.txt > $ofile || exit 1;

  # Extract the vocabulary that is truly new, not just words in incorrect cases
  comm -23 <(comm -23 $intermediate/new_vocab_all.txt $intermediate/to_uppercase.tmp) \
       $intermediate/to_lowercase.tmp > $new_vocab || exit 1;

  # NOTE! But if I do this I should also use the named entity lists
  
fi

exit 0
