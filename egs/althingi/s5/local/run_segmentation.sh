#!/bin/bash

# Copyright 2014  Guoguo Chen
#           2016  Reykjavik University (Inga Rún Helgadóttir)
# Apache 2.0

# This script demonstrates how to re-segment long audios into short segments.
# The basic idea is to decode with an existing in-domain acoustic model, and a
# bigram language model built from the reference, and then work out the
# segmentation from a ctm like file.
# To be run from ..

. ./cmd.sh
. ./path.sh

# # Begin configuration section.
# nj=30
# stage=-4

echo "$0 $@"  # Print the command line for logging

. parse_options.sh || exit 1;

if [ $# != 3 ]; then
    echo "Usage: local/run_segmentation.sh [options] <data-dir> <lang-dir> <model-dir>"
    echo " e.g.: local/run_segmentation.sh data/all data/lang exp/tri2_cleaned"
    exit 1;
fi

datadir=$1
base=$(basename $datadir)
langdir=$2
modeldir=$3

echo "Truncate the long audio into smaller overlapping segments"
steps/cleanup/split_long_utterance.sh \
  --seg-length 30 --overlap-length 5 \
  ${datadir} ${datadir}_split

echo "Make MFCC features and compute CMVN stats"
steps/make_mfcc.sh --cmd "$train_cmd" --nj 64 \
  ${datadir}_split exp/make_mfcc/${base}_split mfcc || exit 1;
utils/fix_data_dir.sh ${datadir}_split
steps/compute_cmvn_stats.sh ${datadir}_split \
  exp/make_mfcc/${base}_split mfcc || exit 1;

echo "Make segmentation graph, i.e. build one decoding graph for each truncated utterance in segmentation."
steps/cleanup/make_segmentation_graph.sh \
  --cmd "$mkgraph_cmd" --nj 64 \
  ${datadir}_split ${langdir} ${modeldir} \
  ${modeldir}/graph_${base}_split || exit 1;

echo "Decode segmentation"
steps/cleanup/decode_segmentation.sh \
  --nj 85 --cmd "$decode_cmd --time 0-12" --skip-scoring true \
  ${modeldir}/graph_${base}_split \
  ${datadir}_split ${modeldir}/decode_${base}_split || exit 1;

echo "Get CTM"
steps/get_ctm.sh --cmd "$decode_cmd" ${datadir}_split \
  ${modeldir}/graph_${base}_split ${modeldir}/decode_${base}_split

echo "Make segmentation data dir"
steps/cleanup/make_segmentation_data_dir.sh --wer-cutoff 0.9 \
  --min-sil-length 0.5 --max-seg-length 15 --min-seg-length 1 \
  ${modeldir}/decode_${base}_split/score_10/${base}_split.ctm \
  ${datadir}_split ${datadir}_reseg

# Here I think I should end this script, go back to run.sh
# and do all training there

# # Now, use the re-segmented data for training.
# steps/make_mfcc.sh --cmd "$train_cmd" --nj 64 \
#   data/all_reseg exp/make_mfcc/all_reseg mfcc || exit 1;
# steps/compute_cmvn_stats.sh data/all_reseg \
#   exp/make_mfcc/all_reseg mfcc || exit 1;

# steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
#   data/all_reseg data/lang exp/tri3b exp/tri3b_ali_si284_reseg || exit 1;

# steps/train_sat.sh  --cmd "$train_cmd" \
#   4200 40000 data/all_reseg \
#   data/lang exp/tri3b_ali_si284_reseg exp/tri4c || exit 1;

# utils/mkgraph.sh data/lang_test_tgpr exp/tri4c exp/tri4c/graph_tgpr || exit 1;
# steps/decode_fmllr.sh --nj 10 --cmd "$decode_cmd" \
#   exp/tri4c/graph_tgpr data/test_dev93 exp/tri4c/decode_tgpr_dev93 || exit 1;
# steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" \
#   exp/tri4c/graph_tgpr data/test_eval92 exp/tri4c/decode_tgpr_eval92 || exit 1;
