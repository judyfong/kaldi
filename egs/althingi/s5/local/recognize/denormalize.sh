#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Denormalize speech recognition transcript

# local/recognize/denormalize.sh <text-input> <denormalized-text-output>

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

ifile=$1
ofile=$2
dir=$(dirname $(readlink -f $ifile))
utf8syms=text_norm/utf8.syms

echo "Abbreviate"
# Numbers are not in the words.txt file. Hence I can't compose with an utf8-to-words.fst file.
fststringcompile ark:$ifile ark:- | fsttablecompose --match-side=left ark,t:- text_norm/ABBREVIATE.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} > ${dir}/thrax_out.tmp

# Remove uttIDs and map to words
cut -d" " -f2- ${dir}/thrax_out.tmp | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -r "s/[[:space:]]+/ /g" > ${dir}/thrax_out_words.tmp

echo "Uppercase first names when followed by family names (eftirnafn) and capitalize abbreviated middle names" 
#F.ex. in Ari trausti Guðmundsson, Unnur brá Konráðsdóttir, Sigríður á Andersen
sed -re "s:\b([A-ZÁÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([a-záðéíóúýþæö]) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\1 \u\2\. \3:g" -e "s:\b([^ ]+) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g" <${dir}/thrax_out_words.tmp > ${dir}/text_propnames.tmp

