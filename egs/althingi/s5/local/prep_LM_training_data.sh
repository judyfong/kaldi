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

echo "Lowercase, rewrite and remove punctuations"

# 1) Remove punctuations which is safe to remove, incl. parentheses. NOTE! Change?
# 2) Rewrite fractions
# 3) Rewrite law numbers
# 4) Remove comments in parentheses
# 2) Add missing space between sentences,
# 3) Rewrite ".is" to " punktur is "
# 4) Rewrite en dash (x96) and regular dash to " til ", if sandwitched between words or numbers,
# 5) Rewrite vulgar fractions,
# 6) Remove "," when not followed by a number, rewrite &,
# 7) Remove periods after letters and make space behind %,
# 8) Lowercase text (not uttID) and rewrite "/a " to "á ári" and "/s " to "á sekúndu"
# 9) Add spaces between letters and numbers in alpha-numeric words,
# 8) Swap "-" and "/" out for a space when sandwitched between words, f.ex. "suður-kórea" and "svart/hvítt",
# 9) Remove comments on what to add in text endanlegt f.ex "/þ. 278/"
# 10) Remove remaining punctuations, change spaces to one between words, remove empty lines and remove leading spaces and write.    
sed 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–\-²³¼¾½ _\)\(]\+//g' ${corpus} \
    | perl -pe 's/\b([0-9])\/([0-9]{1,2})\b/$1 $2\./g' \
    | perl -pe 's/\/?([0-9]+)\/([0-9]+)/ $1 $2/g' | perl -pe 's/([0-9]+)\/([A-Z]{2,})/$1 $2/g' | perl -pe 's/([0-9])\/ ([0-9])/$1 $2/g' \
    | perl -pe 's/\([^\/\(<>]*?\)/ /g' \
    | perl -pe 's/\?|:|;|, | ,| \.| / /g' \
    | sed -e 's/\([a-záðéíóúýþæö0-9]\.\)\([A-ZÁÐÉÍÓÚÝÞÆÖ\/]\)/\1 \2/g' \
    | perl -pe 's/\.(is|net|com)(\W)/ punktur $1$2/g' \
    | perl -pe 's/([^ ])–([^ ])/$1 til $2/g' | perl -pe 's/([0-9\.%])-([0-9])/$1 til $2/g' \
    | perl -pe 's/¼/ einn fjórði/g' | perl -pe 's/¾/ þrír fjórðu/g' \
    | perl -pe 's/,([^0-9])/$1/g' | perl -pe 's/&/og/g' \
    | perl -pe 's/([^0-9])\./$1/g' | perl -pe 's/%/% /g' \
    | sed -e 's/\(.*\)/\L\1/g' | perl -pe 's/\/a( |$)/ á ári$1/g' | perl -pe 's/\/s( |$)/ á sekúndu$1/g' \
    | perl -pe 's/( [a-záðéíóúýþæö]+)-?([0-9]+)(\W)/$1 $2$3/g' | perl -pe 's/( [0-9]+%?)\.?-?([a-záðéíóúýþæö]+)(\W)/$1 $2$3/g' \
    | perl -pe 's/([a-záðéíóúýþæö])-([a-záðéíóúýþæö])/$1 $2/g' \
    | perl -pe 's/—|–|-|­//g' | perl -pe 's/\// /g' | sed -e "s/[[:space:]]\+/ /g" | egrep -v "^\s*$" | sed -e 's/^[ \t]*//' > scraped_clean1.tmp

echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
# Might clash with someones middle name. # The module roman comes from Dive into Python
sed -i 's/\([A-Z]\.\?\)–\([A-Z]\)/\1 til \2/g' scraped_clean1.tmp
python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${outdir}/scraped_clean1.tmp', 'r')
text_out = open('${out}', 'w')
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
