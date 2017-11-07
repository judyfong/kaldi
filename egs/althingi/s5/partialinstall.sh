#!/bin/bash -eu

rm steps
rm utils
ln -s ../../wsj/s5/utils utils
ln -s ../../wsj/s5/steps steps

#Make folders if they don't exist

#Chain LSTM model
cp -r decodeinstall/chain/exp  exp
#exp/chain/tdnn_lstm_1e_sp/graph_3gsmall
#exp/chain/tdnn_lstm_1e_sp/lang_3gsmall
#exp/chain/tdnn_lstm_1e_sp/lang_5g
#exp/chain/tdnn_lstm_1e_sp/final.mdl
#exp/chain/tdnn_lstm_1e_sp/final.ie.id
#exp/chain/tdnn_lstm_1e_sp/cmvn_opts
#exp/chain/tdnn_lstm_1e_sp/frame_subsampling_factor
cp -r decodeinstall/chain/data data
#data/lang_3gsmall
#data/lang_5g
