#!/bin/bash

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Decode audio using a LF-MMI tdnn-lstm model. Takes in audio + an optional meta file connecting the audiofile name and the speaker. The final transcript is capitalized and contains punctuation. 
#
# Usage: $0 <audiofile> [<metadata>]
# Example (if want to save the time info as well):
# { time recognize/local/recognize.sh data/local/corpus/audio/rad20160309T151154.flac data/local/corpus/metadata.csv; } &> recognize/chain/rad20160309T151154.log

set -e
set -o pipefail

# configs
stage=-1
num_jobs=1
lmwt=8 # Language model weight. Can have big effect. 
score=false

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

datadir=recognize/chain/$speechname
mkdir -p ${datadir}

if [ $# = 2 ]; then
    speakerfile=$2  # A meta file containing the name of the speaker
elif [ $# = 1 ]; then
    echo -e "unknown",$speechname > ${datadir}/${speechname}_meta.tmp
    speakerfile=${datadir}/${speechname}_meta.tmp
else
    echo "Usage: recognize/local/recognize.sh [options] <audiofile> [<metadata>]"
fi

# Dirs used #
# Already existing
modeldir=exp/chain
graphdir=${modeldir}/tdnn_lstm_1e_sp/graph_3gsmall
oldLMdir=data/lang_3gsmall
newLMdir=data/lang_5g
# Created
decodedir=${datadir}_segm_hires/decode_3gsmall
rescoredir=${datadir}_segm_hires/decode_5g

if [ $stage -le 0 ]; then

    echo "Set up a directory in the right format of Kaldi and extract features"
    recognize/local/prep_audiodata.sh $speechfile $speakerfile $datadir || exit 1;
fi
spkID=$(cut -d" " -f1 $datadir/spk2utt)

if [ $stage -le 3 ]; then

    echo "Segment audio data"
    recognize/local/segment_audio.sh ${datadir} ${datadir}_segm || exit 1;
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
        ${datadir}_segm_hires ${modeldir}/extractor \
        ${datadir}_segm_hires/ivectors_hires || exit 1;
fi

if [ $stage -le 6 ]; then
    rm ${datadir}_segm_hires/.error 2>/dev/null || true

    frames_per_chunk=140,100,160
    frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)
    extra_left_context=50
    extra_right_context=0
    cp ${modeldir}/tdnn_lstm_1e_sp/{final.mdl,final.ie.id,cmvn_opts,frame_subsampling_factor} ${datadir}_segm_hires || exit 1;

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
    
    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" --skip-scoring true \
	${oldLMdir} ${newLMdir} ${datadir}_segm_hires \
	${decodedir} ${rescoredir} || exit 1;
fi

if [ $stage -le 7 ]; then

    echo "Extract the transcript hypothesis from the Kaldi lattice"
    lattice-best-path \
        --lm-scale=$lmwt \
        --word-symbol-table=${oldLMdir}/words.txt \
        "ark:zcat ${rescoredir}/lat.1.gz |" ark,t:- &> ${rescoredir}/extract_transcript.log || exit 1;

    # Extract the best path text (tac - concatenate and print files in reverse)
    tac ${rescoredir}/extract_transcript.log | grep -e '^[^ ]\+rad' | sort -u -t" " -k1,1 > ${rescoredir}/transcript.txt || exit 1;

fi

if [ $stage -le 8 ]; then

    echo "Denormalize the transcript"
    recognize/local/denormalize.sh \
        ${rescoredir}/transcript.txt \
        ${datadir}/../${speechname}.txt || exit 1;
    rm ${rescoredir}/*.tmp
fi
# ${rescoredir}/${spkID}_${speechname}_transcript.txt
if [ $score = true ] ; then

    echo "Estimate the WER"
    # NOTE! Correct for the mismatch in the beginning and end of recordings.
    recognize/local/score_recognize.sh --cmd "$train_cmd" $speechname ${oldLMdir} ${rescoredir}

    rm -r ${datadir} ${datadir}_segm
else
    rm -r ${datadir} ${datadir}_segm ${datadir}_segm_hires
fi

