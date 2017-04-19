#!/bin/bash -eu

set -o pipefail

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

# data dir
datadir=recognize/speeches/$speechname
mkdir -p ${datadir}

stage=6

num_jobs=1

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# Dirs used
langdir=data/lang_cs  #data/lang_bd
graphdir=exp/chain/tdnn_lstm_1e/graph_3g_cs_023pruned  #exp/tri3/graph_tg_bd_023pruned
decodedir=${datadir}_segm_hires/decode_3g_cs_023pruned  #decode_tg_bd_023pruned
rescoredir=${datadir}_segm_hires/decode_5g_cs  #decode_fg_bd_unpruned
oldLMdir=data/lang_3g_cs_023pruned  #data/lang_tg_bd_023pruned
newLMdir=data/lang_5g_cs  #data/lang_fg_bd_unpruned

if [ $stage -le 0 ]; then

    echo "Set up a directory in the right format of Kaldi and extract features"
    local/prep_audiodata_fromName.sh $speechname $datadir
fi

if [ $stage -le 3 ]; then

    echo "Segment audio data"
    local/segment_audio.sh ${datadir} ${datadir}_segm
fi

if [ $stage -le 4 ]; then

    echo "Create high resolution MFCC features"
    utils/copy_data_dir.sh ${datadir}_segm ${datadir}_segm_hires
    steps/make_mfcc.sh \
	--nj $num_jobs --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" ${datadir}_segm_hires || exit 1;
    steps/compute_cmvn_stats.sh ${datadir}_segm_hires || exit 1;
    utils/fix_data_dir.sh ${datadir}_segm_hires
fi

if [ $stage -le 5 ]; then

    echo "Extracting iVectors"
    mkdir -p ${datadir}_segm_hires/ivectors_hires
    steps/online/nnet2/extract_ivectors_online.sh \
	--cmd "$train_cmd" --nj $num_jobs \
        ${datadir}_segm_hires exp/nnet3/extractor \
        ${datadir}_segm_hires/ivectors_hires || exit 1;
fi

if [ $stage -le 6 ]; then
    rm ${datadir}_segm_hires/.error 2>/dev/null || true

    frames_per_chunk=140,100,160
    frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)
    extra_left_context=50
    extra_right_context=0
    cp exp/chain/tdnn_lstm_1e/{final.mdl,final.ie.id,cmvn_opts} ${datadir}_segm_hires

    steps/nnet3/decode.sh \
	--acwt 1.0 --post-decode-acwt 10.0 \
	--nj $num_jobs --cmd "$decode_cmd" \
	--skip-scoring true \
	--extra-left-context $extra_left_context  \
	--extra-right-context $extra_right_context  \
	--extra-left-context-initial 0 \
	--extra-right-context-final 0 \
	--frames-per-chunk "$frames_per_chunk_primary" \
	--online-ivector-dir ${datadir}_segm_hires/ivectors_hires \
	$graphdir ${datadir}_segm_hires ${decodedir} || exit 1;
    
    steps/lmrescore.sh --cmd "$decode_cmd" --skip-scoring true \
	${oldLMdir} ${newLMdir} ${datadir}_segm_hires \
	${decodedir} ${rescoredir} || exit 1;
    
    wait
    if [ -f ${datadir}_segm_hires/.error ]; then
	echo "$0: something went wrong in decoding"
	exit 1
    fi
fi


if [ $stage -le 7 ]; then

    echo "Extract the transcript hypothesis from the Kaldi lattice"
    # NOTE! Is scale=12 good?
    lattice-best-path \
        --lm-scale=12 \
        --word-symbol-table=${langdir}/words.txt \
        "ark:zcat ${rescoredir}/lat.1.gz |" ark,t:- &> ${rescoredir}/extract_transcript.log

    # Extract the best path text (tac - concatenate and print files in reverse)
    tac ${rescoredir}/extract_transcript.log | grep -e '^[^ ]\+rad' | sort -u -t" " -k1,1 > ${rescoredir}/transcript.txt

    # Remove utterance IDs
    perl -pe 's/[^ ]+rad[^ ]+//g' ${rescoredir}/transcript.txt | tr "\n" " " | sed -e "s/[[:space:]]\+/ /g" > ${rescoredir}/transcript_noID.txt
fi

if [ $stage -le 8 ]; then

    echo "Denormalize the transcript"
    local/denormalize.sh \
        ${rescoredir}/transcript_noID.txt \
        ${rescoredir}/transcript_denormalized.txt
    rm ${rescoredir}/*.tmp

fi
