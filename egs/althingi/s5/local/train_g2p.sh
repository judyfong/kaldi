#!/bin/bash -eu

# Train a g2p model based on the Althingi projects pron dict, excluding foreign words. See: https://github.com/sequitur-g2p/sequitur-g2p

. ./path.sh

dict=~/data/althingi/pronDict_LM/g2p_pron_dict.txt
dictdir=`dirname $dict`;
#dictdir=~/data/althingi/pronDict_LM
modeldir=data/local/g2p

n=5 # Number of training iterations

# 1) Make a train and a test lex
#    Randomly select 50 words for a test set
sort -R $dict > ${dictdir}/shuffled_prondict.tmp
head -n 50 ${dictdir}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_test.lex
head -n -50 ${dictdir}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_train.lex
rm ${dictdir}/shuffled_prondict.tmp

# 2) Train a model
#    Train the first model, will be rather poor because it is only a unigram
utils/slurm.pl --mem 4G ${modeldir}/g2p_1.log g2p.py --train ${dictdir}/g2p_train.lex --devel 5% --encoding="UTF-8" --write-model ${modeldir}/g2p_1.mdl

#    To create higher order models you need to run g2p.py again a few times
for i in `seq 1 $n`; do
    utils/slurm.pl --mem 4G --time 0-06 ${modeldir}/g2p_$[$i+1].log g2p.py --model ${modeldir}/g2p_${i}.mdl --ramp-up --train ${dictdir}/g2p_train.lex --devel 5% --encoding="UTF-8" --write-model ${modeldir}/g2p_$[$i+1].mdl
done

# 3) Evaluate the model
#    To find out how accurately your model can transcribe unseen words type:
g2p.py --model ${modeldir}/g2p_${n}.mdl --encoding="UTF-8" --test ${dictdir}/g2p_test.lex

# If happy with the model I would rename it to g2p.mdl
# mv ${modeldir}/g2p_${n}.mdl ${modeldir}/g2p.mdl

# 4) Transcribe new words.
#   Prepare a list of words you want to transcribe as a simple text
#   file words.txt with one word per line (and no phonemic
#   transcription), then type:
# local/transcribe_g2p.sh data/local/g2p words.txt > transcribed_words.txt
# The above script contains: g2p.py --apply $wordlist --model $model --encoding="UTF-8"
