#!/bin/bash -eu

set -o pipefail

# Take in the texts that have been cleaned for the punctuation restoration process, since they still contain all EOS punctuations, which I can use to split the text. Otherwise, some weird n-grams are formed.

# I need to clean away punctuations and expand abbreviations and numbers. I have to split lines also when the last word is a number
infile=~/data/althingi/postprocessing/text_w_t130_for_punctRestoring.train.txt
outfile=~/data/althingi/pronDict_LM/LMtext_w_t130_split_on_EOS.txt
outdir=$(dirname $outfile);

# 1) Rewrite fractions
# 2) Rewrite time
# 3) Rewrite law numbers
# 4-5) Remove punctuations which is safe to remove
# 6) Remove "ja" from numbers written like "22ja"
# 7) Rewrite [ck]?m[23] to [ck]?m[²³] and "kV" to "kw"
# 8) Add missing space between sentences,
# 9) Rewrite website names,
# 10) In an itemized list, lowercase what comes after the numbering.
# 11) Rewrite en dash (x96) as " til ", if sandwitched between words or numbers,
# 12) Rewrite thousands and millions, f.ex. 3.500 to 3500,
# 13) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
# 14 Rewrite vulgar fractions
# 15) Remove "," when not followed by a number or when not preceded by a number
# 16) Remove periods in lists itemized using letters
# 17) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
# 18) Change dashes and remaining slashes out for space
# 19) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
# 20) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
# 21) Fix spacing around % and degrees celsius and add space in a number starting with a zero
# 22) Remove remaining punctuations and weird words, numbers longer than 9 characters (temporary till change expand.sh)
# 23) Remove periods at the beginning of lines, fix spacing and remove empty lines
sed -re 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
    -e 's:([0-9])\:([0-9][0-9]):\1 \2:g' \
    -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' \
    -e 's:\:|;|,+ | ,+|,\.| |__+: :g' \
    -e 's:([0-9]+)ja\b:\1:g' \
    -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: kV : kw :g' -e 's:Wst:\L&:g' \
    -e 's:\b([^ ]*[^ A-ZÁÐÉÍÓÚÝÞÆÖ])([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2:g' \
    -e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
    -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \L\2:g' \
    -e 's:([^ ])–([^ ]):\1 til \2:g' \
    -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
    -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
    < ${infile} \
    | perl -pe 's/\b(0(?!,5))/$1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
    | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
          -e 's:,([^0-9]|$): \1:g' -e 's:([^0-9]),:\1 :g' \
	  -e 's: ([abdðeéfghijklmnoóprstuúvþæö])\. : \1 :g' \
	  -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
	  -e 's:—|–|/|\:|;: :g' \
	  -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' -e 's:([0-9]+)\.([0-9]+%?)\.?:\1 \2 :g' \
	  -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ]+)\b:\1 \2:g' \
	  -e 's: +([;!%‰°º²³]):\1:g' -e 's:([°º]) c :\1c :g' -e 's: 0([0-9]): 0 \1:g' \
	  -e 's/[^a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ0-9\.,?! %‰°º²³]+//g' -e 's/\b[^ ]*[a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ]+[0-9]+[^ ]*/ /g' -e 's:[0-9]{10,}:<unk>:g' \
	  -e 's:^\. *::g' -e 's/[[:space:]]+/ /g' \
    | grep -v "^\s*$" \
	   > ${outdir}/LMtext_noPuncts.txt

echo "Expand some abbreviations, incl. 'hv.' and 'þm.' in certain circumstances"
python3 local/replace_abbr_acro.py ${outdir}/LMtext_noPuncts.txt ${outdir}/LMtext_exp1.txt # Switch out for a nicer solution
# Use Anna's code
python3 local/althingi_replace_plain_text.py ${outdir}/LMtext_exp1.txt ${outdir}/LMtext_exp2.txt

# Split lines on an EOS marker, remove " ... " and
# split on "bla.[.?]", "bla . bla" and "bla .. bla"
# change spaces to one between words and remove empty lines.
sed -re 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]|[0-9]{4,}|[%‰°º²³])([\.?!]+)( |$):\1\n:g' < ${outdir}/LMtext_exp2.txt | sed -re 's/ +\.\.\. +/ /g' -e $'s/ *\.[\.\?]? +/\\\n/g' -e 's/[[:space:]]+/ /g' | grep -v "^\s*$" > ${outfile}


