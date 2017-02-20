#!/bin/bash -eu

# Script that takes in a audio file and returns a transcribed text.
# Using what model?

# local/recognize.sh <audio-zip> <

# data dirs
audio_zip=$1
audiodir=data/$(basename $audio_zip .tar.gz)
#datadir=$2 # or something like: data/$speechname or data/speeches_$date
data=$(basename $audiodir)

# Model and lang dirs
langdir=data/lang_bd
graphdir=exp/graph_tg_bd

stage=-1
mkdir -p ${audiodir}
tar -zxvf ${audio_zip} --directory ${audiodir}/

n_files=$(ls $audiodir/*.mp3 | wc -l) # .wav?
num_jobs=$n_files

. ./cmd.sh
. ./path.sh

if ! [[ $n_files > 0 ]]; then
    error "$audio_zip didn't contain audio files"
fi

if [ $stage -le 0 ]; then
local/prep_audiodata.sh --nj $num_jobs $audiodir
fi

if [ $stage -le 3 ]; then

    echo "Create high resolution MFCC features"
    utils/copy_data_dir.sh $datadir ${datadir}_hires
    steps/make_mfcc.sh \
	--nj $num_jobs --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" ${datadir}_hires || exit 1;
    steps/compute_cmvn_stats.sh ${datadir}_hires || exit 1;
    utils/fix_data_dir.sh ${datadir}_hires
fi

if [ $stage -le 4 ]; then

    echo "Extracting iVectors"
    steps/online/nnet2/extract_ivectors_online.sh \
	--cmd "$train_cmd" --nj $num_jobs \
        ${datadir}_hires exp/nnet3_sp/extractor \
        exp/nnet3_sp/ivectors_${data}_hires || exit 1;
fi

if [ $stage -le 5 ]; then

    echo "Decoding"
    steps/nnet3/decode.sh \
	--nj $num_jobs --cmd "$decode_cmd" \
	--skip-scoring true \
	--online-ivector-dir exp/nnet3_sp/ivectors_${data}_hires \
	$graphdir ${datadir}_hires ${datadir}_hires/decode_${data} || exit 1;
    
fi

if [ $stage -le 6 ]; then

    echo "Extract the transcript hypothesis from the Kaldi lattice"
    # NOTE! Fix and find which values to use!
    for n in $(seq 1 $(cat ${datadir}_hires/decode_${data}/num_jobs))
    do	
	lattice-best-path \
	    --lm-scale=12 \
	    --word-symbol-table=${langdir}/words.txt \
	    "ark:zcat ${datadir}_hires/decode_${data}/lat.${n}.gz |" ark,t:- |
	    utils/int2sym.pl -f 2- ${langdir}/words.txt >>${datadir}_hires/decode_${data}/transcript.txt
    done
    
fi

if [ $stage -le 7 ]; then

    echo "Denormalize the transcript"
    local/denormalize.sh ${datadir}_hires/decode_${data}/transcript.txt ${datadir}_hires/decode_${data}/transcript_denormalized.txt

fi
