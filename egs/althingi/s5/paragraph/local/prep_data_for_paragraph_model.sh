#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

. ./path.sh
. ./local/utils.sh
. ./local/array.sh

if [ $# -ne 2 ]; then
  echo "This script prepares XML text data to be used to train a model in learning"
  echo "the positions of paragraph breaks. It switches the XML tags </mgr><mgr> out for"
  echo "' EOP ', removes the remaining XML tags and splits the data into train/test sets"
  exit 1;
fi

indir=$1
dir=$2 #paragraph/data/may18
mkdir -p $dir

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

for d in $indir/all_*; do
sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' -e 's:</mgr><mgr>: EOP :g' -e 's:<[^>]*?>: :g' \
  -e 's:\([^/()<>]*?\)+: :g' \
  -e 's:^rad[0-9T]+ ::' \
  -e 's:[[:space:]]+: :g' \
  < ${d}/text_orig_endanlegt.txt \
  >> ${tmp}/text_noXML_endanlegt.txt || error 13 $LINENO ${error_array[13]};
done

# Split up to train, dev and test set
nlines20=$(echo $((($(wc -l ${tmp}/text_noXML_endanlegt.txt | cut -d" " -f1)+1)/5)))
sort -R ${tmp}/text_noXML_endanlegt.txt > ${tmp}/shuffled.tmp || error 13 $LINENO ${error_array[13]};

head -n $[$nlines20/2] ${tmp}/shuffled.tmp \
     > ${dir}/althingi.dev.txt || error 14 $LINENO ${error_array[14]};
tail -n $[$nlines20/2+1] ${tmp}/shuffled.tmp | head -n $[$nlines20/2] \
     > ${dir}/althingi.test.txt || error 14 $LINENO ${error_array[14]};
tail -n +$[$nlines20+1] ${tmp}/shuffled.tmp \
     > ${dir}/althingi.train.txt || error 14 $LINENO ${error_array[14]};

exit 0;
