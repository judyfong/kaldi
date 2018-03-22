<#!/bin/bash -e

# I have alignment files. Use the alignment information from there to extract the silences

utils/slurm.pl JOB=1:100 exp/reseg_fmllr_ali/log/ali_to_ctm.JOB.log ali-to-phones --ctm-output exp/tri4/final.mdl ark:"gunzip -c exp/reseg_fmllr_ali/ali.JOB.gz|" -> ${exp/reseg_fmllr_ali/ali.JOB.gz%.gz}.c
tm &

for i in ali_to_ctm.*.log; do egrep "rad[0-9]" $i >> merged_ctm_all.txt; done

# Change from int to sym:
int2sym.pl -f 5 data/lang/phones.txt exp/reseg_fmllr_ali/merged_ctm_all.txt > exp/reseg_fmllr_ali/merged_ctm_all_sym.txt

# Let the phones of each word be in a single line:
sed -re "s:.*? ([^ ]+_I):\1:" -e "s:^[^ ]+ 1 (.*?) ([^ ]+_E):\2 \1:" exp/reseg_fmllr_ali/merged_ctm_all_sym.txt | perl -pe 'chomp if /_[BI]/' | awk '{ if ($5 !="sil" && !match($5, /^.*?_S/)) $NF=""; if ($5 !="sil" && !match($5, /^.*?_S/)) $(NF-1)=""; print}'  > exp/reseg_fmllr_ali/merged_ctm_all_sym_edited.txt

# get rid of channel info and start time of each phone/silence
cut -d" " -f1,4- merged_ctm_all_sym_edited.txt > merged_ctm_all_sym_edited_cut.txt

# Extract information about position and duration of each silence in a segment
python local/punctuator/extract_silence.py exp/reseg_fmllr_ali/merged_ctm_all_sym_edited_cut.txt exp/reseg_fmllr_ali/sil_all.txt &

cut -d" " -f1 exp/reseg_fmllr_ali/sil_all.txt | sort -u > exp/reseg_fmllr_ali/sil_uttid.tmp
join -j 1 exp/reseg_fmllr_ali/sil_uttid.tmp <(sort -u data/all_reseg_filtered_Sept2017_ID/text) > exp/reseg_fmllr_ali/text_newdata.txt

join -j 1 <(cut -d" " -f1 exp/reseg_fmllr_ali/text_newdata.txt) <(sort -u exp/reseg_fmllr_ali/sil_all.txt) > exp/reseg_fmllr_ali/sil_newdata.txt

# Weave together the silence and text info.
python local/punctuator/add_sil_to_segm.py exp/reseg_fmllr_ali/text_newdata.txt exp/reseg_fmllr_ali/sil_newdata.txt exp/reseg_fmllr_ali/pause_annotated_text_newdata.txt

# Next I need to get the punctuation tokens as well. I need to make is such that it reads one speech and respective pause annotated segments at a time.
source py3env/bin/activate
IFS=$'\n'
dir=punctuator2/example/out_cs
touch ${dir}/althingi.train_Sept2017_pause_punct.txt
{ time 
for speech in $(cat ${dir}/althingi.train_Sept2017_pause_simpleExp.txt); do
    uttid=$(echo $speech | cut -d" " -f1)
    grep $uttid exp/reseg_fmllr_ali/pause_annotated_text_newdata.txt > ${dir}/segments.tmp
    python local/punctuator/segment_matching.py "$speech" ${dir}/segments.tmp ${dir}/althingi.train_Sept2017_pause_punct.txt 
done } &>> segment_matching_time.log
deactivate

# Fixing of the output:
# 1) Not all speeches start in a new line.
# 2) When applying the punctuation model the "%" is included in <NUM> hence I need to collapse them:
sed -re 's/>([^ ]+?-rad)/>\n\1/g' \
    -e 's:<NUM> <sil=[0-9.]+> % (<sil=[0-9.]+>):<NUM> \1:g' \
    < ${dir}/althingi.train_Sept2017_pause_punct.txt \
    | sort -u > ${dir}/althingi.train_Sept2017_pause_punct_edited.txt

mkdir ${dir}/../second_stage
mv ${dir}/althingi.train_Sept2017_pause_punct_edited.txt ${dir}/../second_stage/althingi.all.txt
cd ${dir}/../second_stage
shuf -n 4000 althingi.all.txt > althingi.dev.txt
join -j1 <(comm -13 <(cut -d" " -f1 althingi.dev.txt | sort -u) <(cut -d" " -f1 althingi.all.txt | sort -u)) <(sort -u althingi.all.txt) > althingi.train_test.txt
shuf -n 4000 althingi.train_test.txt > althingi.test.txt
join -j1 <(comm -13 <(cut -d" " -f1 althingi.test.txt | sort -u) <(cut -d" " -f1 althingi.train_test.txt | sort -u)) <(sort -u althingi.train_test.txt) > althingi_train.txt
rm althingi.train_test.txt
cut -d" " -f2- althingi.dev.txt > tmp && mv tmp althingi.dev.txt
cut -d" " -f2- althingi.test.txt > tmp && mv tmp althingi.test.txt
cut -d" " -f2- althingi.train.txt > tmp && mv tmp althingi.train.txt
