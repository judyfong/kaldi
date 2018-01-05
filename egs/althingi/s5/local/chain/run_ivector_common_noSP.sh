#!/bin/bash

# this script is called from scripts like run_ms.sh; it does the common stages
# of the build, such as feature extraction.
# This is actually the same as local/online/run_nnet2_common.sh, except
# for the directory names.

mfccdir=mfcc

stage=1

train_set=train_okt2017_fourth
gmm=tri5

num_threads_ubm=24

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

gmm_dir=exp/${gmm}

if [ $stage -le 1 ]; then
  for datadir in $train_set dev eval; do
    utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
    steps/make_mfcc.sh --nj 100 --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd --time 0-16" data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;
  done
  # Make a subset containing 30k utterances of the original training set
  utils/subset_data_dir.sh data/${train_set}_hires 35000 data/${train_set}_hires_35k || exit 1
  utils/subset_data_dir.sh data/${train_set}_hires 70000 data/${train_set}_hires_70k || exit 1
fi

if [ $stage -le 2 ]; then
  # We need to build a small system just because we need the LDA+MLLT transform
  # to train the diag-UBM on top of.  We align a subset of training data for
  # this purpose.
  echo "$0: aligning a subset of training data."
  utils/subset_data_dir.sh --utt-list <(awk '{print $1}' data/${train_set}_hires_35k/utt2spk) \
     data/${train_set} data/${train_set}_35k

  steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
    data/${train_set}_35k data/lang $gmm_dir ${gmm_dir}_ali_35k
fi

if [ $stage -le 3 ]; then
  # Train a small system just for its LDA+MLLT transform.  We use --num-iters 13
  # because after we get the transform (12th iter is the last), any further
  # training is pointless.
  echo "$0: training a system on the hires subset data for its LDA+MLLT transform, in order to produce the diagonal GMM."
  steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 13 \
    --realign-iters "" \
    --splice-opts "--left-context=3 --right-context=3" \
    5000 10000 data/${train_set}_hires_35k data/lang \
     ${gmm_dir}_ali_35k exp/chain/tri6
fi

if [ $stage -le 4 ]; then
  echo "$0: using the subset of data to train the diagonal UBM."
  mkdir -p exp/chain/diag_ubm
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 30 \
    --num-frames 700000 --num-threads $num_threads_ubm \
    data/${train_set}_hires_35k 512 \
    exp/chain/tri6 exp/chain/diag_ubm || exit 1;
fi

if [ $stage -le 5 ]; then
  # even though $nj is just 10, each job uses multiple processes and threads.
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd --time 0-12" --nj 10 \
    data/${train_set}_hires_70k exp/chain/diag_ubm exp/chain/extractor || exit 1;
fi

if [ $stage -le 6 ]; then
  echo "$0: extracting iVectors for training data"
  ivectordir=exp/chain/ivectors_${train_set}_hires

  # We extract iVectors on the training data, which will be what we train the system on.
  # With --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker. this gives more diversity in iVectors..
  # Note that these are extracted 'online'.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    data/${train_set}_hires ${ivectordir}/${train_set}_hires_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd --time 0-12" --nj 100 \
    ${ivectordir}/${train_set}_hires_max2 exp/chain/extractor $ivectordir || exit 1;
fi

if [ $stage -le 7 ]; then
  echo "$0: extracting iVectors for dev and test data"
  for data in dev eval; do
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
      data/${data}_hires exp/chain/extractor exp/chain/ivectors_${data}_hires || exit 1;
  done
fi

exit 0;
