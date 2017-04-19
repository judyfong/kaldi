#!/bin/bash -eu

set -o pipefail

. ./path.sh

# Make lang dir
mkdir -p data/local/dict_cs
frob=~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix6.txt
local/prep_lang.sh \
    $frob             \
    data/local/dict_cs     \
    data/lang_cs

echo "pruned 3g LM"
mkdir -p data/lang_3g_cs_023pruned
for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                        topo words.txt; do
    [ ! -e data/lang_3g_cs_023pruned/$s ] && cp -r data/lang_cs/$s data/lang_3g_cs_023pruned/$s
done

/opt/kenlm/build/bin/lmplz \
    --skip_symbols \
    -o 3 -S 70% --prune 0 2 3 \
    --text ~/data/althingi/pronDict_LM/LMtexts_CaseSens.txt \
    --limit_vocab_file <(cat data/lang_3g_cs_023pruned/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
    | gzip -c > data/lang_3g_cs_023pruned/kenlm_3g_cs_023pruned.arpa.gz

    utils/slurm.pl data/lang_3g_cs_023pruned/format_lm.log utils/format_lm.sh data/lang_cs data/lang_3g_cs_023pruned/kenlm_3g_cs_023pruned.arpa.gz data/local/dict_cs/lexicon.txt data/lang_3g_cs_023pruned

echo "unpruned 5g LM"
mkdir -p data/lang_5g_cs
for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                        topo words.txt; do
    [ ! -e data/lang_5g_cs/$s ] && cp -r data/lang_cs/$s data/lang_5g_cs/$s
done

/opt/kenlm/build/bin/lmplz \
    --skip_symbols \
    -o 5 -S 70% --prune 0 \
    --text ~/data/althingi/pronDict_LM/LMtexts_CaseSens.txt \
    --limit_vocab_file <(cat data/lang_5g_cs/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
    | gzip -c > data/lang_5g_cs/kenlm_5g_cs.arpa.gz

    utils/slurm.pl --mem 4G data/lang_5g_cs/format_lm.log utils/format_lm.sh data/lang_cs data/lang_5g_cs/kenlm_5g_cs.arpa.gz data/local/dict_cs/lexicon.txt data/lang_5g_cs

