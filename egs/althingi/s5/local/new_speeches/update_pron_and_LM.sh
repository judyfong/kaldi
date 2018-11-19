#!/bin/bash -e

set -o pipefail

# Run from the s5 directory
# Take in new speech transcripts cleaned for language modelling and new words,
# confirmed by editors, and update the pronunctiation dictionary,
# the language models, the decoding graph and the latest bundle.

# As this script is written, it is asumed that it will not be run when many the editors are working.
# Otherwise some vocab could be moved straight to the archive and not to the pron dict.

stage=0

. ./path.sh # the $root_* variable are defined here
. ./cmd.sh
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
lm_transcripts_archive=$root_lm_transcripts_archive
lm_training_dir=$root_lm_training
current_LM_training_texts=$(ls -t $lm_training_dir/*.txt | head -n1)
lm_modeldir=$root_lm_modeldir/$d

# Temporary dir used when creating data/lang dirs in local/prep_lang.sh
localdict=$root_localdict # Byproduct of local/prep_lang.sh

for f in $current_prondict $current_LM_training_texts; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $stage -le 1 ]; then

  # Do I want to overwrite or not?
  [ -f $prondir/prondict.${d}.txt ] && \
  echo "$0: $prondir/prondict.${d}.txt already exists. Are you sure you want to overwrite it?" \
  && exit 1;

  if [ "$(ls -A $lm_transcript_dir)" ]; then
    echo "Update the LM training texts"
    cat $current_LM_training_texts $lm_transcript_dir/*.txt > $lm_training_dir/LMtext.${d}.txt
    mv $lm_transcript_dir/*.txt $lm_transcripts_archive/
  else
    echo "There are no new transcripts to add to the language models"
    exit 1;
  fi

  # Update the prondict if there is new confirmed vocabulary, and move those vocab files to the archive
  if [ "$(ls -A $confirmed_vocab_dir)" ]; then
    echo "Update the pronunciation dictionary"
    cat $confirmed_vocab_dir/*.txt $current_prondict | sort -u > $prondir/prondict.${d}.txt
    mv $confirmed_vocab_dir/*.txt $vocab_archive/ 
  fi
    
  # # Select all language models training texts from the last time the language model was updated
  # if [ -f $newest -a -f $archive_newest ]; then
  #   n1=$(grep -n $archive_newest $tmp/lm_transcript_list.tmp | cut -d':' -f1)
  #   n2=$(grep -n $newest $tmp/lm_transcript_list.tmp | cut -d':' -f1)
  #   head -n $[$n1-1] $tmp/lm_transcript_all.tmp | tail -n +$n2 > $tmp/lm_texts_list.tmp
  # elif [ -f $newest -a ! -f $archive_newest ]; then
  #   n1=$(grep -n $oldest $tmp/lm_transcript_list.tmp | cut -d':' -f1)
  #   n2=$(grep -n $newest $tmp/lm_transcript_list.tmp | cut -d':' -f1)
  #   head -n $n1 $tmp/lm_transcript_all.tmp | tail -n +$n2 > $tmp/lm_texts_list.tmp
  # elif [ ! -f $newest -a -f $archive_newest ]; then
  #   n1=$(grep -n $archive_newest $tmp/lm_transcript_list.tmp | cut -d':' -f1)
  #   head -n $[$n1-1] $tmp/lm_transcript_all.tmp > $tmp/lm_texts_list.tmp    
  # else
  #   echo "No new or former new vocabulary files to base the language text selection on"
  #   exit 1;
  # fi
  
fi

if [ $stage -le 2 ]; then

  echo "Update the lang dir"

  # Make lang dir
  prondict=$(ls -t $prondir/prondict.*.txt | head -n1)
  [ -d $localdict ] && rm -r $localdict
  mkdir -p $localdict $lm_modeldir/lang
  
  local/prep_lang.sh \
    $prondict        \
    $localdict   \
    $lm_modeldir/lang

  echo "Preparing a pruned trigram language model"
  mkdir -p $lm_modeldir/log
  $train_cmd --mem 12G $lm_modeldir/log/make_LM_3gsmall.log \
    local/make_LM.sh \
      --order 3 --small true --carpa false \
      $lm_training_dir/LMtext.${d}.txt $lm_modeldir/lang \
      $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating a pruned trigram language model"
  
  echo "Preparing an unpruned 5g LM"
  mkdir -p $lm_modeldir/log
  $train_cmd --mem 20G $lm_modeldir/log/make_LM_5g.log \
    local/make_LM.sh \
      --order 5 --small false --carpa true \
      $lm_training_dir/LMtext.${d}.txt $lm_modeldir/lang \
      $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating an unpruned 5-gram language model"
  
fi

if [ $stage -le 3 ]; then

  echo "Update the decoding graph"
  local/update_graph.sh || error 1 "ERROR: update_graph.sh failed"
  
fi

if [ $stage -le 4 ]; then

  echo "Update latest"
  local/update_latest.sh || error 1 "ERROR: update_latest.sh failed"

fi

exit 0;
