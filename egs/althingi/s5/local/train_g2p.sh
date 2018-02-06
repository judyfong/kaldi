#!/bin/bash -eu

# Train a g2p model based on the Althingi projects pron dict, excluding foreign words. See: https://github.com/sequitur-g2p/sequitur-g2p

. ./path.sh

dictdir=/home/staff/inga/data/althingi/pronDict_LM
# Remove non-Icelandic words
#comm -13 <(sort ${dictdir}/erlend_ord_wtrans.txt | uniq) <(sort ${dictdir}/CaseSensitive_pron_dict_Fix16.txt | uniq) > ${dictdir}/g2p_pron_dict_Fix16.txt
modeldir=data/local/g2p
id=_jan18

n=4 # Number of training iterations

# 1) Make a train and a test lex
#    Randomly select 50 words for a test set
sort -R ${dictdir}/g2p_pron_dict_Fix16.txt > ${dictdir}/shuffled_prondict.tmp
head -n 200 ${dictdir}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_test${id}.lex
tail -n +201 ${dictdir}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_train${id}.lex
rm ${dictdir}/shuffled_prondict.tmp

# 2) Train a model
#    Train the first model, will be rather poor because it is only a unigram
utils/slurm.pl --mem 4G ${modeldir}/g2p_1${id}.log g2p.py --train ${dictdir}/g2p_train${id}.lex --devel 5% --encoding="UTF-8" --write-model ${modeldir}/g2p_1${id}.mdl

#    To create higher order models you need to run g2p.py again a few times
for i in `seq 1 $[$n-1]`; do
    utils/slurm.pl --mem 4G --time 0-06 ${modeldir}/g2p_$[$i+1]${id}.log g2p.py --model ${modeldir}/g2p_${i}${id}.mdl --ramp-up --train ${dictdir}/g2p_train${id}.lex --devel 5% --encoding="UTF-8" --write-model ${modeldir}/g2p_$[$i+1]${id}.mdl
done

# 3) Evaluate the model
#    To find out how accurately your model can transcribe unseen words type:
g2p.py --model ${modeldir}/g2p_${n}${id}.mdl --encoding="UTF-8" --test ${dictdir}/g2p_test${id}.lex

# If happy with the model I would rename it to g2p.mdl
# mv ${modeldir}/g2p_${n}.mdl ${modeldir}/g2p.mdl

# 4) Transcribe new words.
#   Prepare a list of words you want to transcribe as a simple text
#   file words.txt with one word per line (and no phonemic
#   transcription), then type:
# local/transcribe_g2p.sh data/local/g2p words.txt > transcribed_words.txt
# The above script contains: g2p.py --apply $wordlist --model $model --encoding="UTF-8"
