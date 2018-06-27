#!/bin/bash -e

set -o pipefail

nj=
ext=

. ./path.sh
. parse_options.sh

if [ $# -ne 2 ]; then
  echo "This script fixes spelling errors in the intermediate parliamentary text transcripts"
  echo "by comparing them to the vocabulary in the final versions."
  echo ""
  echo "Usage: $0 <vocab-in-final> <output-data-dir> <which-subdir> <number-of-subdirs>" >&2
  echo "e.g.: $0 /data/local/corpus data/all" >&2
  exit 1;
fi

words_text_endanlegt=$1
outdir=$2

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

IFS=$'\n' # Important
for speech in $(cat ${outdir}/split${nj}/text_exp2_bb.${ext})
do
    uttID=$(echo $speech | cut -d" " -f1) || exit 1;
    echo $speech | cut -d" " -f2- | sed 's/[0-9\.,:;?!%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${tmp}/vocab_speech.${ext} || exit 1;
    
    # Find words that are not in any text_endanlegt speech 
    comm -23 <(cat ${tmp}/vocab_speech.${ext}) <(cat $words_text_endanlegt) > ${tmp}/vocab_speech_only.${ext} || exit 1;
    
    grep $uttID ${outdir}/text_exp2_endanlegt.txt > ${tmp}/text_endanlegt_speech.${ext} || exit 1;
    cut -d" " -f2- ${tmp}/text_endanlegt_speech.${ext} | sed 's/[0-9\.,:;?!%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${tmp}/vocab_text_endanlegt_speech.${ext} || exit 1;

    echo $speech > ${tmp}/speech.${ext}
    
    # Find the closest match in vocab_text_endanlegt_speech.tmp and substitute
    #set +u # Otherwise I will have a problem with unbound variables
    python local/MinEditDist.py ${tmp}/speech.${ext} ${outdir}/split${nj}/text_bb_SpellingFixed.${ext}.txt ${tmp}/vocab_speech_only.${ext} ${tmp}/vocab_text_endanlegt_speech.${ext} || exit 1;	
done

exit 0;
