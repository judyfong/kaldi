#!/bin/bash -e

set -o pipefail

outdir=$1
extension=$2
num_files=$3

IFS=$'\n' # Important
for speech in $(cat ${outdir}/split${num_files}/text_exp2_bb.${extension})
do
    uttID=$(echo $speech | cut -d" " -f1)
    echo $speech | cut -d" " -f2- | sed 's/[0-9\.,%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${outdir}/split${num_files}/vocab_speech.${extension}
    
    # Find words that are not in any text_endanlegt speech 
    comm -23 <(cat ${outdir}/split${num_files}/vocab_speech.${extension}) <(cat ${outdir}/words_text_endanlegt.txt) > ${outdir}/split${num_files}/vocab_speech_only.${extension}
    
    grep $uttID ${outdir}/text_exp2_endanlegt.txt > ${outdir}/split${num_files}/text_endanlegt_speech.${extension}
    cut -d" " -f2- ${outdir}/split${num_files}/text_endanlegt_speech.${extension} | sed 's/[0-9\.,%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${outdir}/split${num_files}/vocab_text_endanlegt_speech.${extension}

    echo $speech > ${outdir}/split${num_files}/speech.${extension}
    
    # Find the closest match in vocab_text_endanlegt_speech.tmp and substitute
    #set +u # Otherwise I will have a problem with unbound variables
    python local/MinEditDist.py ${outdir}/split${num_files}/speech.${extension} ${outdir}/split${num_files}/text_bb_SpellingFixed.${extension}.txt ${outdir}/split${num_files}/vocab_speech_only.${extension} ${outdir}/split${num_files}/vocab_text_endanlegt_speech.${extension}	
done
