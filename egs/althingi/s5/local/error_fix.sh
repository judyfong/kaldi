#!/bin/bash -eu

set -o pipefail

# Get the Althingi data on a proper format for kaldi
# 2016 Inga Rún

. ./path.sh

datadir=data/all
splitdir=data/all_split

echo "Fix spelling errors"
cut -d" " -f2- ${datadir}/text_noPuncts_endanlegt.txt | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | grep -v "^$" | sort -u > ${datadir}/words_text_endanlegt.txt
abbr_expanded=$(cut -f2 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_multiple_expansions.txt)
for abbr in $abbr_expanded
do
    grep -q "\b${abbr}\b" ${datadir}/words_text_endanlegt.txt || echo -e ${abbr} >> ${datadir}/words_text_endanlegt.txt
done

# Add numbers to the list
cut -f2 text_norm/lex/ordinals_*?_lexicon.txt >> ${datadir}/words_text_endanlegt.txt
cut -f2 text_norm/lex/units_lexicon.txt >> ${datadir}/words_text_endanlegt.txt
cut -f2 text_norm/lex/factors_lexicon.txt >> ${datadir}/words_text_endanlegt.txt
sort ${datadir}/words_text_endanlegt.txt | uniq > tmp && mv tmp ${datadir}/words_text_endanlegt.txt

#for speech in $(cat ${datadir}/PHB_rad20140320T195206)
IFS=$'\n' # IMPORTANT
for speech in $(cat ${splitdir}/text.orig)
do
    #echo $speech > speech.tmp
    uttID=$(echo $speech | cut -d" " -f1)
    echo $speech | cut -d" " -f2- | tr " " "\n" | grep -v "^$" | sort -u > vocab_speech.tmp
    comm -23 <(cat vocab_speech.tmp) <(sort ${datadir}/words_text_endanlegt.txt) > vocab_speech_only.tmp # not in any text_endanlegt speech
    
    grep $uttID".*" ${datadir}/text_noPuncts_endanlegt.txt > text_endanlegt_speech.tmp
    cut -d" " -f2- text_endanlegt_speech.tmp | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | grep -v "^$" | sort -u > vocab_text_endanlegt_speech.tmp

    # Find an approximate match in the vocab_text_endanlegt_speech
    # Substitute $word and the match in $speech
    python3 local/MinEditDist.py "$speech" text.orig_fixed vocab_speech_only.tmp vocab_text_endanlegt_speech.tmp
done
rm *.tmp
