#!/bin/bash -eu

nj=60

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

datadir=$1

echo "Expand abbreviations and numbers in text"

# # ./local/train_LM.sh
# Nothing should be mapped to <unk> in the following
cat ${datadir}/text_bb_SpellingFixed.txt \
    | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30all.txt \
    | utils/int2sym.pl -f 2- text_norm/text/words30all.txt > ${datadir}/text_bb_SpellingFixed_noOOV.txt

# We want to process it in parallel.
mkdir -p ${datadir}/split$nj/
IFS=$' \t\n'
split_text=$(for j in `seq 1 $nj`; do printf "${datadir}/split%s/text_bb_SpellingFixed_noOOV.%s.txt " $nj $j; done)
utils/split_scp.pl ${datadir}/text_bb_SpellingFixed_noOOV.txt $split_text # problem with using $split_text if the field separator is not correct
# Expand
utils/slurm.pl JOB=1:$nj ${datadir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30all.txt ark,t:${datadir}/split${nj}/text_bb_SpellingFixed_noOOV.JOB.txt text_norm/expand_to_words30all.fst text_norm/text/numbertextsAll_3g.fst ark,t:${datadir}/split${nj}/text_expanded.JOB.txt &

# # Put all expanded text into one file
if [ -f ${datadir}/text_bb_expanded.txt ]; then
    mv ${datadir}/{,.backup/}text_bb_expanded.txt
fi
cat ${datadir}/split${nj}/text_expanded.*.txt > ${datadir}/text_bb_expanded.txt

# Check if all the speeches were expanded
num_speeches_expanded=$(cut -d" " -f2- ${datadir}/text_bb_expanded.txt | egrep -v "^\s*$" | sort -u | wc -l | cut -d" " -f1)
num_speeched_total=$(wc -l ${datadir}/utt2spk | cut -d" " -f1)

if [ "$num_speeches_expanded" -eq "num_speeched_total" ] ; then
    cp ${datadir}/text_bb_expanded.txt ${datadir}/text
else
    echo "Some speeches were not expanded!"
    exit 1;
fi

# ################################
# #### Just a temporary fix ####
# grep -o "[^0-9 ]*_rad20[0-9]*T[0-9]*" ${datadir}/log/expand-numbers.*.log | cut -d":" -f2 | sort -u > ${datadir}/speeches_notExpanded.txt # Find speeches not expanded

# # Obtain the text NOT expanded
# if [ -f ${datadir}/text_bb_NOT_expanded.txt ]; then
#    rm ${datadir}/text_bb_NOT_expanded.txt
# fi

# for uttID in $(cat ${datadir}/speeches_notExpanded.txt)
# do
#     grep $uttID ${datadir}/text_bb_SpellingFixed.txt >> ${datadir}/text_bb_NOT_expanded.txt 
# done
# cat ${datadir}/text_bb_NOT_expanded.txt \
#         | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30.txt \
#         | utils/int2sym.pl -f 2- text_norm/text/words30.txt > ${datadir}/text_bb_NOT_expanded_noOOVs.txt
# mv ${datadir}/text_bb_NOT_expanded_noOOVs.txt ${datadir}/text_bb_NOT_expanded.txt

# # Put all expanded text into one file
# #cat ${datadir}/text_expanded.*.txt > ${datadir}/text_bb_expanded.txt
# # Remove uttID of speeches not expanded. (Directly modify the file and create a backup)
# for uttID in $(cat ${datadir}/speeches_notExpanded.txt)
# do
#     sed -i.bak "/$uttID/d" ${datadir}/text_bb_expanded.txt
# done

# # Expand the not expanded again. I fixed the problem
# nj=2
# mkdir -p ${datadir}/split${nj}/
# split_text=$(for j in `seq 1 $nj`; do printf "${datadir}/split%s/text_bb_NOT_expanded.%s.txt " $nj $j; done)
# IFS=$' \t\n' # Important
# utils/split_scp.pl ${datadir}/text_bb_NOT_expanded.txt $split_text
# # Expand
# utils/slurm.pl JOB=1:$nj ${datadir}/log/expand-numbers_temp.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30all.txt ark,t:${datadir}/split${nj}/text_bb_NOT_expanded.JOB.txt text_norm/expand_to_words30all.fst text_norm/text/numbertextsAll_3g.fst ark,t:${datadir}/split${nj}/text_expanded_try3.JOB.txt &

# ####################################

