#!/bin/bash -eu

set -o pipefail

# After segmenting the data calculate words per second
# for each segment - 2016 Inga Rún

if [ $# -ne 1 ]; then
    echo "Usage: $0 <data-dir> " >&2
    echo "Eg. $0 data/all_reseg" >&2
    exit 1;
fi

data=$1
if [ -f ${data}/wps.txt ]; then
  rm ${data}/wps.txt
fi
# Calculate the length of each segment
awk 'NR >= 1 { $5 = $4 - $3 } 1' < ${data}/segments > segments_diff.tmp
awk '{print NF-1" "$0}' < ${data}/text  > wordcount.tmp
join -1 1 -2 2 segments_diff.tmp wordcount.tmp > wc_sec.tmp # Join on uttID
awk '{ tmp=($6)/($5+0.0001) ; print tmp" "$0 }' wc_sec.tmp > ${data}/wps.txt # How to also round the new column?

rm *.tmp

exit 0

