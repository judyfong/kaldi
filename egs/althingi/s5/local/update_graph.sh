#!/bin/bash

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;

#date
d=$(date +'%Y%m%d')

lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)
decoding_lang=$lmdir/lang_3gsmall

am_model=$(ls -td $root_chain/*/*/* | head -n1)
ampath=$(dirname $am_model)

# if [ ! $# = 2 ]; then
#   echo "This script updates the graph, creates a new acoustic model directory and updates latest. Usually performed after a language models have been updated."
#   echo ""
#   echo "Usage: $0 <input-AM-model-dir> <output-AM-model-dir>"
#   echo " e.g.: $0 ~/models/acoustic_model/chain/5.4/tdnn_2/ /models/acoustic_model/chain/5.4/20180907/tdnn_2/"
#   exit 1;
# fi

# indir=$(realpath $1)
# outdir=$(realpath $2)
outdir=$ampath/$d
[ -d $outdir ] && echo "$outdir already exists" && exit 1;
mkdir -p $outdir/log

echo "Make a small 3-gram graph"
utils/slurm.pl --mem 8G $outdir/log/mkgraph.log utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $am_model $outdir/graph_3gsmall

# Create symlinks in the new model dir to the old one
for f in cmvn_opts extractor final.ie.id final.mdl frame_subsampling_factor tree ; do
  ln -s $am_model/$f $outdir/$f
done
ln -s $(dirname $decoding_lang) $outdir/lmdir

exit 0;
