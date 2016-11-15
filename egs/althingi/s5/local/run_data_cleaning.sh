#!/bin/bash

set -e

# This script shows how you can do data-cleaning, and exclude data that has a
# higher likelihood of being wrongly transcribed. This didn't help with the 
# LibriSpeech data set, so perhaps the data is already clean enough.
# For the actual results see the comments at the bottom of this script.

# Copyright: Someone working on LibriSpeech, no author or date mentioned
# 2016 Inga Rún

stage=2
nj=20
nj_decode=$(echo $((($(wc -l data/train/spk2utt | cut -d" " -f1)+1)/2))) # #spk/2
thresh=0.2

echo "$0 $@"  # Print the command line for logging
. ./path.sh
. ./cmd.sh || exit 1;
. utils/parse_options.sh || exit 1;

# ifif [ $# != 5 ]; then
#    echo "Wrong #arguments ($#, expected 5)"
#    echo "Usage: local/run_data_cleaning.sh [options] <train-dir> <dev-dir> <lang-dir> <LM-dir> <model-dir>"
#    echo " e.g.: local/run_data_cleaning.sh data/train data/dev data/lang data/lang_tg exp/tri3"
#    echo "main options (for others, see top of script file)"
#    echo "  --nj <nj>                                # number of parallel jobs"
#    echo "  --nj_decode <nj_decode>                  # number of parallel jobs when decoding"
#    echo "  --thresh <thresh>                        # max WER"
#    exit 1;
# fi

# train=$1
# dev=$2
# lang=$3
# LMdir=$4
# srcdir=$5

if [ $stage -le 1 ]; then
  steps/cleanup/find_bad_utts.sh --nj 100 --cmd "$train_cmd" data/train data/lang \
    exp/tri3_ali exp/tri3_cleanup
fi

#thresh=0.2 # They used 0.1
if [ $stage -le 2 ]; then
  cat exp/tri3_cleanup/all_info.txt | awk -v threshold=$thresh '{ errs=$2;ref=$3; if (errs <= threshold*ref) { print $1; } }' > uttlist
  utils/subset_data_dir.sh --utt-list uttlist data/train data/train_thresh$thresh
fi

if [ $stage -le 3 ]; then
  steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
    data/train_thresh$thresh data/lang exp/tri3 exp/tri3_ali_$thresh
fi

if [ $stage -le 4 ]; then
  steps/train_sat.sh  --cmd "$train_cmd" \
    5000 50000 data/train_thresh$thresh data/lang exp/tri3_ali_$thresh exp/tri3_$thresh || exit 1;
fi

if [ $stage -le 5 ]; then
  utils/mkgraph.sh data/lang_tg exp/tri3_$thresh exp/tri3_$thresh/graph_tg || exit 1
  steps/decode_fmllr.sh --nj 3 --cmd "$decode_cmd" --config conf/decode.config \
    exp/tri3_$thresh/graph_tg data/dev exp/tri3_$thresh/decode_tg || exit 1
fi

# # Results with the original data. 74 hr of Althingi speeches.
# %WER 33.31 [ 4093 / 12289, 866 ins, 834 del, 2393 sub ] exp/tri3/decode_tg2/wer_13_0.0

# # Results with cleaned up subset of the data (at threshold 0.2)
# %WER 32.44 [ 3987 / 12289, 860 ins, 777 del, 2350 sub ] exp/tri3_0.2/decode_tg/wer_13_0.0



