#!/bin/bash -eu

#Analyze the decoding results.
#Extract csid info (number of correct, substituted, inserted and deleted words in an utterance):

dir=$1
grep "#csid" $dir/per_utt | awk '{$7=$3/($3+$4+$5+$6)}1' | sort -n -k7 > $dir/csid_plusCorrectnessRatio.txt
