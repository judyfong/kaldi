#!/bin/bash

# To be run from the s5/ directory.

# This is to be done after local/prepare_rnnlm_data.sh.

set -e

embedding_dim=1024
data_dir=data/rnnlm
dir=exp/rnnlm_tdnn
stage=0
train_stage=0

. ./path.sh
. ./cmd.sh
. utils/parse_options.sh   # parse options-- mainly for the --stage parameter.

for f in ${data_dir}/vocab/words.txt ${data_dir}/data/dev.txt; do
  [ ! -f ] && echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 0 ]; then
    mkdir -p $dir/config
    cp ${data_dir}/vocab/words.txt $dir/config/

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
train   1   1.0
EOF

  echo "<unk>" >$dir/config/oov.txt  # not really necessary as OOVs were previously
                              # converted to <unk>, but doesn't hurt.


  # we need the unigram probs to get the unigram features.
  rnnlm/get_unigram_probs.py --vocab-file=$data_dir/vocab/words.txt \
                             --data-weights-file=$dir/config/data_weights.txt \
                             $data_dir/data >$dir/config/unigram_probs.txt


  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<unk>' \
                           $data_dir/vocab/words.txt > $dir/config/features.txt

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=512 input=Append(0, IfDefined(-1))
relu-renorm-layer name=tdnn2 dim=512 input=Append(0, IfDefined(-1))
relu-renorm-layer name=tdnn3 dim=512 input=Append(0, IfDefined(-2))
# check steps/libs/nnet3/xconfig/lstm.py for the other options and defaults
fast-lstmp-layer name=fastlstm1 cell-dim=512 recurrent-projection-dim=128 non-recurrent-projection-dim=128 delay=-3 decay-time=20

output-layer name=output include-log-softmax=false dim=$embedding_dim
EOF

  rnnlm/validate_config_dir.sh $data_dir/data $dir/config
fi


if [ $stage -le 1 ]; then
  rnnlm/prepare_rnnlm_dir.sh --cmd "$train_cmd" $data_dir/data $dir/config $dir
fi

if [ $stage -le 2 ]; then
  rnnlm/train_rnnlm.sh --num-epochs 40 --cmd "$train_cmd" $dir
fi
