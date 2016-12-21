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
