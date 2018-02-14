#!/bin/bash

set -e -o pipefail -u

# Get unigram counts for the LM train and dev files
# f.ex. local/rnnlm/get_unigram_counts.sh data/rnnlm

data_dir=$1

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

. path.sh

for file in train dev; do
    nohup tr ' ' '\n' < $data_dir/${file}.txt \
    | egrep -v '^\s*$' > $tmp/words \
    && sort --parallel=8 $tmp/words \
            | uniq -c > $tmp/words.sorted \
    && sort -k1 -n --parallel=8 \
        $tmp/words.sorted | awk '{print $2,$1}' > ${data_dir}/${file}.counts
done

exit 0;
