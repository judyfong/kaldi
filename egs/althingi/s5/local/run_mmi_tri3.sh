#!/bin/bash
. ./cmd.sh

# "MMI on top of tri3 (i.e. LDA+MLLT+SAT+MMI)"

steps/make_denlats.sh \
    --config conf/decode.config \
    --nj $nj --cmd "$train_cmd" \
    --transform-dir exp/tri3_ali \
    data/train data/lang \
    exp/tri3 exp/tri3_denlats || exit 1;

steps/train_mmi.sh \
    --boost 0.1 \
    data/train data/lang \
    exp/tri3_ali \
    exp/tri3_denlats \
    exp/tri3_mmi_b0.1 || exit 1;

steps/decode_fmllr.sh \
    --config conf/decode.config \
    --nj $nj_decode --cmd "$decode_cmd" \
    --alignment-model exp/tri3/final.alimdl \
    --adapt-model exp/tri3/final.mdl \
    exp/tri3/graph_tg data/dev \
    exp/tri3_mmi_b0.1/decode_tg_dev || exit 1;

steps/decode_fmllr.sh \
    --config conf/decode.config \
    --nj $nj_decode --cmd "$decode_cmd" \
    --alignment-model exp/tri3/final.alimdl \
    --adapt-model exp/tri3/final.mdl \
    exp/tri3/graph_tg data/test \
    exp/tri3_mmi_b0.1/decode_tg_test || exit 1;
