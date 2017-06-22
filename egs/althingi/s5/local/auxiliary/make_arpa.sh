#!/bin/bash -eu

set -o pipefail

# 2016 Inga Run

# OLD! Now I use kenLM! See run.sh

echo "$0 $@"  # Print the command line for logging

. ./path.sh || exit 1;

order=3

. utils/parse_options.sh || exit 1;
. local/utils.sh || exit 1;

if [ $# -ne 2 ]; then
    echo "usage: local/make_arpa.sh <textfile> <dest-dir>"
    echo "e.g.: local/make_arpa.sh data/train/LMtext data/lang_tg"
    echo "options: "
    echo "   --order <ngram order>      # default trigram"
    exit 1;
fi

data=$1;
destdir=$2;

# Get the lm suffix
lm_suffix=$(echo "$destdir" | awk -F'[_.]' '{print $2}')

# # Copy everything from data/lang into dest-dir
# mkdir -p $destdir
# cp -r data/lang/* $destdir || exit 1;

loc=`which estimate-ngram`;
if [ -z $loc ]; then
    sdir=/opt/mitlm/bin
    if [ -f $sdir/estimate-ngram ]; then
        echo "Using MITLM language modelling tool from $sdir"
    	export PATH=$PATH:$sdir
    else
        echo "MITLM toolkit is probably not installed."
    	exit 1
    fi
fi

estimate-ngram -order $order -vocab <(cat $destdir/words.txt | egrep -v "<eps>|<s>|</s>|#" | cut -d' ' -f1) -text $data -wl $destdir/lm_${lm_suffix}.arpa.gz

echo "Wrote the arpa file lm_${lm_suffix}.arpa.gz in $destdir"

exit 0