echo "Collapse acronyms pronounced as letters"
# Collapse first the longest acronyms, in case they contain smaller ones.
IFS=$'\n'
for var in $(cat text_norm/acronyms.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
    var1=$(echo $var | sed 's/./& /g' | sed -e 's/ +$//')
    sed -i "s/ $var1/ \U$var /g" ${dir}/text_propnames.tmp
done

echo "Rewrite"
# 1) Change spaces to one between words.
# 2-3) Rewrite law numbers
# 4) Rewrite intervals
# 5) Rewrite, f.ex. "2005 to 2007" as "2005—2007"
# 6) Rewrite time, f.ex. "kl 13 35" to "kl 13:35"
# 7-9) Rewrite decimal numbers
# 10) Fix ratios
# 11) Remove space in front of °, % and ‰
# 12-13) Rewrite website names
# 14) Rewrite "and or" as "and/or"
# 15) Fix Rás 1 and Stöð 2
# 15) Add a hyphen in f.ex. allsherjar- og menntamálanefnd
# 16) Abbreviate "doktor" if followed by a proper name
sed -re "s/[[:space:]]\+/ /g" \
    -e 's:([0-9]+) (frá )?([0-9]+) (EBE|EB|ESB):\1/\3/\4:g' \
    -e 's:nr ([0-9]+) (frá )?([0-9]+):nr \1/\3:g' \
    -e 's:([0-9]+) til ([0-9]+):\1–\2:g' \
    -e 's/kl ([0-9]+) ([0-9]+)/kl \1:\2/g' \
    -e 's:([0-9]+) komma ([0-9]+) ?([0-9]{1,2}):\1,\2\3:g' \
    -e 's:([0-9]+) komma ([0-9]+) ([^0-9]{2,}):\1,\2 \3:g' \
    -e 's:([0-9]+,[0-9]+) ([0-9]{1,2}[^,]):\1\2:g' \
    -e 's:\b([0-9]) ([0-9])\.:\1/\2:g' \
    -e 's: ([°%‰]):\1:g' \
    -e 's:h t t p s:https:g' -e 's:h t t p:http:g' \
    -e 's:(https?) w w w ([[:alnum:]]+) punktur (is|net|com):\1\://www\.\2.\3:g' -e 's:w w w ([[:alnum:]]+) punktur (is|net|com):www\.\1.\2:g' -e 's:([[:alnum:]]+) punktur (is|net|com):\1.\2:g' \
    -e 's:og eða:og/eða:g' \
    -e 's:\b([Rr]ás) eitt\b:\u\1 1:g' -e 's:\b([Rr]ás) tvö\b:\u\1 2:g' -e 's:\b([Ss]töð) tvö\b:\u\1 2:g' \
    -e 's:(allsherjar|efnahags|stjórnskipunar|umhverfis)( og [^ ]+nefnd):\1-\2:g' \
    -e 's:([Dd])oktor ([A-ZÁÉÍÓÚÝÞÆÖ]):\1r \2:g' \
<${dir}/text_propnames.tmp > ${dir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/" <- added to theano-env/bin/activate and kaldi/tools/env.sh

#set +u # otherwise I have problems with unbound variables
#source punctuator2/theano-env/bin/activate
source activate thenv

echo "Extract the numbers before punctuation"
python local/punctuator/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

echo "Punctuate"
cat ${dir}/punctuator_in.tmp | THEANO_FLAGS='device=cpu' python punctuator2/punctuator.py punctuator2/Model_althingi_noCOMMA_h256_lr0.02.pcl ${dir}/punctuator_out.tmp &>${dir}/punctuator.log
wait

echo "Re-insert the numbers"
if [ -s  ${dir}/numlist.tmp ]; then
    python local/punctuator/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp ${dir}/punctuator_out_wNumbers.tmp
else
    cp ${dir}/punctuator_out.tmp ${dir}/punctuator_out_wNumbers.tmp
fi

echo "Convert punctuation tokens back to actual punctuations and capitalize"
# Convert punctuation tokens back to actual punctuations and capitalize sentence beginnings
# Capitalize the first word in the speech
# Insert a period at the end of the speech
# Fix km/klst and kr./kíló
# Remove space before [°%‰] and in <unk>
sed -re 's/ \.PERIOD ([^ ])/. \u\1/g' -e 's/ \?QUESTIONMARK ([^ ])/? \u\1/g' -e 's/ !EXCLAMATIONMARK ([^ ])/! \u\1/g' -e 's/ :COLON ([^ ])/: \u\1/g' \
    -e 's/ \.PERIOD/./g; s/ \?QUESTIONMARK/?/g; s/ !EXCLAMATIONMARK/!/g; s/ ,COMMA/,/g; s/ :COLON/:/g; s/ ;SEMICOLON/;/g' \
    -e 's:^([a-záéíóúýþæö]):\u\1:' \
    -e 's:([0-9]+) km á klukkustund:\1 km/klst.:g' -e 's:([0-9]+) kr á kíló[^m ]* ?:\1 kr./kg :g' \
    -e 's: ([°%‰]):\1:g' -e 's:< unk >:<unk>:g' \
    ${dir}/punctuator_out_wNumbers.tmp > ${dir}/punctuator_out_wPuncts.tmp

echo "Insert periods into abbreviations and insert period at the end of the speech"
fststringcompile ark:"sed 's:.*:1 &:' ${dir}/punctuator_out_wPuncts.tmp |" ark:- | fsttablecompose --match-side=left ark,t:- text_norm/INS_PERIODS.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} | cut -d" " -f2- | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -re "s/ +/ /g" -e 's:\s*$:.:' > ${dir}/punctuator_out_wPeriods.tmp

# # Insert paragraph breaks using a paragraph model and before the appearance of ". [herra|frú|virðulegur|hæstv] forseti."
cat ${dir}/punctuator_out_wPeriods.tmp | THEANO_FLAGS='device=cpu' python paragraph/paragrapher.py paragraph/Model_althingi_paragraph_may18_h256_lr0.02.pcl ${dir}/paragraphed_tokens.tmp
sed -re "s: EOP :\n:g"  -e 's:\. ([^ ]+ forseti\.):\.\n\1:g' ${dir}/paragraphed_tokens.tmp > $ofile

# Insert paragraph breaks before the appearance of  ". [herra|frú|virðulegur|hæstv] forseti."
#sed -r 's:\. ([^ ]+ forseti\.):\.\n\1:g' < ${dir}/punctuator_out_wPeriods.tmp > $ofile

# # Maybe fix the casing of prefixes?
# cat /data/althingi/lists/forskeyti.txt /data/althingi/lists/forskeyti.txt | sort | awk 'ORS=NR%2?":":"\n"' | sed -re 's/^.*/s:&/' -e 's/$/:gI/g' > prefix_sed_pattern.tmp

# # Fix the casing of known named entities
# /bin/sed -f ${dir}/ner_sed_pattern.tmp file > file_out

# # Abbreviate "háttvirtur", "hæstvirtur" and "þingmaður" in some cases
# sed -re 's:([Hh])áttv[^ ]+ (þingm[^ .?:eö]+ [A-ZÁÐÉÍÓÚÝÞÆÖ]):\1v\. \2:g' -e 's:([Hh]v\. ([0-9]+\. )?)þingm[^ .?:eö]+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1þm. \3:g' -e 's:([Hh]æstv)irtur forseti:\1\. forseti:g' < ${dir}/punctuator_out_wPeriods_words.tmp > $ofile

#deactivate
source deactivate
