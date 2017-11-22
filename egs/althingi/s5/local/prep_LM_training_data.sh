#!/bin/bash -eu

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Clean the scraped althingi texts for use in a language model

nj=100
stage=-1
expand_stage=-1
order=5 # n-gram order

. ./path.sh
. ./cmd.sh
. utils/parse_options.sh
. local/utils.sh

if [ $# -ne 2 ]; then
    echo "Usage: $0 <texts-to-use-in-LM> <output-clean-expanded-capitalized-texts>" >&2
    echo "Eg. $0 ~/data/althingi/pronDict_LM/wp_lang.txt ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_expanded_CS.txt" >&2
    exit 1;
fi

corpus=$1
out=$2
dir=$(dirname $out)

if [ $stage -le 1 ]; then
    echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
    # Might clash with someones middle name. # The module roman comes from Dive into Python
    # First remove punctuations which are safe to remove and rewrite "–" between two roman numerals as "til".
    sed -re 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–²³¼¾½ _)(-]+//g' -e 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' <$corpus > ${dir}/scraped_precleaned.txt
    python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${dir}/scraped_precleaned.txt', 'r')
text_out = open('${dir}/scraped_noRoman.txt', 'w')
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
fi

if [ $stage -le 2 ]; then

    echo "Lowercase, rewrite and remove punctuations"
    # 1) Rewrite fractions
    # 2) Rewrite time
    # 3) Rewrite law numbers
    # 4) Remove comments in parentheses and expand "&"
    # 5-6) Remove punctuations which is safe to remove
    # 7) Remove "ja" from numbers written like "22ja"
    # 8) Rewrite [ck]?m[23] to [ck]?m[²³] and "kV" to "kw"
    # 9) Add missing space between sentences,
    # 10) Rewrite website names,
    # 11) In an itemized list, lowercase what comes after the numbering.
    # 12) Rewrite en dash (x96) and regular dash to " til ", if sandwitched between words or numbers,
    # 13) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
    # 14 Rewrite vulgar fractions
    # 15) Remove "," when not followed by a number or when not preceded by a number
    # 16) Remove final period,
    # 17) Lowercase text 
    # 18) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
    # 19) Change dashes and remaining slashes out for space
    # 20) Rewrite thousands and millions, f.ex. 3.500 to 3500,
    # 21) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
    # 22) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
    # 23) Fix spacing around % and degrees celsius and add space in a number starting with a zero
    # 24) Remove remaining punctuations and weird words, numbers longer than 9 characters (temporary till change expand.sh)
    # 25) Remove periods at the beginning of lines, fix spacing and remove empty lines
    sed -re 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
	-e 's:([0-9])\:([0-9][0-9]):\1 \2:g' \
	-e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
	-e 's:\([^/(]*?\): :g' -e 's:&: og :g' \
        -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' \
        -e 's:\?|!|\:|;|,+ | ,+| \.+|,\.| |__+: :g' \
        -e 's:([0-9]+)ja\b:\1:g' \
        -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: kV : kw :g' -e 's:Wst:\L&:g' \
        -e 's:\b([^ ]*[^ A-ZÁÐÉÍÓÚÝÞÆÖ])([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2:g' \
        -e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
        -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \L\2:g' \
        -e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9\.%])-+([0-9]):\1 til \2:g' \
        -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
	< ${dir}/scraped_noRoman.txt \
	| perl -pe 's/\b(0(?!,5))/$1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
        | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
              -e 's:,([^0-9]|$): \1:g' -e 's:([^0-9]),:\1 :g' \
              -e 's:\.+( +[A-ZÁÐÉÍÓÚÝÞÆÖ]|$):\1:g' -e 's:([^0-9])\.+([0-9]):\1 \2:g' -e 's:([^0-9])\.+:\1:g' -e 's:([0-9]{4,})\.+:\1 :g' \
              -e 's:.*:\L&:g' \
              -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
              -e 's:—|–|/: :g' -e 's:([a-záðéíóúýþæö])-+([a-záðéíóúýþæö]):\1 \2:g' \
              -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
              -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' -e 's:([0-9]+)\.([0-9]+%?)\.?:\1 \2 :g' \
              -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([a-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([a-záðéíóúýþæö]+)\b:\1 \2:g' \
              -e 's: +([;!%‰°º²³]):\1:g' -e 's:([°º]) c :\1c :g' -e 's: 0([0-9]): 0 \1:g' \
              -e 's/[^a-záðéíóúýþæö0-9\., %‰°º²³]+//g' -e 's/\b[^ ]*[a-záðéíóúýþæö]+[0-9]+[^ ]*/ /g' -e 's:[0-9]{10,}:<unk>:g' \
	      -e 's:^\. *::g' -e 's/[[:space:]]+/ /g' | grep -v "^\s*$" > ${dir}/scraped_noPuncts.txt

