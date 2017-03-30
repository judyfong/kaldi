#!/bin/bash -eu

set -o pipefail

# 2017 Inga Rún Helgadóttir
# Denormalize speech recognition transcript

# local/denormalize.sh <text-input> <denormalized-text-output>

ifile=$1
ofile=$2

dir=$(dirname $(readlink -f $ifile))

# An implementation of thraxrewrite-tester that takes in a file and returns an output file where the option with the lowest weight is chosen
thraxrewrite-fileio --far=local/abbreviate.far --rules=ABBREVIATE --noutput=1 --input_mode=utf8 --output_mode=utf8 $ifile ${dir}/thrax_out.tmp

# 1) Change spaces to one between words.
# 2-3) Rewrite law numbers
# 4) Rewrite intervals
# 5) Rewrite, f.ex. "2005 to 2007" as "2005—2007"
# 6) Rewrite time, f.ex. "kl 13 35" to "kl 13:35"
# 7-8) Rewrite decimal numbers
# 9) Rewrite f.ex. "4 and half" to "4,5"
# 10) Remove space in front of °, % and ‰
# 11) Rewrite website names
# 12) Rewrite "and or" as "and/or"
sed -e "s/[[:space:]]\+/ /g" ${dir}/thrax_out.tmp \
    | perl -pe 's:(\d+) (frá )?(\d+) (ebe|eb|esb):$1/$3/\U$4:g' \
    | perl -pe 's:nr (\d+) (frá )?(\d+):nr $1/$3:g' \
    | perl -pe 's:(\d+) til (\d+):$1—$2:g' \
    | perl -pe 's/kl (\d+) (\d+)/kl $1:$2/g' \
    | perl -pe 's/(\d+) komma (\d+) ?(\d{1,2}|[^\d]{2,})/$1,$2$3/g' \
    | perl -pe 's/(\d+,\d+) (\d{1,2}[^,]|[^\d]{2,})/$1$2/g' \
    | perl -pe 's/(\d+) og hálf\w*/$1,5/g' \
    | perl -pe 's/ ([°%‰])/$1/g' \
    | perl -pe 's/(\w+) punktur (is|net|com)/$1.$2/g' \
    | perl -pe 's/og eða/og\/eða/g' > ${dir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/:~/punctuator2/example/local/" <- added to .bashrc and kaldi/tools/env.sh

set +u # otherwise I have problems with unbound variables
cd ~/punctuator2
source theano-env/bin/activate
srun python ~/punctuator2/example/local/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

srun --gres gpu:1 sh -c "cat ${dir}/punctuator_in.tmp | python ~/punctuator2/punctuator.py ~/punctuator2/Model_althingi_h256_lr0.02.pcl ${dir}/punctuator_out.tmp &>${dir}/punctuator.log" &
wait

if [ -s  ${dir}/numlist.tmp ]; then
    srun python ~/punctuator2/example/local/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp ${dir}/punctuator_out_wNumbers.tmp
else
    cp ${dir}/punctuator_out.tmp ${dir}/punctuator_out_wNumbers.tmp
fi

deactivate
set -u
cd ~/kaldi/egs/althingi/s5

# Convert punctuation tokens back to actual punctuations
sed -r 's/ \.PERIOD/./g; s/ \?QUESTIONMARK/?/g; s/ !EXCLAMATIONMARK/!/g; s/ ,COMMA/,/g; s/ :COLON/:/g' ${dir}/punctuator_out_wNumbers.tmp > ${dir}/punctuator_out_wPuncts.tmp

# Capitalize proper names, location and organization names
# Implement!

# Some things I want to abbreviate if preceded or followed by a name (i.e. by an uppercase letter) f.ex. "doktor" and "þingmaður"
# I will wait with that implementation for a while and do the following in the meanwhile
sed -e 's/doktor \([a-záðéíóúýþæö]\{2,\}\)/dr\. \1/g' ${dir}/punctuator_out_wPuncts.tmp > ${dir}/text.dr.tmp

cut -f1 data/name_id_2017.txt | tr " " "\n" | sort -u > ${dir}/name.tmp
srun python local/capitalize_names.py ${dir}/text.dr.tmp ${dir}/name.tmp ${dir}/text_wCap.tmp

# Capitalize sentence beginnings and add periods to abbreviations.
# Implement! Regex for capitalization and thrax for the periods.
#sed -e 's/\([^0-9][\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' ${dir}/text_wCap.tmp | sed -e 's/\([0-9]\{4\}[\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' > ${dir}/denorm_BOScap.tmp
sed -e 's/\([^0-9]\.\|\?\|:\|!\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' ${dir}/text_wCap.tmp | sed -e 's/\([0-9]\{4\}[\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' > ${dir}/denorm_BOScap.tmp

perl -pe 's:(\d+) km á klukkustund:$1 $2/klst.:g' ${dir}/denorm_BOScap.tmp | perl -pe 's:(\d+) kr á kíló[^m ]* ?:$1 $2\./kg :g' > ${dir}/denorm_measure.tmp

thraxrewrite-fileio --far=local/abbreviate.far --rules=INS_PERIODS --noutput=1 --input_mode=utf8 --output_mode=utf8 ${dir}/denorm_measure.tmp $ofile

# # þingm regex
# sed -e 's/\([Hh]v\.\) \([0-9\. ]*\)þingm\w\+ \([A-ZÁÉÍÓÚÝÞÆÖ]\)/\1 \2þm\. \3/g' ${dir}/denorm_periods.tmp > ${dir}/$ofile
