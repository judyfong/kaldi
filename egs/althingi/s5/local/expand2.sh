#!/bin/bash -eu

nj=60

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

echo "Expand abbreviations and numbers in text"

# # ./local/train_LM.sh
# Nothing should be mapped to <unk> in the following
cat ${outdir}/text_bb_SpellingFixed.txt \
    | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30all.txt \
    | utils/int2sym.pl -f 2- text_norm/text/words30all.txt > ${outdir}/text_bb_SpellingFixed_noOOV.txt

# We want to process it in parallel.
mkdir -p ${outdir}/split$nj/
IFS=$' \t\n'
split_text=$(for j in `seq 1 $nj`; do printf "${outdir}/split%s/text_bb_SpellingFixed_noOOV.%s.txt " $nj $j; done)
utils/split_scp.pl ${outdir}/text_bb_SpellingFixed_noOOV.txt $split_text # problem with using $split_text if the field separator is not correct
# Expand
utils/slurm.pl JOB=1:$nj ${outdir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30all.txt ark,t:${outdir}/split${nj}/text_bb_SpellingFixed_noOOV.JOB.txt text_norm/expand_to_words30all.fst text_norm/text/numbertextsAll_2g.fst ark,t:${outdir}/split${nj}/text_expanded.JOB.txt &

# # Put all expanded text into one file
if [ -f ${outdir}/text_bb_expanded.txt ]; then
    mv ${outdir}/{,.backup/}text_bb_expanded.txt
fi
cat ${outdir}/split${nj}/text_expanded.*.txt > ${outdir}/text_bb_expanded.txt

cp ${outdir}/text_bb_expanded.txt ${outdir}/text

# ################################
# #### Just a temporary fix ####
grep -o "[^0-9 ]*_rad20[0-9]*T[0-9]*" ${outdir}/log/expand-numbers.*.log | cut -d":" -f2 | sort -u > ${outdir}/speeches_notExpanded.txt # Find speeches not expanded

# Obtain the text NOT expanded
if [ -f ${outdir}/text_bb_NOT_expanded.txt ]; then
   rm ${outdir}/text_bb_NOT_expanded.txt
fi

for uttID in $(cat ${outdir}/speeches_notExpanded.txt)
do
    grep $uttID ${outdir}/text_bb_SpellingFixed.txt >> ${outdir}/text_bb_NOT_expanded.txt 
done
cat ${outdir}/text_bb_NOT_expanded.txt \
        | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30.txt \
        | utils/int2sym.pl -f 2- text_norm/text/words30.txt > ${outdir}/text_bb_NOT_expanded_noOOVs.txt
mv ${outdir}/text_bb_NOT_expanded_noOOVs.txt ${outdir}/text_bb_NOT_expanded.txt

# Put all expanded text into one file
#cat ${outdir}/text_expanded.*.txt > ${outdir}/text_bb_expanded.txt
# Remove uttID of speeches not expanded. (Directly modify the file and create a backup)
for uttID in $(cat ${outdir}/speeches_notExpanded.txt)
do
    sed -i.bak "/$uttID/d" ${outdir}/text_bb_expanded.txt
done

# Expand the not expanded again. I fixed the problem
nj=2
mkdir -p ${outdir}/split${nj}/
split_text=$(for j in `seq 1 $nj`; do printf "${outdir}/split%s/text_bb_NOT_expanded.%s.txt " $nj $j; done)
IFS=$' \t\n'
utils/split_scp.pl ${outdir}/text_bb_NOT_expanded.txt $split_text # problem with using $split_text
# Expand
utils/slurm.pl JOB=1:$nj ${outdir}/log/expand-numbers_temp.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30all.txt ark,t:${outdir}/split${nj}/text_bb_NOT_expanded.JOB.txt text_norm/expand_to_words30all.fst text_norm/text/numbertextsAll_2g.fst ark,t:${outdir}/split${nj}/text_expanded_try3.JOB.txt &

####################################

