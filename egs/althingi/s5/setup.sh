#!/bin/bash

. path.sh

echo Setting up symlinks
ln -sfn $KALDI_ROOT/egs/wsj/s5/steps steps
ln -sfn $KALDI_ROOT/egs/wsj/s5/utils utils
ln -sfn $KALDI_ROOT/egs/wsj/s5/rnnlm rnnlm

echo Done
