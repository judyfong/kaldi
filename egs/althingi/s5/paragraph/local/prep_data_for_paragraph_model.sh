#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Introduce a paragraph token where there are "</mgr><mgr>" tags. Want to learn the position of those.

. ./path.sh
. ./utils/parse_options.sh

dir=$1 #paragraph/data/may18
mkdir -p $dir

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

for d in data/all_{mars18,nov2016,okt2017,sept2017}; do
sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' -e 's:</mgr><mgr>: EOP :g' -e 's:<[^>]*?>: :g' \
  -e 's:\([^/()<>]*?\)+: :g' \
  -e 's:^rad[0-9T]+ ::' \
  -e 's:[[:space:]]+: :g' ${d}/text_orig_endanlegt.txt >> ${tmp}/text_noXML_endanlegt.txt
done

# Split up to train, dev and test set
nlines20=$(echo $((($(wc -l ${tmp}/text_noXML_endanlegt.txt | cut -d" " -f1)+1)/5)))
sort -R ${tmp}/text_noXML_endanlegt.txt > ${tmp}/shuffled.tmp

head -n $[$nlines20/2] ${tmp}/shuffled.tmp > ${dir}/althingi.dev.txt
tail -n $[$nlines20/2+1] ${tmp}/shuffled.tmp | head -n $[$nlines20/2] > ${dir}/althingi.test.txt
tail -n +$[$nlines20+1] ${tmp}/shuffled.tmp > ${dir}/althingi.train.txt

