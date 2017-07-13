#!/bin/bash -eu

set -o pipefail

# 2017 Inga Rún Helgadóttir
# Denormalize speech recognition transcript

# local/denormalize.sh <text-input> <denormalized-text-output>

ifile=$1
ofile=$2

dir=$(dirname $(readlink -f $ifile))

echo "Abbreviate"
# An implementation of thraxrewrite-tester that takes in a file and returns an output file where the option with the lowest weight is chosen
thraxrewrite-fileio --far=local/abbreviate.far --rules=ABBREVIATE --noutput=1 --input_mode=utf8 --output_mode=utf8 $ifile ${dir}/thrax_out.tmp

echo "Fix casing in Ari trausti Guðmundsson and Unnur brá Konráðsdóttir for exemple"
sed -i "s/\b\([^ ]\+\) \([A-ZÁÉÍÓÚÝÞÆÖ][^ ]\+\(s[oy]ni\?\|dótt[iu]r\)\)\b/\u\1 \2/g" ${dir}/thrax_out.tmp

echo "Collapse acronyms pronounced as letters"
# Collapse first the longest acronyms, in case they contain smaller ones.
IFS=$'\n'
for var in $(cat data/acronyms.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
    var1=$(echo $var | sed 's/./& /g' | sed -e 's/ +$//')
    sed -i 's/'$var1'/\U'$var' /g' ${dir}/thrax_out.tmp
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
sed -e "s/[[:space:]]\+/ /g" ${dir}/thrax_out.tmp \
    | perl -pe 's:(\d+) (frá )?(\d+) (EBE|EB|ESB):$1/$3/\U$4:g' \
    | perl -pe 's:nr (\d+) (frá )?(\d+):nr $1/$3:g' \
    | perl -pe 's:(\d+) til (\d+):$1–$2:g' \
    | perl -pe 's/kl (\d+) (\d+)/kl $1:$2/g' \
    | perl -pe 's/(\d+) komma (\d+) ?(\d{1,2})/$1,$2$3/g' \
    | perl -pe 's/(\d+) komma (\d+) ([^\d]{2,})/$1,$2 $3/g' \
    | perl -pe 's/(\d+,\d+) (\d{1,2}[^,])/$1$2/g' \
    | perl -pe 's/(\d+) og hálf\w*/$1,5/g' \
    | perl -pe 's/ ([°%‰])/$1/g' \
    | perl -pe 's/(\w+) punktur (is|net|com)/$1.$2/g' \
    | perl -pe 's/og eða/og\/eða/g' \
    | sed 's/\([^ ]\+\)\( og [^ ]\+nefnd\)/\1-\2/g' > ${dir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/:~/punctuator2/example/local/" <- added to .bashrc and kaldi/tools/env.sh

set +u # otherwise I have problems with unbound variables
cd ~/punctuator2
source theano-env/bin/activate

echo "Extract the numbers before punctuation"
srun python ~/punctuator2/example/local/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

echo "Punctuate"
srun sh -c "cat ${dir}/punctuator_in.tmp | THEANO_FLAGS='device=cpu' python ~/punctuator2/punctuator.py ~/punctuator2/Model_althingi_CS_h256_lr0.02.pcl ${dir}/punctuator_out.tmp &>${dir}/punctuator.log"
wait

echo "Re-insert the numbers"
if [ -s  ${dir}/numlist.tmp ]; then
    srun python ~/punctuator2/example/local/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp ${dir}/punctuator_out_wNumbers.tmp
else
    cp ${dir}/punctuator_out.tmp ${dir}/punctuator_out_wNumbers.tmp
fi

deactivate
set -u
cd ~/kaldi/egs/althingi/s5

echo "Convert punctuation tokens back to actual punctuations"
sed -r 's/ \.PERIOD/./g; s/ \?QUESTIONMARK/?/g; s/ !EXCLAMATIONMARK/!/g; s/ ,COMMA/,/g; s/ :COLON/:/g' ${dir}/punctuator_out_wNumbers.tmp | perl -pe 's/ ([°%‰])/$1/g' > ${dir}/punctuator_out_wPuncts.tmp

# Some things I want to abbreviate if preceded or followed by a name (i.e. by an uppercase letter) f.ex. "doktor" and "þingmaður"
sed -r 's:doktor ([A-ZÁÉÍÓÚÝÞÆÖ]):dr\. \1:g' ${dir}/punctuator_out_wPuncts.tmp > ${dir}/text.dr.tmp

echo "Capitalize sentence beginnings and add periods to abbreviations."
# Implement! Regex for capitalization and thrax for the periods.
#sed -e 's/\([^0-9][\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' ${dir}/text_wCap.tmp | sed -e 's/\([0-9]\{4\}[\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' > ${dir}/denorm_BOScap.tmp
sed -re 's/([^0-9]\.|\?|:|!) ([a-záðéíóúýþæö])/\1 \u\2/g' -e 's/([0-9]{4}[\.:?!]) ([a-záðéíóúýþæö])/\1 \u\2/g' ${dir}/text.dr.tmp > ${dir}/denorm_BOScap.tmp

perl -pe 's:(\d+) km á klukkustund:$1 $2/klst.:g' ${dir}/denorm_BOScap.tmp | perl -pe 's:(\d+) kr á kíló[^m ]* ?:$1 $2\./kg :g' > ${dir}/denorm_measure.tmp

echo "Insert periods into abbreviations"
thraxrewrite-fileio --far=local/abbreviate.far --rules=INS_PERIODS --noutput=1 --input_mode=utf8 --output_mode=utf8 ${dir}/denorm_measure.tmp $ofile

# # þingm regex
# sed -e 's/\([Hh]v\.\) \([0-9\. ]*\)þingm\w\+ \([A-ZÁÉÍÓÚÝÞÆÖ]\)/\1 \2þm\. \3/g' ${dir}/denorm_periods.tmp > ${dir}/$ofile
