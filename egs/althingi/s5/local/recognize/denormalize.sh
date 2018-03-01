#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Denormalize speech recognition transcript

# local/recognize/denormalize.sh <text-input> <denormalized-text-output>

. ./path.sh
. ./cmd.sh

ifile=$1
ofile=$2
dir=$(dirname $(readlink -f $ifile))
utf8syms=text_norm/utf8.syms

echo "Abbreviate"
# Numbers are not in the words.txt file. Hence I can't compose with an utf8-to-words.fst file.
fststringcompile ark:$ifile ark:- | fsttablecompose --match-side=left ark,t:- text_norm/ABBREVIATE.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} > ${dir}/thrax_out.tmp

# Remove uttIDs and map to words
cut -d" " -f2- ${dir}/thrax_out.tmp | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -r "s/[[:space:]]+/ /g" > ${dir}/thrax_out_words.tmp

# Fix ratios, f.ex. "einn 3." -> "1/3"
sed -re 's:\b(einn|einum|eins) ([0-9]{1,3})\.:1/\2:g' \
    -e 's:\b(tveir|tvo|tveimur) ([0-9]{1,3})\.:2/\2:g' \
    -e 's:\b(þrír|þrjá|þrem(ur)?|þriggja) ([0-9]{1,3})\.:3/\3:g' \
    -e 's:\b(fjórir|fjóra|fjórum|fjögurra) ([0-9]{1,3})\.:4/\2:g' \
    -e 's:\bfimm ([0-9]{1,3})\.:5/\1:g' \
    -e 's:\bsex ([0-9]{1,3})\.:6/\1:g' \
    -e 's:\bsjö ([0-9]{1,3})\.:7/\1:g' \
    -e 's:\bátta ([0-9]{1,3})\.:8/\1:g' \
    -e 's:\bníu ([0-9]{1,3})\.:9/\1:g' \
    <${dir}/thrax_out_words.tmp > ${dir}/text_w_ratios.tmp

echo "Uppercase first names when followed by family names (eftirnafn)." 
#F.ex. in Ari trausti Guðmundsson and Unnur brá Konráðsdóttir
sed -i -r "s:\b([^ ]+) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r))\b:\u\1 \2:g" ${dir}/text_w_ratios.tmp

echo "Collapse acronyms pronounced as letters"
# Collapse first the longest acronyms, in case they contain smaller ones.
IFS=$'\n'
for var in $(cat text_norm/acronyms.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
    var1=$(echo $var | sed 's/./& /g' | sed -e 's/ +$//')
    sed -i "s/ $var1/ \U$var /g" ${dir}/text_w_ratios.tmp
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
# 12-13) Rewrite website names
# 14) Rewrite "and or" as "and/or"
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
    -e 's:([0-9]+) og hálf[^ ]*:\1,5:g' \
    -e 's: ([°%‰]):\1:g' \
    -e 's:h t t p s:https:g' -e 's:h t t p:http:g' \
    -e 's:(https?) w w w ([[:alnum:]]+) punktur (is|net|com):\1\://www\.\2.\3:g' -e 's:w w w ([[:alnum:]]+) punktur (is|net|com):www\.\1.\2:g' -e 's:([[:alnum:]]+) punktur (is|net|com):\1.\2:g' \
    -e 's:og eða:og/eða:g' \
    -e 's:(allsherjar|efnahags|stjórnskipunar|umhverfis)( og [^ ]+nefnd):\1-\2:g' \
    -e 's:doktor ([A-ZÁÉÍÓÚÝÞÆÖ]):dr\. \1:g' \
<${dir}/text_w_ratios.tmp > ${dir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/:~/punctuator2/example/local/" <- added to .bashrc and kaldi/tools/env.sh

#set +u # otherwise I have problems with unbound variables
source punctuator2/theano-env/bin/activate

echo "Extract the numbers before punctuation"
python punctuator2/local/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

echo "Punctuate"
cat ${dir}/punctuator_in.tmp | THEANO_FLAGS='device=cpu' python punctuator2/punctuator.py punctuator2/Model_althingi_noCOMMA_h256_lr0.02.pcl ${dir}/punctuator_out.tmp &>${dir}/punctuator.log
wait

echo "Re-insert the numbers"
if [ -s  ${dir}/numlist.tmp ]; then
    python punctuator2/local/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp ${dir}/punctuator_out_wNumbers.tmp
else
    cp ${dir}/punctuator_out.tmp ${dir}/punctuator_out_wNumbers.tmp
fi

deactivate

echo "Convert punctuation tokens back to actual punctuations and capitalize"
# Convert punctuation tokens back to actual punctuations
# Remove space before [°%‰] and in <unk>
# Capitalize sentence beginnings and the first word in the speech
# Fix kl/klst and kr./kíló
sed -re 's/ \.PERIOD/./g; s/ \?QUESTIONMARK/?/g; s/ !EXCLAMATIONMARK/!/g; s/ ,COMMA/,/g; s/ :COLON/:/g' \
    -e 's: ([°%‰]):\1:g' -e 's:< unk >:<unk>:g' \
    -e 's/([^0-9]\.|\?|:|!) ([a-záðéíóúýþæö])/\1 \u\2/g' -e 's/([0-9]{4,}[\.:?!]) ([a-záðéíóúýþæö])/\1 \u\2/g' -e 's:^([a-záéíóúýþæö]):\u\1:' \
    -e 's:([0-9]+) km á klukkustund:\1 km/klst.:g' -e 's:([0-9]+) kr á kíló[^m ]* ?:\1 kr./kg :g' \
    ${dir}/punctuator_out_wNumbers.tmp > ${dir}/punctuator_out_wPuncts.tmp

echo "Insert periods into abbreviations"
fststringcompile ark:"sed 's:.*:1 &:' ${dir}/punctuator_out_wPuncts.tmp |" ark:- | fsttablecompose --match-side=left ark,t:- text_norm/INS_PERIODS.fst ark:- | fsts-to-transcripts ark:- ark,t:- | int2sym.pl -f 2- ${utf8syms} > ${dir}/punctuator_out_wPeriods.tmp

cut -d" " -f2- ${dir}/punctuator_out_wPeriods.tmp | sed -re 's: ::g' -e 's:0x0020: :g' | tr "\n" " " | sed -r "s/[[:space:]]+/ /g" > $ofile  #${dir}/punctuator_out_wPeriods_words.tmp

# # Abbreviate "háttvirtur", "hæstvirtur" and "þingmaður" in some cases
# sed -re 's:([Hh])áttv[^ ]+ (þingm[^ .?:eö]+ [A-ZÁÐÉÍÓÚÝÞÆÖ]):\1v\. \2:g' -e 's:([Hh]v\. ([0-9]+\. )?)þingm[^ .?:eö]+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1þm. \3:g' -e 's:([Hh]æstv)irtur forseti:\1\. forseti:g' < ${dir}/punctuator_out_wPeriods_words.tmp > $ofile

