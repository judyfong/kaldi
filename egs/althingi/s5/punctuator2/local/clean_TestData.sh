#!/bin/bash -eu

set -o pipefail

# 2016 Inga Rún
# Clean the scraped althingi texts for use in a language model

if [ $# -ne 3 ]; then
    echo "Usage: $0 <texts-to-use-in-LM> <output-clean-texts>" >&2
    echo "Eg. $0 ~/data/althingi/postprocessing/text16_noXML.tmp text16_for_punctRestoring.dev.txt text16_for_punctRestoring.test.txt" >&2
    exit 1;
fi

corpus=$1 
out_dev=$2
out_test=$3
#outdir=$(readlink -f $2);

#mkdir -p $outdir

# echo "Rewrite roman numerals to numbers" # Enough to rewrite X,V and I based numbers.
perl -pe 's/([A-Z]\.?)–([A-Z])/$1 til $2/g' ${corpus} > roman.tmp
python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('roman.tmp', 'r')
text_out = open('noRoman.tmp', 'w')
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


echo "Rewrite and remove punctuations that I'm not trying to learn how to restore"

# 1) Remove punctuations that I'm not trying to learn how to restore, incl. parentheses and their content.
# 2) Fix errors like: "bla bla .Bla bla"
# 3) Add missing space between sentences,
# 3) Rewrite ".is" to " punktur is "
# 4) Rewrite en dash (x96) and regular dash to " til ", if sandwitched between words or numbers,
# 5) Swap dashes and slashes out for a space,
# 6) Rewrite vulgar fractions,
# 7) Rewrite &,
# 8) Add space around %,‰, ° and º so that they will be taken as part of the vocabulary.
# 9) Remove periods inside abbreviations and periods after abbreviated middle names,
# 10) Remaining punctuations that are not ".,:?!" are swapped out for a space, change spaces to one between words, remove empty lines and remove leading spaces and write.    
perl -pe 's/\+|\*|×|…|\([^\)]*\)|\[|\]|\.\.\.|,,|”|“|„|\"|´|__+|\x27|<U+0090>|­||«|»|¬|<U+2015>//g' noRoman.tmp \
    | perl -pe 's/ \.([^\.])/\. $1/g' \
    | sed -e 's/\([^ A-ZÁÐÉÍÓÚÝÞÆÖ]\)\([A-ZÁÐÉÍÓÚÝÞÆÖ]\)/\1 \2/g' | perl -pe 's/([^0-9 ][^0-9 ,–])([0-9])/$1 $2/g' \
    | perl -pe 's/\.(is|net|com)(\W)/ punktur $1$2/g' \
    | perl -pe 's/([^ ])–([^ ])/$1 til $2/g' | perl -pe 's/([0-9\.%])-([0-9])/$1 til $2/g' \
    | perl -pe 's/—|–|-|­| |\// /g' \
    | perl -pe 's/¼/ einn fjórði/g' | perl -pe 's/½/ hálfur/g' | perl -pe 's/¾/ þrír fjórðu/g' \
    | sed -e 's/ \([%‰°º]\|[°º]c\)/\1 /g' \
    | perl -pe 's/\.([a-záðéíóúýþæö])/$1/g' | sed -e 's/ \([A-ZÁÐÉÍÓÚÝÞÆÖ]\)\. / \1 /g' \
    | sed -e 's/[^ ]*\([^a-yáðéíóúýþæöA-YÁÉÍÓÚÝÞÆÖ0-9\.,?!:; %‰°º&]\)[^ ]*/ /g' > noRoman.punct1.tmp


echo "Remove periods after abbreviations"
# NOTE! I should switch the pythone script out for a bash script I think
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_lexicon.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u > abbr_lex.tmp
python3 ~/punctuator2/example/local/remove_abbr_period.py noRoman.punct1.tmp abbr_lex.tmp noRoman.punct2.tmp

echo "Write to dev and test files"
#tr "\n" " " < noRoman.punct2.tmp | perl -pe 's/([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])([\.?!]) /$1$2\n/g' | sed -e 's/\(.*\)/\L\1/g' > noRoman.punct3.tmp

nlines_half=$(echo $((($(wc -l noRoman.punct2.tmp | cut -d" " -f1)+1)/2)))
head -n $nlines_half noRoman.punct2.tmp > $out_dev
head -n -$nlines_half noRoman.punct2.tmp > $out_test

exit 0
