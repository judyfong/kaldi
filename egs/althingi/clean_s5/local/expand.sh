#!/bin/bash -e

# Expand abbreviations and numbers in text

nj=60
stage=19

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

datadir=$1
normdir=$2

if [ $# != 2 ]; then
   echo "Usage: local/expand.sh [options] <data-dir> <text-norm-dir>"
   echo "e.g.: local/expand.sh --stage 23 data/all text_norm"
fi

if [ $stage -le 20 ]; then
    echo "We want to process it in parallel."
    mkdir -p ${datadir}/split$nj/
    IFS=$' \t\n'
    split_text=$(for j in `seq 1 $nj`; do printf "${datadir}/split%s/text_bb_SpellingFixed.%s.txt " $nj $j; done)
    utils/split_scp.pl ${datadir}/text_bb_SpellingFixed.txt $split_text # problem with using $split_text if the field separator is not correct
fi

if [ $stage -le 21 ]; then
    echo "Make a list over all the words in numbertexts"
    gzip -cd ${normdir}/numbertexts_althingi100.txt.gz | cut -d" " -f2- | tr " " "\n" | grep -v "^\s*$" | sort -u > ${normdir}/words_numbertexts_althingi100.txt
fi

if [ $stage -le 22 ]; then
    for JOB in `seq 1 $nj`; do
	cut -d" " -f2- ${datadir}/split${nj}/text_bb_SpellingFixed.$JOB.txt | tr " " "\n" | grep -v "^\s*$" | sort -u > ${datadir}/split${nj}/words_text_bb_SpellingFixed.$JOB.tmp
	echo "Extract words that are only in the althingi texts, excluding unexpanded abbrs and numbers"
	comm -23 <(comm -23 ${datadir}/split${nj}/words_text_bb_SpellingFixed.$JOB.tmp ${normdir}/words_numbertexts_althingi100.txt | egrep -v "[0-9]") <(cut -f1 ${normdir}/lex/abbr_lexicon.txt | sort -u) > ${datadir}/split${nj}/words_Job${JOB}_only.tmp
	
	echo "Map words which are not seen in context in numbertexts to <word>"
	python3 local/save_OOVwords.py ${datadir}/split${nj}/text_bb_SpellingFixed.$JOB.txt ${datadir}/split${nj}/words_Job${JOB}_only.tmp ${datadir}/split${nj}/text_afterWordMapping.$JOB.txt ${datadir}/split${nj}/MappedWords_Job${JOB}.txt

	echo "Expand"
	utils/slurm.pl JOB=$JOB ${datadir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=${normdir}/words30.txt ark,t:${datadir}/split${nj}/text_afterWordMapping.JOB.txt ${normdir}/expand_to_words30all.fst ${normdir}/numbertexts_althingi100_3g.fst ark,t:${datadir}/split${nj}/text_expanded.JOB.txt &
	# Old command
	#utils/slurm.pl JOB=1:$nj ${datadir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30all.txt ark,t:${datadir}/split${nj}/text_bb_SpellingFixed_noOOV.JOB.txt text_norm/expand_to_words30all.fst text_norm/text/numbertextsAll_3g.fst ark,t:${datadir}/split${nj}/text_expanded.JOB.txt &
    done
fi

if [ $stage -le 22 ]; then
    for JOB in `seq 1 $nj`; do

	wait;
	info "Check if all the speeches were expanded"
	num_speeches_expanded=$(cut -d" " -f2- ${datadir}/split${nj}/text_expanded.$JOB.txt | egrep -v "^\s*$" | sort -u | wc -l | cut -d" " -f1)
	num_speeched_total=$(wc -l ${datadir}/split${nj}/text_afterWordMapping.$JOB.txt | cut -d" " -f1)

	if [ "$num_speeches_expanded" -eq "$num_speeched_total" ] ; then
            echo "Insert words back"
	    utils/slurm.pl ${datadir}/split${nj}/log/re-inserting-OOVwords.$JOB.log python local/re-inserting-OOVwords.py ${datadir}/split${nj}/text_expanded.$JOB.txt ${datadir}/split${nj}/MappedWords_Job${JOB}.txt ${datadir}/split${nj}/text_expanded_wOOVwords.$JOB.txt
	    sed -i 's/ \([^ ]\+rad[0-9]\)/\n\1/g' ${datadir}/split${nj}/text_expanded_wOOVwords.$JOB.txt
	else
            echo "Some speeches in ${datadir}/split${nj}/text_afterWordMapping.$JOB.txt were not expanded!"
	    echo "That has to be fixed before re-inserting the OOV words."
            exit 1;
	fi
    done
fi

if [ $stage -le 23 ]; then
    # Put all expanded text into one file
    if [ -f ${datadir}/text_bb_expanded.txt ]; then
	mv ${datadir}/{,.backup/}text_bb_expanded.txt
    fi
    cat ${datadir}/split${nj}/text_expanded_wOOVwords.*.txt > ${datadir}/text_bb_expanded.txt

    if [ -e ${datadir}/text ] ; then
	# we don't want to overwrite old stuff, ask the user to delete it.
	echo "$0: ${datadir}/text already exists: "
	echo "Are you sure you want to proceed?"
	echo "It will overwrite the file"
	echo ""
	echo "  If so, please delete and then rerun this part"
	exit 1;
    fi

    cp ${datadir}/text_bb_expanded.txt ${datadir}/text
fi

# # Check if all the speeches were expanded
# num_speeches_expanded=$(cut -d" " -f2- ${datadir}/text_bb_expanded.txt | egrep -v "^\s*$" | sort -u | wc -l | cut -d" " -f1)
# num_speeched_total=$(wc -l ${datadir}/utt2spk | cut -d" " -f1)

# if [ "$num_speeches_expanded" -eq "num_speeched_total" ] ; then
#     cp ${datadir}/text_bb_expanded.txt ${datadir}/text
# else
#     echo "Some speeches were not expanded!"
#     exit 1;
# fi

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
#         | utils/int2sym.pl -f 2- text_norm/text/words30.txt > ${datadir}/text_bb_NOT_expanded.txt
# mv ${datadir}/text_bb_NOT_expanded.txt ${datadir}/text_bb_NOT_expanded.txt

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

