#!/bin/bash -e

set -o pipefail

# Update the models used by the recognizer
# Info on the training data used to create the models is in the log files for the acoustic and ngram and rnn language models, 
# NOTE! For those of above which are dependent on certain versions of training data, can I have at their original location an info files listing the version of the training data (e.g. $root_punctuation_datadir/$d ) ?
# So in each bundle I could do something like `cat $bundle/punctuation_model/training_data_info`


# Copyright 2018  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# files needed in recognize.sh:
# extractor
# acoustic_model
# decoding_lang
# rescoring_lang
# rescoring_lang_rnn
# graph

# denormalize.sh:
# utf8.syms
# ambiguous_personal_names
# text_norm  <-- contains the fsts
# punctuation_model
# paragraph_model

# NOTE! I need to make an easy way of updating the LMs and then the graph needs to be updated as well.
# Where will I store the graph?

  # graph is dependent on decoding_lang and the acoustic model.
  # rescoring and decoding LMs need to be compatible
  # All the files used in denormalize are independent of each other so latest can be updated
  # if any one of those is updated
  # If the LM's are updated, latest can be updated, given that mkgraph.sh is run if needed
  # If rescoring_lang_rnn is not updated but the other ones are, then I need to change
  # recognize.sh such that if rnnlm=true then the latest bunch containing it will be used
  # I will make it available to not use the newest version of everything. Then the preferred version
  # can be given as an option

extractor=
acoustic_model=
punct_model=
paragraph_model=
text_norm=

# Define the paths. path.sh also called conf/path.conf
. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;
. ./local/utils.sh

#date
d=$(date +'%Y%m%d')

latest=$root_bundle/latest
thisbundle=$root_bundle/$d
[ -d $thisbundle ] && echo "$thisbundle already exists" && exit 1;
mkdir -p $thisbundle

# Choose the newest version if not provided a specific version
[ -z $acoustic_model ] && acoustic_model=$(ls -td $root_chain/*/*/* | head -n1) \
    || error 1 "Failed setting acoustic_model variable";
[ -z $extractor ] && extractor=$acoustic_model/extractor \
    || error 1 "Failed setting extractor variable";
lmdir=$acoustic_model/lmdir \
    || error 1 "Failed setting lmdir variable";
#[ -z $rnnlmdir ] && rnnlmdir=$(ls -td $root_rnnlm/2* | head -n1) || error 1 "Failed setting rnnlmdir variable";
graph=$acoustic_model/graph_3gsmall \
    || error 1 "Failed setting graph variable";
[ -z $punct_model ] && punct_model=$(ls -t $root_punctuation_modeldir/2*/*.pcl | head -n1) \
    || error 1 "Failed setting punct_model variable";
[ -z $paragraph_model ] && paragraph_model=$(ls -t $root_paragraph_modeldir/2*/*.pcl | head -n1) \
    || error 1 "Failed setting paragraph_model variable";
[ -z $text_norm ] && text_norm=$(ls -td $root_text_norm_modeldir/2* | head -n1) \
    || error 1 "Failed setting text_norm variable";

# bundle_graph= && if [ -e $root_bundle/*/graph]; then bundle_graph=$root_bundle/*/graph; fi
# newest_graph=$(ls -td $acoustic_model/graph_3gsmall $bundle_graph | head -n1)
# if [ $lmdir/lang_3gsmall/words.txt -nt $newest_graph/words.txt ]; then
#   echo "Make a small 3-gram graph"
#   utils/mkgraph.sh --self-loop-scale 1.0 $lmdir/lang_3gsmall $acoustic_model $thisbundle/graph || error 1 "utils/mkgraph.sh failed!";
# fi

amb_pers_names=$(ls -t $root_capitalization/ambiguous_personal_names.*.txt | head -n1) \
  || error 1 "Failed setting amb_pers_names variable";
utf8syms=$root_listdir/utf8.syms \
  || error 1 "Failed setting utf8syms variable";

# Create symlinks

ln -s $acoustic_model $thisbundle/acoustic_model || error 1 "Failed creating acoustic model symlink";
ln -s $amb_pers_names $thisbundle/ambiguous_personal_names || error 1 "Failed creating ambiguous-names symlink";
ln -s $extractor $thisbundle/extractor || error 1 "Failed creating extractor symlink";
#[ ! -d $thisbundle/graph ] && ln -s $newest_graph $thisbundle/graph || error 1 "Failed creating the graph symlink";
ln -s $graph $thisbundle/graph || error 1 "Failed creating the graph symlink";
ln -s $lmdir/lang_3gsmall $thisbundle/decoding_lang || error 1 "Failed creating the decoding lang symlink";
ln -s $lmdir/lang_5g $thisbundle/rescoring_lang || error 1 "Failed creating the rescoring lang symlink";
ln -s $paragraph_model $thisbundle/paragraph_model || error 1 "Failed creating paragraph model symlink";
ln -s $punct_model $thisbundle/punctuation_model || error 1 "Failed creating punctuation model symlink";
ln -s $text_norm $thisbundle/text_norm || error 1 "Failed creating text_norm symlink";
ln -s $utf8syms $thisbundle/utf8.syms || error 1 "Failed creating the utf8.syms symlink";

if [ ! -d $lmdir/rnn ]; then
  echo "NOTE! No RNN language model exists for this vocabulary, $lmdir"
else
  ln -s $lmdir/rnn $thisbundle/rescoring_lang_rnn || error 1 "Failed creating the RNN rescoring lang symlink";
fi

# ! cmp $thisbundle/decoding_lang/words.txt <(egrep -v "<brk>" $rnnlmdir/config/words.txt) && \
#   echo "$0: Warning: decoding and rnn rescoring LM vocabularies may be incompatible."
# ln -s $rnnlmdir $thisbundle/rescoring_lang_rnn || error 1 "Failed creating rnn lm symlink";

# Let $latest point to $thisbundle
[ -d $latest ] && mv $latest $root_bundle/.oldlatest
ln -s $thisbundle $latest || error 1 "Failed creating the 'latest' dir symlink";

exit 0;

  
