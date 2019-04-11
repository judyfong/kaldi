#!/bin/bash -e

. ./path.sh
. ./local/utils.sh
. ./local/array.sh

asrlm_modeldir=/jarnsmidur/asr-lm_models
trans_out=$root_transcription_dir
lirfa_audio=$root_lirfa_audio

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# Check if a new decoding graph was created at least an hour ago
# NOTE! I find this a bit uncomfortable. Is it possible to rather get a message when local/new_speeches/update_LM_and_graph.sh has finished?
new_HCLG=$(find $asrlm_modeldir/acoustic_model/chain/5.4/tdnn_*/*/graph_3gsmall/HCLG.fst -cmin +60 -ctime -2 | tail -n1)
if [ -z "$new_HCLG" ]; then
  echo "No new decoding graph found, exit the script.";
  exit 0;
fi

# Newest AM dir
am_modeldir=$(ls -td $asrlm_modeldir/acoustic_model/*/*/*/* | head -n1)

# Copy the new LMs and decoding graph from the LM server to the decoding server

# The pathnames are not the same in the beginning, between the two servers, cut away what is different
n=$(echo $asrlm_modeldir | egrep -o '/' | wc -l)
am_date=$(basename $am_modeldir)
middle_ampath=$(dirname $am_modeldir | cut -d'/' -f$[$n+2]-)

# Newest language models
lm_modeldir=$(cat $am_modeldir/lminfo)
lm_date=$(basename $lm_modeldir)
middle_lmpath=language_model

decode_amdir=$root_modeldir/$middle_ampath
decode_lmdir=$root_lm_modeldir

if [ -d $decode_lmdir/$lm_date ]; then
  echo "Language model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new language models"
  mkdir -p $decode_lmdir
  cp -r $asrlm_modeldir/$middle_lmpath/$lm_date $decode_lmdir
fi

if [ -d $decode_amdir/$am_date ]; then
  echo "Acoustic model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new acoustic model directory"
  mkdir -p $decode_amdir
  cp -r $asrlm_modeldir/$middle_ampath/$am_date $decode_amdir
  ln -sf $decode_lmdir/$lm_date $decode_amdir/$am_date/lmdir
fi

echo "Update latest"
d=$(basename $(ls -td $root_bundle/20* | head -n1))
if [ $d = $am_date ]; then
  echo "The latest bundle is already from $am_date"
  echo "I won't overwrite it"
else
  local/update_latest.sh || error 1 "ERROR: update_latest.sh failed"
fi

echo "Test decoding three speeches using the new ASR version"
fail=0
empty=0
for nb in 1 2 3; do 
  audio=$(ls -t $lirfa_audio | head -n3 | tail -n$nb)
  speechname=$(basename "$audio")
  speechname="${speechname%.*}"
  reftext=$trans_out/$speechname/$speechname.txt
  if [ -s $audio -a -s $reftext ]; then
    testout=$tmp/speechname
    mkdir -p $testout

    local/recognize/recognize.sh --trim 0 --rnnlm false $audio $testout &> $testout/$speechname.log

    echo "Compare it with an earlier transcription"
    compute-wer --text --mode=present ark:$reftext ark,p:$testout/$speechname.txt >& $testout/edit_dist$nb

    WEDcomp=$(grep WER $testout/edit_dist$nb | utils/best_wer.sh | cut -d' ' -f2)
    WEDcomp_int=${WEDcomp%.*}
    if [ $WEDcomp_int < 90 ]; then
      echo "FAILED: Bad comparison between new and old transcription of $speechname."
      fail=$[$fail+1]
    fi
  else
    echo "$audio is empty or $reftext is non-existent"
    empty=$[$empty+1]
  fi
done

if [ $fail -eq 3 ]; then
  echo "FAILED: Bad comparison for all speeches"
  echo "Maybe something is wrong with the new ASR version"
  echo "Revert to using the old one"
  mv $root_bundle/.oldlatest $root_bundle/latest
  exit 1;
elif [ $empty -eq 3 ]; then
  echo "Non-existent audio or reference text for all speeches"
  echo "Something is wrong"
  exit 1;
fi

exit 0;
