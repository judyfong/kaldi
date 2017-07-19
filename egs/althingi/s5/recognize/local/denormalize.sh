#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Denormalize speech recognition transcript

# local/denormalize.sh <text-input> <denormalized-text-output>

. ./path.sh
. ./cmd.sh

ifile=$1
ofile=$2
dir=$(dirname $(readlink -f $ifile))
utf8syms=/data/althingi/utf8.syms

echo "Abbreviate"
# Numbers are not in the words.txt file. Hence I can't compose with an utf8-to-words.fst file.
fststringcompile ark:$ifile ark:- | fsttablecompose --match-side=left ark,t:- text_norm/ABBREVIATE.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} > ${dir}/thrax_out.tmp

# Remove uttIDs and map to words
cut -d" " -f2- ${dir}/thrax_out.tmp | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -r "s/[[:space:]]+/ /g" > ${dir}/thrax_out_words.tmp

echo "Fix casing in Ari trausti Guðmundsson and Unnur brá Konráðsdóttir for exemple"
sed -i -r "s:\b([^ ]+) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r))\b:\u\1 \2:g" ${dir}/thrax_out_words.tmp

echo "Collapse acronyms pronounced as letters"
# Collapse first the longest acronyms, in case they contain smaller ones.
IFS=$'\n'
for var in $(cat data/acronyms.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
    var1=$(echo $var | sed 's/./& /g' | sed -e 's/ +$//')
    sed -i "s/ $var1/ \U$var /g" ${dir}/thrax_out_words.tmp
done

echo "Rewrite"
# 1) Change spaces to one between words.
# 2-3) Rewrite law numbers
# 4) Rewrite intervals
# 5) Rewrite, f.ex. "2005 to 2007" as "2005—2007"
# 6) Rewrite time, f.ex. "kl 13 35" to "kl 13:35"
# 7-9) Rewrite decimal numbers
# 10) Rewrite f.ex. "4 and half" to "4,5"
# 11) Remove space in front of °, % and ‰
# 12) Rewrite website names
# 13) Rewrite "and or" as "and/or"
# 14) Add a hyphen in f.ex. allsherjar- og menntamálanefnd
# 15) Abbreviate "doktor" if followed by a proper name
sed -re "s/[[:space:]]\+/ /g" \
    -e 's:([0-9]+) (frá )?([0-9]+) (EBE|EB|ESB):\1/\3/\4:g' \
    -e 's:nr ([0-9]+) (frá )?([0-9]+):nr \1/\3:g' \
    -e 's:([0-9]+) til ([0-9]+):\1–\2:g' \
    -e 's/kl ([0-9]+) ([0-9]+)/kl \1:\2/g' \
    -e 's:([0-9]+) komma ([0-9]+) ?([0-9]{1,2}):\1,\2\3:g' \
    -e 's:([0-9]+) komma ([0-9]+) ([^0-9]{2,}):\1,\2 \3:g' \
    -e 's:([0-9]+,[0-9]+) ([0-9]{1,2}[^,]):\1\2:g' \
    -e 's:([0-9]+) og hálf[^ ]*:\1,5:g' \
    -e 's: ([°%‰]):\1:g' \
    -e 's:([[:alnum:]]+) punktur (is|net|com):\1.\2:g' \
    -e 's:og eða:og/eða:g' \
    -e 's:([^ ]+)( og [^ ]+nefnd):\1-\2:g' \
    -e 's:doktor ([A-ZÁÉÍÓÚÝÞÆÖ]):dr\. \1:g' \
<${dir}/thrax_out_words.tmp > ${dir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/:~/punctuator2/example/local/" <- added to .bashrc and kaldi/tools/env.sh

#set +u # otherwise I have problems with unbound variables
source punctuator2/theano-env/bin/activate

echo "Extract the numbers before punctuation"
srun python punctuator2/example/local/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

echo "Punctuate"
srun sh -c "cat ${dir}/punctuator_in.tmp | THEANO_FLAGS='device=cpu' python punctuator2/punctuator.py punctuator2/Model_althingi_CS_h256_lr0.02.pcl ${dir}/punctuator_out.tmp &>${dir}/punctuator.log"
wait

echo "Re-insert the numbers"
if [ -s  ${dir}/numlist.tmp ]; then
    srun python punctuator2/example/local/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp ${dir}/punctuator_out_wNumbers.tmp
else
    cp ${dir}/punctuator_out.tmp ${dir}/punctuator_out_wNumbers.tmp
fi

deactivate

echo "Convert punctuation tokens back to actual punctuations and capitalize"
# Convert punctuation tokens back to actual punctuations
# Remove space before [°%‰] and in <unk>
# Capitalize sentence beginnings
# Fix kl/klst and kr./kíló
sed -re 's/ \.PERIOD/./g; s/ \?QUESTIONMARK/?/g; s/ !EXCLAMATIONMARK/!/g; s/ ,COMMA/,/g; s/ :COLON/:/g' \
    -e 's: ([°%‰]):\1:g' -e 's:< unk >:<unk>:g' \
    -e 's/([^0-9]\.|\?|:|!) ([a-záðéíóúýþæö])/\1 \u\2/g' -e 's/([0-9]{4,}[\.:?!]) ([a-záðéíóúýþæö])/\1 \u\2/g' \
    -e 's:([0-9]+) km á klukkustund:\1 km/klst.:g' -e 's:([0-9]+) kr á kíló[^m ]* ?:\1 kr./kg :g' \
    ${dir}/punctuator_out_wNumbers.tmp > ${dir}/punctuator_out_wPuncts.tmp

echo "Insert periods into abbreviations"
fststringcompile ark:"sed 's:.*:1 &:' ${dir}/punctuator_out_wPuncts.tmp |" ark:- | fsttablecompose --match-side=left ark,t:- text_norm/INS_PERIODS.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} > ${dir}/punctuator_out_wPeriods.tmp

cut -d" " -f2- ${dir}/punctuator_out_wPeriods.tmp | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -r "s/[[:space:]]+/ /g" > ${ofile}

# # þingm regex
# sed -e 's/\([Hh]v\.\) \([0-9\. ]*\)þingm\w\+ \([A-ZÁÉÍÓÚÝÞÆÖ]\)/\1 \2þm\. \3/g' ${dir}/denorm_periods.tmp > ${dir}/$ofile
