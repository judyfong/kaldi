#!/bin/bash -eu

set -o pipefail

# 2016 Inga Rún
# Clean the scraped althingi texts for use in a language model

. ./path.sh
. ./cmd.sh

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap "rm -rf $tmp" EXIT

if [ $# -ne 2 ]; then
    echo "Usage: $0 <texts-to-use-in-LM> <output-clean-texts>" >&2
    echo "Eg. $0 ~/data/althingi/pronDict_LM/wp_lang.txt ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean.txt" >&2
    exit 1;
fi

corpus=$1 #~/data/althingi/pronDict_LM/wp_lang.txt
out=$2 #~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean.txt
outdir=$(readlink -f $2);

#mkdir -p $outdir

if [ $stage -le 1 ]; then
    echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
    # Might clash with someones middle name. # The module roman comes from Dive into Python
    # First remove punctuations which are safe to remove and rewrite "–" between two roman numerals as "til".
    sed -re 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–²³¼¾½ _)(-]+//g' -e 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' ${outdir}/scraped_precleaned.tmp
    python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${outdir}/scraped_precleaned.tmp', 'r')
text_out = open('${outdir}/scraped_noRoman.tmp', 'w')
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
    # 4) Remove comments in parentheses
    # 5) Remove more punctuations
    # 6) Add missing space between sentences,
    # 7) Rewrite website names
    # 7) Rewrite en dash (x96) and regular dash to " til ", if sandwitched between words or numbers,
    # 8) Rewrite vulgar fractions,
    # 9) Remove "," when not followed by a number (usually cramped between two words)
    # 10) Rewrite &,
    # 11) Make space behind %,
    # 12) Remove period at the end og a sentence (i.e. when followed by a space and an upper case letter or EOL)
    # 13) Lowercase text
    # 14) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
    # 15) Change f.ex. "23ja" to "23"
    # 16) Rewrite [ck]?m[23] to [ck]?m[²³] and expand things like "4x4"
    # 17) Add spaces between letters and numbers in alpha-numeric words,
    # 18) Swap "-"out for a space when sandwitched between words, f.ex. "suður-kórea" and "svart/hvítt",
    # 19) Remove periods after letters and after number of lenght 4
    # 20-21) Rewrite decimal numbers
    # 21) Remove periods, f.ex. "30.000" -> "30000"
    # 22) Rewrite f.ex. chapter names
    # 23) Remove every character not listed (I can skip starting the regex with a space becasue I have no uttIDs)
    # 15) Remove remaining punctuations, change spaces to one between words, remove empty lines and remove leading spaces and write.    
    sed -re 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
	-e 's:([0-9])\:([0-9][0-9]):\1 \2:g' \
	-e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
	-e 's:\([^/(]*?\): :g' \
	-e 's:\?|\:|;|, | ,+| \.+|,\.| |__+: :g' \
	-e 's: ([^ ]*[^ A-ZÁÐÉÍÓÚÝÞÆÖ])([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2:g' \
	-e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
	-e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9\.%])-([0-9]):\1 til \2:g' \
	-e 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
	-e 's:,([^0-9]):\1:g' \
	-e 's:&: og :g' \
	-e 's:%:% :g' \
	-e 's/\.( +[A-ZÁÐÉÍÓÚÝÞÆÖ]|$)/\1/g' \
	-e 's:.*:\L&:g' \
	-e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
	-e 's:([0-9]+)ja\b:\1:g' \
	-e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's:( [0-9]+)([^0-9 ,])([0-9]):\1 \2 \3:g' \
	-e 's:( [a-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:(^| )([0-9,]+%?)\.?-?([a-záðéíóúýþæö]+)\b:\1\2 \3:g' \
	-e 's:([a-záðéíóúýþæö])-([a-záðéíóúýþæö]):\1 \2:g' \
	-e 's:([^0-9])\.+:\1:g' -e 's:([0-9]{4})\.\b:\1:g' \
	-e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma \2:g' <${outdir}/scraped_noRoman.tmp \
	| perl -pe 's: (0(?!,5)): $1 :g' | perl -pe 's:komma (0? ?)(\d)(\d)(\d)(\d?):komma $1$2 $3 $4 $5:g' \
	| sed -re 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
	-e 's:([0-9]{1,2})\.([0-9]{1,2}):\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\.?:\1 \2 :g' \
	-e 's:/: :g' -e 's:[^a-záðéíóúýþæö0-9\., %‰°º²³]+::g' -e "s:[[:space:]]+: :g" -e 's:^[ \t]*::' | egrep -v "^\s*$" > ${outdir}/scraped_noPuncts.tmp
fi

if [ $stage -le 24 ]; then
  
    echo "Expand numbers and abbreviations to make a better LM"
    ./local/expand_scraped.sh ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean text_norm
fi

# Capitalize words in the scraped Althingi texts, that are capitalized in the pron dict
comm -12 <(sed -e 's/\(.*\)/\L\1/' ${pronDictdir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(tr " " "\n" < scrapedAlthingiTexts_clean.txt | grep -Ev "^\s*$" | sort -u) > ${pronDictdir}/propernouns_scraped_althingi_texts.txt
# Make the regex pattern
tr "\n" "|" < ${pronDictdir}/propernouns_scraped_althingi_texts.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > ${pronDictdir}/propernouns_scraped_althingi_texts_pattern.tmp

# Capitalize
srun --mem 8G sed -e 's/\(\b'$(cat ${pronDictdir}/propernouns_scraped_althingi_texts_pattern.tmp)'\b\)/\u\1/g' ${pronDictdir}/scrapedAlthingiTexts_clean.txt > ${pronDictdir}/scrapedAlthingiTexts_clean_CaseSens.txt


exit 0
