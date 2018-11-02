#!/bin/bash -eu

set -o pipefail

# Run from the s5 directory
# Take in all new words, confirmed by editors, and update the pronunctiation dictionary,
# the language models, the decoding graph and the latest bundle.

. ./path.sh # the $root_* variable are defined here
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

#date
d=$(date +'%Y%m%d')

confirmed_vocab_dir=$root_confirmed_vocab
vocab_archive=$root_confirmed_vocab_archive
prondir=$root_lexicon
current_prondict=$(ls -t $prondir/prondict.*.txt | head -n1)
lm_transcript_dir=$root_lm_transcripts
lm_training_dir=$root_lm_training
current_LM_training_texts=$(ls -t $lm_training_dir/*.txt | head -n1)
lm_modeldir=$root_lm_modeldir/$d

# Temporary dir used when creating data/lang dirs in local/prep_lang.sh
localdict=$root_localdict # Byproduct of local/prep_lang.sh

for f in $current_prondict $current_LM_training_texts; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

# Do I want to overwrite or not?
[ -f $prondir/prondict.${d}.txt ] && \
  echo "$0: $prondir/prondict.${d}.txt already exists. Are you sure you want to overwrite it?" \
  && exit 1;

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# I need to gather all new confirmed vocab and relevant new transcripts in the lm dir (I can match them by their file names (speechname.txt))

if [ $stage -le 1 ]; then
  
  # Update the prondict
  cat $confirmed_vocab_dir/*.txt $current_prondict | sort -u > $prondir/prondict.${d}.txt

  # Use a list of speeches with new vocab, to extract the relevant texts
  # NOTE! If I do it like this then I need to constantly remove from the
  # $root_confirmed_vocab dir what has already been added to the prondict
  # Maybe I should find another solution. I could also move the files I'm using into another archive directory and keep this one for new confirmed vocab.
  ls $confirmed_vocab_dir/*.txt > $tmp/confirmed_vocab_list.tmp

  for f in $(cat $tmp/confirmed_vocab_list.tmp); do
    cat $lm_transcript_dir/$f >> $tmp/new_texts.tmp
    mv $confirmed_vocab_dir/$f $vocab_archive/$f
  done

  # Update the LM training texts
  cat $tmp/new_texts.tmp $current_LM_training_texts > $lm_training_dir/LMtext.${d}.txt
fi

if [ $stage -le 2 ]; then

  echo "Update the lang dir and the language models"
  mkdir -p $lm_modeldir/log
  utils/slurm.pl --mem 8G $lm_modeldir/log/make_lang_and_LM_3gsmall.log \
    local/update_lm.sh \
      --order 3 --small true --carpa false \
    || error 1 "ERROR: Failed creating a pruned trigram language model"
		 
  utils/slurm.pl --mem 12G $lm_modeldir/log/make_LM_5g.log \
    local/update_lm.sh \
      --stage 2 --order 5 --small false --carpa true \
    || error 1 "ERROR: Failed creating an unpruned 5-gram language model"
fi

if [ $stage -le 3 ]; then

  echo "Update the decoding graph"
  local/update_graph.sh || error 1 "ERROR: update_graph.sh failed"
  
fi

if [ $stage -le 4 ]; then

  echo "Update latest"
  local/update_latest.sh || error 1 "ERROR: update_latest.sh failed"

fi
