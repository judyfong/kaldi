#!/bin/bash -e

. ./path.sh

# NOTE! This file is just crap. Created to test the second stage training. If I am ever going to use a two stage punctuation model I need to do this properly

if [ $# -ne 3 ]; then
  echo "This script creates pause annotated data for 2nd stage punctuation modelling."
  echo ""
  echo "Usage: $0 <alignment-directory> <input-text-data> <segmented-data>" >&2
  echo "e.g.: $0 exp/tri4_ali punctuation/data/second_stage/althingi.all_sept2017_without_pauses.txt data/all_sept2017_reseg_filtered" >&2
  exit 1;
fi

ali_dir=$1; shift # Should be $exp/tri4_ali according to run.sh
text=$1; shift
reseg=$1
dir=$(dirname $text)
intermediate=$dir/intermediate
mkdir -p $dir/log $intermediate

lang=$(ls -td $root_lm_modeldir/20*/lang | head -n1)

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# I have alignment files. Use the alignment information from there to extract the silences

utils/slurm.pl JOB=1:100 ${ali_dir}/log/ali_to_ctm.JOB.log ali-to-phones --ctm-output ${ali_dir}/final.mdl ark:"gunzip -c ${ali_dir}/ali.JOB.gz|" -> ${ali_dir}/ali.JOB.ctm &
wait

for i in ${ali_dir}/log/ali_to_ctm.*.log; do egrep "rad[0-9]" $i >> $intermediate/merged_ctm_all.txt; done

# Change from int to sym:
int2sym.pl -f 5 $lang/phones.txt ${intermediate}/merged_ctm_all.txt > ${intermediate}/merged_ctm_all_sym.txt

# Let the phones of each word be in a single line:
sed -re "s:.*? ([^ ]+_I):\1:" -e "s:^[^ ]+ 1 (.*?) ([^ ]+_E):\2 \1:" ${intermediate}/merged_ctm_all_sym.txt | perl -pe 'chomp if /_[BI]/' | awk '{ if ($5 !="sil" && !match($5, /^.*?_S/)) $NF=""; if ($5 !="sil" && !match($5, /^.*?_S/)) $(NF-1)=""; print}'  > ${intermediate}/merged_ctm_all_sym_edited.txt

# get rid of channel info and start time of each phone/silence
cut -d" " -f1,4- ${intermediate}/merged_ctm_all_sym_edited.txt > ${intermediate}/merged_ctm_all_sym_edited_cut.txt

# Extract information about position and duration of each silence in a segment
python punctuator/local/extract_silence.py ${intermediate}/merged_ctm_all_sym_edited_cut.txt ${intermediate}/sil_all.txt &

cut -d" " -f1 ${intermediate}/sil_all.txt | sort -u > ${intermediate}/sil_uttid.tmp
join -j 1 ${intermediate}/sil_uttid.tmp <(sort -u $text) > ${intermediate}/text_newdata.txt

join -j 1 <(cut -d" " -f1 ${intermediate}/text_newdata.txt) <(sort -u ${intermediate}/sil_all.txt) > ${intermediate}/sil_newdata.txt

# Weave together the silence and text info.
python punctuator/local/add_sil_to_segm.py ${intermediate}/text_newdata.txt ${intermediate}/sil_newdata.txt ${intermediate}/pause_annotated_text_newdata.txt

# Next I need to get the punctuation tokens as well. I need to make is such that it reads one speech and respective pause annotated segments at a time.
source venv3/bin/activate
IFS=$'\n'
outfile1=${intermediate}/althingi.train_$(sed -r 's/[^ ]+[_.]([a-z]*[0-9]+)[_.][^ ]+/\1/gI' <(echo $text))_pause_punct.txt
touch $outfile
{ time 
for speech in $(cat $text); do
    uttid=$(echo $speech | cut -d" " -f1)
    grep $uttid ${intermediate}/pause_annotated_text_newdata.txt > ${dir}/segments.tmp
    python punctuator/local/segment_matching.py "$speech" ${dir}/segments.tmp $outfile1 
done } &>> $dir/log/segment_matching_time.log
deactivate

# Fixing of the output:
# 1) Not all speeches start in a new line.
# 2) When applying the punctuation model the "%" is included in <NUM> hence I need to collapse them:
sed -re 's/>([^ ]+?-rad)/>\n\1/g' \
    -e 's:<NUM> <sil=[0-9.]+> % (<sil=[0-9.]+>):<NUM> \1:g' \
    < $outfile1 \
    | sort -u > ${outfile1}.edited

shuf -n 4000 ${outfile1}.edited > $dir/althingi.dev.txt
join -j1 <(comm -13 <(cut -d" " -f1 $dir/althingi.dev.txt | sort -u) <(cut -d" " -f1 ${outfile1}.edited | sort -u)) <(sort -u ${outfile1}.edited) > $dir/althingi.train_test.txt
shuf -n 4000 $dir/althingi.train_test.txt > $dir/althingi.test.txt
join -j1 <(comm -13 <(cut -d" " -f1 $dir/althingi.test.txt | sort -u) <(cut -d" " -f1 $dir/althingi.train_test.txt | sort -u)) <(sort -u $dir/althingi.train_test.txt) > $dir/althingi_train.txt
rm $dir/althingi.train_test.txt
cut -d" " -f2- $dir/althingi.dev.txt > $tmp/dev.tmp && mv $tmp/dev.tmp $dir/althingi.dev.txt
cut -d" " -f2- $dir/althingi.test.txt > $tmp/test.tmp && mv $tmp/test.tmp $dir/althingi.test.txt
cut -d" " -f2- $dir/althingi.train.txt > $tmp/train.tmp && mv $tmp/train.tmp $dir/althingi.train.txt

exit 0;
