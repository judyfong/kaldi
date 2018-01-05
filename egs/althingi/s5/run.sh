#!/bin/bash -eu

# The script contains the steps taken to train an Icelandic LVCSR
# built for the Icelandic parliament using text and audio data
# from the parliament. It is assumed that the text data provided
# consists of two sets of files, the intermediate text
# and the final text. The text needs to be normalized and
# and audio and text has to be aligned and segmented before
# training.
#
# If you have already segmented data, you just need to create the kaldi files
# (done in the first part of prep_althingi_data.sh) and can then go to
# stage 5.
#
# This script is thought as a template. Changes might have to be made.
#
# Copyright 2017 Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0
#
# I have not thought this file as to be run through.
# NOTE! Decide if using speaker names or abbreviations in uttIDs
# The names are stated in the metafile but the abbreviations can be
# found on althingi.is

# NOTE! If obtaining the audio and text files from althingi.is run
# extract_new_files.sh and skip stage -1 instead

set -o pipefail

nj=20
decode_nj=32 
stage=-100
corpus_zip=/data/althingi/tungutaekni_145.tar.gz
datadir=/data/althingi/corpus
outdir=data/all_okt2017

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh


if [ $stage -le -1 ]; then
    echo "Extracting corpus"
    [ -f $corpus_zip ] || error "$corpus_zip not a file"
    mkdir -p ${datadir}
    tar -zxvf $corpus_zip --directory ${datadir}/
    mv ${datadir}/2016/* ${datadir}/
    rm -r ${datadir}/2016
    # validate
    if ! [[ -d ${datadir}/audio && \
		  -d ${datadir}/text_bb && \
		  -d ${datadir}/text_endanlegt && \
		  -f ${datadir}/metadata.csv ]]; then
        error "Corpus doesn not have correct structure"
    fi
    encoding=$(file -i ${datadir}/metadata.csv | cut -d" " -f3)
    if [[ "$encoding"=="charset=iso-8859-1" ]]; then
	iconv -f ISO-8859-1 -t UTF-8 ${datadir}/metadata.csv > tmp && mv tmp ${datadir}/metadata.csv
    fi

fi

if [ $stage -le 0 ]; then
    
    echo "Make Kaldi data files, do initial text normalization and clean spelling errors in the text"
    local/prep_althingi_data.sh ${datadir} ${outdir}
fi

if [ $stage -le 1 ]; then
    if [ -d text_norm ]; then
	echo "Probably an expansion LM already exists."
	echo "Are you sure you want to redo it?"
	echo "  If so, delete the text_norm dir and then rerun this part"
	exit 1;
    fi
    echo "Text normalization: Expansion of abbreviations and numbers"
    # train a language model for expansion
    ./local/train_expansionLM.sh text_norm ${outdir}
fi

if [ $stage -le 2 ]; then
    echo "Expand numbers and abbreviations"
    ./local/expand.sh text_norm ${outdir}/text_bb_SpellingFixed_uttID.txt ${outdir}/text

    echo "Validate the data dir"
    utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir}
fi

if [ $stage -le 3 ]; then
    
    info "Make the texts case sensitive (althingi and LM training text)"
    local/case_sensitive.sh ~/data/althingi/pronDict_LM ${outdir}
    
    # Make the CS text be the main text
    mv ${outdir}/text ${outdir}/LCtext
    mv ${outdir}/text_CaseSens.txt ${outdir}/text
fi

if [ $stage -le 4 ]; then
    # I can't train without segmenting the audio and text first.
    # I use the LF-MMI tdnn-lstm recognizer, trained on 514 hrs of
    # data to transcribe the audio so that I can align the new data	
    echo "Segment the data using and in-domain recognizer"
    nohup local/run_segmentation.sh ${outdir} data/lang exp/tri2_cleaned &>${outdir}/log/segmentation.log

    # Should be unnecessary
    # echo "Analyze the segments and filter based on a words/sec ratio"
    # local/words-per-second.sh data/all_reseg
    # #local/hist/wps_perSegment_hist.py wps.txt
    
    # Filter away segments with extreme wps
    local/filter_segments.sh ${outdir}_reseg ${outdir}_reseg_filtered
fi

if [ $stage -le 5 ]; then
    echo "Extracting features"
    steps/make_mfcc.sh \
        --nj $nj       \
        --mfcc-config conf/mfcc.conf \
        --cmd "$train_cmd"           \
        ${outdir}_reseg_filtered exp/make_mfcc mfcc

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh \
        ${outdir}_reseg_filtered exp/make_mfcc mfcc

fi
    
if [ $stage -le 6 ]; then

    # NOTE! I want to do this differently. And put an upper limit on the quantity of data from one speaker
    
    echo "Splitting into a train, dev and eval set"
    # Ideal would have been to hold back a little of the training data, called f.ex. train-dev
    # to use for bias estimation. Then have a dev/eval set to check the decoding on and finally
    # have a test set that is never touched, until in the end. In the following I did not do that.
    
    # Use the data from the year 2016 as my eval data
    grep "rad2016" data/all_reseg_20161128_filtered/utt2spk | cut -d" " -f1 > test_uttlist
    grep -v "rad2016" data/all_reseg_20161128_filtered/utt2spk | cut -d" " -f1 > train_uttlist
    
    subset_data_dir.sh --utt-list train_uttlist data/all_reseg_20161128_filtered data/train
    subset_data_dir.sh --utt-list test_uttlist data/all_reseg_20161128_filtered data/dev_eval
    rm test_uttlist train_uttlist

    # # NOTE! Now I have multiple sources of training data. I need to combine them all
    # utils/combine_data.sh data/train_okt2017 data/train data/all_okt2017_reseg_filtered &
    
    # Randomly split the dev_eval set 
    shuf <(cut -d" " -f1 data/dev_eval/utt2spk) > tmp
    m=$(echo $(($(wc -l tmp | cut -d" " -f1)/2)))
    head -n $m tmp > out1 # uttlist 1
    tail -n +$(( m + 1 )) tmp > out2 # uttlist 2
    utils/subset_data_dir.sh --utt-list out1 data/dev_eval data/dev
    utils/subset_data_dir.sh --utt-list out2 data/dev_eval data/eval
fi

if [ $stage -le 7 ]; then

    echo "Lang preparation"

    # Make lang dir
    mkdir -p data/local/dict
    pronDictdir=~/data/althingi/pronDict_LM
    frob=${pronDictdir}/CaseSensitive_pron_dict_Fix15_stln_fixed.txt
    local/prep_lang.sh \
        $frob            \
        data/local/dict   \
        data/lang

    # Make the LM training sample, assuming the 2016 data is used for testing
    #cat ${pronDictdir}/scrapedAlthingiTexts_expanded_CS.txt <(grep -v rad2016 data/all/text | cut -d" " -f2-) > ${pronDictdir}/LMtexts_expanded_CS.txt
    nohup local/prep_LM_training_data_from_punct_texts.sh # outfile is ${pronDictdir}/LMtext_w_t131_split_on_EOS.txt
    #cat ${pronDictdir}/t130_131_capitalized_1line.txt <(egrep -v rad2016 data/all/text | cut -d" " -f2-) <(cut -d" " -f2- data/all_okt2017/text) <(cut -d" " -f2-data/all_sept2017/text) > ${pronDictdir}/LMtexts_expanded_CS_okt2017.txt

    # Expanded LM training text and split on EOS:
    #/home/staff/inga/data/althingi/pronDict_LM/LMtext_w_t131_split_on_EOS_expanded.txt

    # Expanded but not split on EOS:
    # LMtexts_expanded_CS.txt
    
    echo "Preparing a pruned trigram language model"
    mkdir -p data/lang_3gsmall
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
	[ ! -e data/lang_3gsmall/$s ] && cp -r data/lang/$s data/lang_3gsmall/$s
    done

    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
	-o 3 -S 70% --prune 0 3 5 \
	--text ${pronDictdir}/LMtext_w_t131_split_on_EOS_expanded.txt \
	--limit_vocab_file <(cat data/lang_3gsmall/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
	| gzip -c > data/lang_3gsmall/kenlm_3g_035pruned.arpa.gz

    utils/slurm.pl data/lang_3gsmall/format_lm.log utils/format_lm.sh data/lang data/lang_3gsmall/kenlm_3g_035pruned.arpa.gz data/local/dict/lexicon.txt data/lang_3gsmall &

    echo "Preparing an unpruned trigram language model"
    mkdir -p data/lang_3glarge
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
	[ ! -e data/lang_3glarge/$s ] && cp -r data/lang/$s data/lang_3glarge/$s
    done

    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
	-o 3 -S 70% --prune 0 \
	--text ${pronDictdir}/LMtext_w_t131_split_on_EOS_expanded.txt \
	--limit_vocab_file <(cat data/lang_3glarge/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
	| gzip -c > data/lang_3glarge/kenlm_3g.arpa.gz

    # Build ConstArpaLm for the unpruned 3g language model.
    utils/build_const_arpa_lm.sh data/lang_3glarge/kenlm_3g.arpa.gz \
        data/lang data/lang_3glarge &
   
    echo "Preparing an unpruned 5g LM"
    mkdir -p data/lang_5g
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
	[ ! -e data/lang_5g/$s ] && cp -r data/lang/$s data/lang_5g/$s
    done

    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
	-o 5 -S 70% --prune 0 \
	--text ${pronDictdir}/LMtext_w_t131_split_on_EOS_expanded.txt \
	--limit_vocab_file <(cat data/lang_5g/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
	| gzip -c > data/lang_5g/kenlm_5g.arpa.gz

    # Build ConstArpaLm for the unpruned 5g language model.
    utils/build_const_arpa_lm.sh data/lang_5g/kenlm_5g.arpa.gz \
        data/lang data/lang_5g &

fi

if [ $stage -le 8 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"

    # utils/subset_data_dir.sh data/train 40000 data/train_40k
    # utils/subset_data_dir.sh --shortest data/train_40k 5000 data/train_5kshort
    # utils/subset_data_dir.sh data/train 10000 data/train_10k
    utils/subset_data_dir.sh data/train 20000 data/train_20k

    # # Make one for the dev/eval sets so that I can get a quick estimate
    # # for the first training steps. Try to get 30 utts per speaker
    # # (~30% of the dev/eval set)
    # utils/subset_data_dir.sh --per-spk data/dev 30 data/dev_30
    # utils/subset_data_dir.sh --per-spk data/eval 30 data/eval_30
fi

if [ $stage -le 9 ]; then
    # NOTE! Should I rather start with SI alignment and then training LDA+MLLT?

    echo "Align and train on the segmented data"
    # Now there is no need to start from mono training since we already got a good recognizer.
    steps/align_fmllr.sh --nj 100 --cmd "$train_cmd --time 1-00" \
        data/train data/lang exp/tri4 exp/tri4_ali || exit 1;

    echo "Train SAT"
    steps/train_sat.sh  \
	--cmd "$train_cmd" \
	7500 150000 data/train \
	data/lang exp/reseg_fmllr_ali exp/tri5 || exit 1;

    utils/mkgraph.sh data/lang_3gsmall exp/tri5 exp/tri5/graph_3gsmall

    decode_num_threads=4
    for dset in dev eval; do
        (
            steps/decode_fmllr.sh \
                --nj $decode_nj --num-threads $decode_num_threads \
                --cmd "$decode_cmd" \
                exp/tri5/graph_3gsmall data/${dset} exp/tri5/decode_${dset}_3gsmall
            steps/lmrescore_const_arpa.sh \
                --cmd "$decode_cmd" data/lang_{3gsmall,3glarge} \
                data/${dset} exp/tri5/decode_${dset}_{3gsmall,3glarge}
            steps/lmrescore_const_arpa.sh \
                --cmd "$decode_cmd" data/lang_{3gsmall,5g} \
                data/${dset} exp/tri5/decode_${dset}_{3gsmall,5g}
        ) &
    done

# if [ $stage -le 10 ]; then
#     echo "Clean and resegment the training data"
#     local/run_cleanup_segmentation.sh
# fi

# NNET Now by default running on un-cleaned data
# Input data dirs need to be changed
if [ $stage -le 11 ]; then

    echo "Run the swbd chain tdnn_lstm recipe with sp"
    local/chain/run_tdnn_lstm.sh >>tdnn_lstm.log 2>&1 &

    echo "Run the swbd chain tdnn_lstm recipe without sp"
    local/chain/run_tdnn_lstm_noSP.sh >>tdnn_lstm_noSP.log 2>&1 &
fi
