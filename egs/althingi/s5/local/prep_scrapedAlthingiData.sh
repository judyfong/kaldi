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
    echo "Eg. $0 ~/data/althingi/wp_lang.txt ~/data/althingi/scrapedAlthingiTexts_clean.txt" >&2
    exit 1;
fi

corpus=$1 #~/data/althingi/wp_lang.txt
out=$2 #data/local/lang/scrapedAlthingiTexts_clean.txt
#outdir=$(readlink -f $2);

#mkdir -p $outdir

echo "Lowercase, rewrite and remove punctuations"

# 1) Remove punctuations which is safe to remove, incl. parentheses. NOTE! Change?
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
perl -pe 's/!|\+|\*|×|…|\(|\)|\[|\]|\.\.\.|\.\.|,,|”|“|„|\"|´|__+|\x27|<U+0090>|­|//g' ${corpus} \
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
    | perl -pe 's/—|–|-|­//g'| perl -pe 's/\// /g' | sed -e "s/[[:space:]]\+/ /g" | egrep -v "^\s*$" | sed -e 's/^[ \t]*//' > ${out}


exit 0
