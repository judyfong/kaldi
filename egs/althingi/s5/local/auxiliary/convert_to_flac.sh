#!/bin/bash -eu

set -o pipefail

. ./path.sh

nj=12
datadir=data/local/corpus
# mkdir -p audio_split$nj/
# split -n$nj -d <(ls ${datadir}/audio) audio_split$nj/audio_

for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    mkdir -p audio_split$nj/flac_$n
done

samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing

for name in $(cat audio_split$nj/audio_JOB); do base=$(echo $name | cut -d"." -f1); sox -v0.98 -tmp3 ${datadir}/audio/$name -c1 -r$samplerate -G -tflac audio_split$nj/flac_JOB/${base}.flac; done


# # convert 100 shortest files to wav for a tf-rnn test
# ls -l data/local/corpus/audio/* | sed -r 's/[[:space:]]+/ /g' | sort -k5,5 -n | head -n100 | cut -d" " -f9 | cut -d"/" -f5 | sort > 100_shortest_audio_files
# for name in $(cat ~/kaldi/egs/althingi/s5/100_shortest_audio_files); do base=$(echo $name | cut -d"." -f1); sox ~/kaldi/egs/althingi/s5/data/local/corpus/audio/$name -c1 -G ${base}.wav; done
# # Make separate text files for the respective texts.
# for name in $(cat ~/kaldi/egs/althingi/s5/100_shortest_audio_files); do base=$(echo $name | cut -d"." -f1); grep $base ~/kaldi/egs/althingi/s5/data/all/text | cut -d" " -f2- > $base.txt; done
