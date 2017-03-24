#!/bin/bash -eu

# Script that takes in an audio file and returns a transcribed text.
# Using what model?

# local/recognize.sh <audio-zip>

# data dirs
#audio_zip=$1
#speech=data/$(basename $audio_zip .tar.gz)
datadir=recognize/speeches/$speech
# Fits well if audio_zip is something like radxxx.tar.gz and contains an
# audio file, by the same name and some metadata. Probably more likely that
# it only contains metadata and a pointer to where the audio is stored.

# Model and lang dirs
langdir=data/lang_bd
graphdir=exp/tri3/graph_tg_bd_023pruned

stage=-1
mkdir -p ${datadir}
#tar -zxvf ${audio_zip} --directory ${datadir}/

n_files=$(ls $datadir/*.flac | wc -l) # .mp3, .wav?
num_jobs=$n_files

. ./cmd.sh
. ./path.sh

if ! [[ $n_files > 0 ]]; then
    error "$audio_zip didn't contain audio files"
fi

if [ $stage -le 0 ]; then
local/prep_audiodata.sh --nj $num_jobs $datadir
fi

# Segment audio data and create a new data dir for the segmented data
if [ $stage -le 3 ]; then
local/segment_audio.sh $datadir ${datadir}_segm
fi

if [ $stage -le 4 ]; then

    echo "Create high resolution MFCC features"
    utils/copy_data_dir.sh $datadir_segm ${datadir}_segm_hires
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

    echo "Decoding"
    cp exp/nnet3/nnet_tdnn_a/final.mdl ${datadir}_segm_hires
    cp exp/nnet3/nnet_tdnn_a/cmvn_opts ${datadir}_segm_hires
    cp ${datadir}_segm_hires/ivectors_hires/final.ie.id ${datadir}_segm_hires
    steps/nnet3/decode.sh \
	--nj $num_jobs --cmd "$decode_cmd" \
	--skip-scoring true \
	--online-ivector-dir ${datadir}_segm_hires/ivectors_hires \
	$graphdir ${datadir}_segm_hires ${datadir}_segm_hires/decode_tg_bd_023pruned || exit 1;
    steps/lmrescore.sh --cmd "$decode_cmd" --skip-scoring true \
          data/lang_tg_bd_023pruned data/lang_fg_bd ${datadir}_segm_hires \
          ${datadir}_segm_hires/decode_tg_bd_023pruned ${datadir}_segm_hires/decode_fg_bd || exit 1;
    
fi

if [ $stage -le 7 ]; then

    echo "Extract the transcript hypothesis from the Kaldi lattice"
    # NOTE! Fix and find which values to use!
    for n in $(seq 1 $(cat ${datadir}_segm_hires/decode_fg_bd/num_jobs))
    do	
	lattice-best-path \
	    --lm-scale=12 \
	    --word-symbol-table=${langdir}/words.txt \
	    "ark:zcat ${datadir}_segm_hires/decode_fg_bd/lat.${n}.gz |" ark,t:- |
	    utils/int2sym.pl -f 2- ${langdir}/words.txt >>${datadir}_segm_hires/decode_fg_bd/transcript.txt
    done
    
fi

if [ $stage -le 8 ]; then

    echo "Denormalize the transcript"
    local/denormalize.sh ${datadir}_segm_hires/decode_fg_bd \
			 ${datadir}_segm_hires/decode_fg_bd/transcript.txt \
			 ${datadir}_segm_hires/decode_fg_bd/transcript_denormalized.txt
    #rm ${datadir}_segm_hires/decode/*.tmp

fi
