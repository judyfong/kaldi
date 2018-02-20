#!/bin/bash

set -e -o pipefail -u

# Get unigram counts for the LM train and dev files
# f.ex. local/rnnlm/get_unigram_counts.sh data/rnnlm

if [ $# != 1 ]; then
  echo "Usage: $0 <text-dir>"
  echo "Makes sure unigram counts (*.counts) are present in <text-dir>,"
  echo "and if not, sets them up."
  exit 1;
fi


dir=$1

for f in `ls $dir/*.txt`; do
  counts_file=$(echo $f | sed s/.txt$/.counts/)
  if [ ! -f $counts_file -o $counts_file -ot $f ]; then
    echo "$0: generating counts file for $f" 1>&2
    cat $f | awk '{for(i = 1; i <= NF; i++) {print $i;} print "</s>"}' | \
	sort --parallel=8 | uniq -c | awk '{print $2,$1}' > $counts_file
done
