#!/bin/bash -eu

set -o pipefail

# 2017 Inga Rún Helgadóttir
# Denormalize speech recognition transcript

# local/denormalize.sh <text-input> <denormalized-text-output>

datadir=$1
ifile=$2
ofile=$3

# An implementation of thraxrewrite-tester that takes in a file and returns an output file where the option with the lowest weight is chosen
thraxrewrite-fileio --far=local/abbreviate.far --rules=ABBREVIATE --noutput=1 --input_mode=utf8 --output_mode=utf8 ${datadir}/$ifile ${datadir}/thrax_out.tmp

# Rewrite law numbers, time, decimals, remove space before '°%‰' and rewrite website names (maybe wait with that till after the punctuator step??)
perl -pe 's:(\d+) (frá )?(\d+) (eb|ebe|esb):$1/$3/\U$4:g' ${datadir}/thrax_out.tmp | perl -pe 's:nr (\d+) (frá )?(\d+):nr $1/$3:g' | perl -pe 's:(\d+) til (\d+):$1–$2:g' | perl -pe 's/kl (\d+) (\d+)/kl $1:$2/g' | perl -pe 's/(\d+) komma (\d+)/$1,$2/g' | perl -pe 's/(\d+) og hálf\w*/$1,5/g' | perl -pe 's/ ([°%‰])/$1/g' | perl -pe 's/(\w+) punktur (is|net|com)/$1\.$2/g' | perl -pe 's/og eða/og\/eða/g' > ${datadir}/denorm1.tmp

# Restore punctuations
#export PYTHONPATH="${PYTHONPATH}:~/.local/lib/python2.7/site-packages/:~/punctuator2/:~/punctuator2/example/local/"
cd ~/punctuator2
source theano-env/bin/activate
#dir=$(readlink -f ${datadir})
dir=~/kaldi/egs/althingi/s5/data/reco_test_hires/decode
srun python ~/punctuator2/example/local/saving_numbers.py ${dir}/denorm1.tmp ${dir}/punctuator_in.tmp ${dir}/numlist.tmp

srun --gres gpu:1 sh -c 'cat ~/kaldi/egs/althingi/s5/data/reco_test_hires/decode/punctuator_in.tmp | python ~/punctuator2/punctuator.py ~/punctuator2/Model_althingi_h256_lr0.02.pcl ~/kaldi/egs/althingi/s5/data/reco_test_hires/decode/punctuator_out.tmp &>~/kaldi/egs/althingi/s5/data/reco_test_hires/decode/punctuator.log' &

srun python ~/punctuator2/example/local/re-inserting-numbers.py ${dir}/punctuator_out.tmp ${dir}/numlist.tmp 0 ${dir}/punctuator_out_wNumbers.tmp

deactivate
cd ~/kaldi/egs/althingi/s5
# Capitalize proper names, location and organization names
# Implement!

# Some things I want to abbreviate if preceded or followed by a name (i.e. by an uppercase letter) f.ex. "doktor" and "þingmaður"
# I will wait with that implementation for a while and do the following in the meanwhile
sed -e 's/doktor \([a-záðéíóúýþæö]\{2,\}\)/dr\. \1/g' ${datadir}/punctuator_out_wNumbers.tmp > ${datadir}/text.dr.tmp

cut -f1 data/name_id_2017.txt | tr " " "\n" | sort -u > ${datadir}/name.tmp
srun python local/capitalize_names.py ${datadir}/text.dr.tmp ${datadir}/name.tmp ${datadir}/text_wCap.tmp

# Capitalize sentence beginnings and add periods to abbreviations.
# Implement! Regex for capitalization and thrax for the periods.
#sed -e 's/\([^0-9][\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' ${datadir}/text_wCap.tmp | sed -e 's/\([0-9]\{4\}[\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' > ${datadir}/denorm_BOScap.tmp
sed -e 's/\(PERIOD\|QUESTIONMARK\|COLON\|EXCLAMATIONMARK\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' ${datadir}/text_wCap.tmp | sed -e 's/\([0-9]\{4\}[\.:?!]\) \([a-záðéíóúýþæö]\)/\1 \u\2/g' > ${datadir}/denorm_BOScap.tmp

perl -pe 's:(\d+) km á klukkustund:$1 $2/klst.:g' ${datadir}/denorm_BOScap.tmp | perl -pe 's:(\d+) kr á kíló[^m ]* ?:$1 $2\./kg :g' > ${datadir}/denorm_measure.tmp

thraxrewrite-fileio --far=local/abbreviate.far --rules=INS_PERIODS --noutput=1 --input_mode=utf8 --output_mode=utf8 ${datadir}/denorm_measure.tmp ${datadir}/$ofile

# # þingm regex
# sed -e 's/\([Hh]v\.\) \([0-9\. ]*\)þingm\w\+ \([A-ZÁÉÍÓÚÝÞÆÖ]\)/\1 \2þm\. \3/g' ${datadir}/denorm_periods.tmp > ${datadir}/$ofile
