#!/bin/bash

# Copyright 2012  Johns Hopkins University (author: Daniel Povey)
#           2015  Guoguo Chen
#           2017  Hainan Xu
#           2017  Xiaohui Zhang

# This script trains LMs on the swbd LM-training data.

# Begin configuration section.

embedding_dim=1024
lstm_rpd=256
lstm_nrpd=256
stage=-10
train_stage=-10

# variables for lattice rescoring
run_lat_rescore=true
decode_dir_suffix=rnnlm_1e
ngram_order=4 # approximate the lattice-rescoring by limiting the max-ngram-order
              # if it's set, it merges histories in the lattice if they share
              # the same ngram history and this prevents the lattice from 
              # exploding exponentially
pruned_rescore=true
LM=5g # using the 5-gram const arpa file as old lm

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh
. ./conf/path.conf # Here $data, $exp and $mfcc are defined, default to /mnt/scratch/inga/


ac_model_dir=$exp/chain/tdnn_lstm_2_sp      #tdnn_sp
text=/data/althingi/text_corpus/LMtext_2004-2018.txt # excluding text in test sets for the acoustic training
lexicon=$root_localdict/lexiconp.txt #$data/local/dict/lexiconp.txt
ngram_lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)

data_dir=$data/rnnlm
dir=$exp/rnnlm_lstm_1e

text_dir=$data_dir/text_1e
mkdir -p $dir/config
set -e

for f in $text $lexicon; do
  [ ! -f $f ] && \
    echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 0 ]; then
  mkdir -p $text_dir
  echo -n >$text_dir/dev.txt
  # hold out one in every 50 lines as dev data.
  cat $text | awk -v text_dir=$text_dir '{if(NR%50 == 0) { print >text_dir"/dev.txt"; } else {print;}}' >$text_dir/althingi_train.txt
fi

if [ $stage -le 1 ]; then
  cp data/lang/words.txt $dir/config/
  n=`cat $dir/config/words.txt | wc -l`
  echo "<brk> $n" >> $dir/config/words.txt

  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <SPOKEN_NOISE> during training.
  echo "<unk>" >$dir/config/oov.txt

  # Choose weighting and multiplicity of data.
  # The following choices would mean that data-source 'foo'
  # is repeated once per epoch and has a weight of 0.5 in the
  # objective function when training, and data-source 'bar' is repeated twice
  # per epoch and has a data -weight of 1.5.
  # There is no constraint that the average of the data weights equal one.
  # Note: if a data-source has zero multiplicity, it just means you are ignoring
  # it; but you must include all data-sources.
  #cat > exp/foo/data_weights.txt <<EOF
  #foo 1   0.5
  #bar 2   1.5
  #baz 0   0.0
  #EOF  
  cat > $dir/config/data_weights.txt <<EOF
althingi_train   1   1.0
EOF

  # we need the unigram probs to get the unigram features.
  rnnlm/get_unigram_probs.py --vocab-file=$dir/config/words.txt \
                             --unk-word="<unk>" \
                             --data-weights-file=$dir/config/data_weights.txt \
                             $text_dir | awk 'NF==2' >$dir/config/unigram_probs.txt

  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<unk>' \
                           $dir/config/words.txt > $dir/config/features.txt

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=$embedding_dim input=Append(0, IfDefined(-1))
fast-lstmp-layer name=lstm1 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn2 dim=$embedding_dim input=Append(0, IfDefined(-3))
fast-lstmp-layer name=lstm2 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn3 dim=$embedding_dim input=Append(0, IfDefined(-3))
output-layer name=output include-log-softmax=false dim=$embedding_dim
EOF
  rnnlm/validate_config_dir.sh $text_dir $dir/config
fi

if [ $stage -le 2 ]; then
  rnnlm/prepare_rnnlm_dir.sh --cmd "$train_cmd" $text_dir $dir/config $dir
fi

if [ $stage -le 3 ]; then
  rnnlm/train_rnnlm.sh \
    --num-jobs-initial 3 \
    --num-jobs-final 12 \
    --stage $train_stage \
    --num-epochs 10 \
    --cmd "$decode_cmd --time 2-00" $dir
fi

# Calculate the lattice-rescoring time
begin=$(date +%s)

if [ $stage -le 4 ] && $run_lat_rescore; then
  echo "$0: Perform lattice-rescoring on $ac_model_dir"
#  LM=sw1_tg # if using the original 3-gram G.fst as old lm
  pruned=
  if $pruned_rescore; then
    pruned=_pruned
  fi
  for decode_set in dev eval; do
    (
    decode_dir=${ac_model_dir}/decode_${decode_set}_${LM}

    # Lattice rescoring
    rnnlm/lmrescore$pruned.sh \
      --cmd "$decode_cmd" \
      --weight 0.5 --max-ngram-order $ngram_order \
      $ngram_lmdir/lang_$LM $dir \
      $data/${decode_set}_hires ${decode_dir} \
      ${decode_dir}_${decode_dir_suffix}
    ) &
  done
fi

end=$(date +%s)
tottime=$(expr $end - $begin)
echo "total time: $tottime seconds"

exit 0
