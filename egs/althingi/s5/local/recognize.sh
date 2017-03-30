#!/bin/bash -eu

set -o pipefail 
# Script that takes in an audio file and returns a transcribed text.
# This is just for me. It needs to be complete rewritten for Alþingi

# local/recognize.sh <speech>
# Example:
# local/recognize.sh data/local/corpus/audio/rad20151103T133116.flac

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

# data dir
datadir=recognize/speeches/$speechname
mkdir -p ${datadir}
# Fits well if the input something like data/radxxx.mp3.

stage=-1

#tar -zxvf ${audio_zip} --directory ${datadir}/

#n_files=$(ls $datadir/*.flac | wc -l) # .mp3, .wav?
#num_jobs=$n_files
num_jobs=1

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# Dirs used
langdir=data/lang_bd
graphdir=exp/tri3/graph_tg_bd_023pruned
decodedir=${datadir}_segm_hires/decode_tg_bd_023pruned
rescoredir=${datadir}_segm_hires/decode_fg_bd_unpruned
oldLMdir=data/lang_tg_bd_023pruned
newLMdir=data/lang_fg_bd_unpruned

# if ! [[ $n_files > 0 ]]; then
#     error "$audio_zip didn't contain audio files"
# fi

if [ $stage -le 0 ]; then
    #local/prep_audiodata.sh --nj $num_jobs $datadir
    local/prep_audiodata_fromName.sh $speechname $datadir
fi

# Segment audio data and create a new data dir for the segmented data
if [ $stage -le 3 ]; then
    local/segment_audio.sh $datadir ${datadir}_segm
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

    # NOTE! I intended to decode using a small lm and rescore using a larger LM. But I get
    # for some segments: Empty lattice for utterance GMJ-rad20071128T135510_00002 (incompatible LM?)
    echo "Decoding"
    extra_left_context=40
    extra_right_context=0
    frames_per_chunk=20
    cp exp/nnet3/lstm_ld5/{final.mdl,cmvn_opts} ${datadir}_segm_hires
    cp ${datadir}_segm_hires/ivectors_hires/final.ie.id ${datadir}_segm_hires
    
    steps/nnet3/decode.sh \
	--nj $num_jobs --cmd "$decode_cmd" \
	--skip-scoring true \
	--extra-left-context $extra_left_context  \
	--extra-right-context $extra_right_context  \
	--frames-per-chunk "$frames_per_chunk" \
	--online-ivector-dir ${datadir}_segm_hires/ivectors_hires \
	$graphdir ${datadir}_segm_hires ${decodedir} || exit 1; 

    steps/lmrescore.sh --cmd "$decode_cmd" --skip-scoring true \
          ${oldLMdir} ${newLMdir} ${datadir}_segm_hires \
          ${decodedir} ${rescoredir} || exit 1;
    
fi

if [ $stage -le 7 ]; then

    echo "Extract the transcript hypothesis from the Kaldi lattice"

    # if [ -f ${rescoredir}/transcript.txt ]; then
    #     rm ${rescoredir}/transcript.txt
    # fi
    
    # #for n in $(seq 1 $(cat ${rescoredir}/num_jobs)) # lat.${n}.gz
    # #do
    # lattice-best-path \
    #     --lm-scale=12 \
    #     --word-symbol-table=${langdir}/words.txt \
    #     "ark:zcat ${rescoredir}/lat.1.gz |" ark,t:- \
    #     | utils/int2sym.pl -f 2- ${langdir}/words.txt >>${rescoredir}/transcript.txt #&>${rescoredir}/extract_transcript.log
    # #done

    # NOTE! Is scale=12 good?
    lattice-best-path \
        --lm-scale=12 \
        --word-symbol-table=${langdir}/words.txt \
        "ark:zcat ${rescoredir}/lat.1.gz |" ark,t:- > ${rescoredir}/extract_transcript.log

    # Extract the best path text (tac - concatenate and print files in reverse)
    tac ${rescoredir}/extract_transcript.log | grep -e '^[^ ]\+rad' | sort -u -t" " -k1,1 > ${rescoredir}/transcript.txt
    # or equal but 9 times slower:
    #utils/int2sym.pl -f 2- ${langdir}/words.txt <(grep -e '^[^ ]\+rad' ${rescoredir}/extract_transcript.log | sort -u -t" " -k1,1) > ${rescoredir}/transcript.txt

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