fi
#  -e 's:–([^0-9]): \1:g'

if [ $stage -le 3 ]; then
    echo "Expand some abbreviations, incl. 'hv.' and 'þm.'"
    # Start with expanding some abbreviations using regex
    sed -re 's:\bamk\b:að minnsta kosti:g' \
	-e 's:\bdr\b:doktor:g' \
	-e 's:\betv\b:ef til vill:g' \
	-e 's:\bfrh\b:framhald:g' \
	-e 's:\bfyrrv\b:fyrrverandi:g' \
	-e 's:\biðnrh\b:iðnaðarráðherra:g' \
	-e 's:\bmas\b:meira að segja:g' \
	-e 's:\bma\b:meðal annars:g' \
	-e 's:\bmkr\b:millj kr:g' \
	-e 's:\bnk\b:næstkomandi:g' \
	-e 's:\bnr\b:númer:g' \
	-e 's:\bos ?frv\b:og svo framvegis:g' \
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
	-e 's:\bþáv\b:þáverandi:g' \
	-e 's:\bþús\b:þúsund:g' \
	-e 's:\bþeas\b:það er að segja:g' \
	< ${dir}/scraped_noPuncts.txt > ${dir}/scraped_exp1.txt
    
    IFS=$'\n'
    for var in $(cat text_norm/abbr_acro_as_letters.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
    do
	var1=$(echo $var | sed 's/./& /g')
	sed -i "s/\b$var\b/$var1/g" ${dir}/scraped_exp1.txt
    done
    sed -r -i 's/[[:space:]]+/ /g' ${dir}/scraped_exp1.txt

    # Make the regex pattern
    tr "\n" "|" < text_norm/acronyms_as_words.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > text_norm/acronyms_as_words_pattern.tmp

    # Capitalize 
    srun sed -r 's:(\b'$(cat text_norm/acronyms_as_words_pattern.tmp)'\b):\U\1:g' ${dir}/scraped_exp1.txt > ${dir}/scraped_exp1_acroCS.txt
    
    # Use Anna's code
    python3 local/althingi_replace_plain_text.py ${dir}/scraped_exp1_acroCS.txt ${dir}/scraped_exp2.txt
fi

if [ $stage -le 4 ]; then
  
    echo "Expand numbers and abbreviations to make a better LM"
    nohup local/expand_scraped.sh --stage $expand_stage --nj $nj --order $order text_norm ${dir}/scraped_exp2.txt ${dir}/scraped_expanded_${order}g.txt &>expand.log
fi

if [ $stage -le 5 ]; then
    echo "Capitalize words in the scraped Althingi texts, that are capitalized in the pron dict"
    comm -12 <(sed -r 's:.*:\L&:' ${dir}/CaseSensitive_pron_dict_propernouns_plus.txt | sort) <(tr " " "\n" < ${dir}/scraped_expanded_${order}g.txt | egrep -v "^\s*$" | sort -u) > ${dir}/propernouns_scraped_althingi_texts.txt
    # Make the regex pattern
    tr "\n" "|" < ${dir}/propernouns_scraped_althingi_texts.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${dir}/propernouns_scraped_althingi_texts_pattern.tmp

    # Capitalize
    srun sed -r "s:(\b$(cat ${dir}/propernouns_scraped_althingi_texts_pattern.tmp)\b):\u\1:g" ${dir}/scraped_expanded_${order}g.txt > $out
fi

exit 0
