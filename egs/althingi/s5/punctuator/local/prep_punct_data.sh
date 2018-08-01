#!/bin/bash -eu

set -o pipefail

# NOTE! Update the 2nd stage part
# NOTE! Update the raw text input

id=
ignore_commas=true
suffix=
$ignore_commas && suffix=_noCOMMA

. ./path.sh
. ./utils/parse_options.sh
. ./conf/path.conf

# These paths are defined in path.conf
prondict=$(ls -t $root_lexicon/prondict.*.txt | head -n1)
abbr_list=$(ls -t $root_text_norm_listdir/abbreviation_list.*.txt | head -n1)
scraped_text_dir=/data/althingi/text_corpora/ #$root_raw_text
all=$root_intermediate

if [ $# -ne 3 ]; then
  echo "This script cleans and preprocesses data for punctuation modelling."
  echo ""
  echo "Usage: $0 <path-to-intermediate-data> <output-data-dir-1st-stage> <output-data-dir-2nd-stage>" >&2
  echo "e.g.: $0 $data/postprocessing punctuation/data/first_stage punctuation/data/first_stage" >&2
  exit 1;
fi

cleaned=$1
out=$2
out_2nd_stage=$3
intermediate=$cleaned/intermediate
mkdir -p $intermediate $cleaned/log $out/log

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# Make a regex pattern of all abbreviations, upper and lower case.
cat $abbr_list <(sed -r 's:.*:\u&:' $abbr_list) | sort -u | tr "\n" "|" | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > $tmp/abbr_pattern.tmp || exit 1;

echo "Clean the scraped data"
n=0
for textin in $scraped_text_dir/t131.txt <(grep -v rad2016 $all/all_nov2016/text_orig_endanlegt.txt) $all/all_{okt2017,sept2017,mars18}/text_orig_endanlegt.txt ; do
  (
    n=$[$n+1]
    base=$(basename $(dirname $textin))
    base=${base}_$n
    utils/slurm.pl $cleaned/log/clean_$base.log \
		   local/clean_new_speech.sh \
		   $textin $tmp/abbr_pattern.tmp \
		   $prondict $cleaned/${base}.clean.txt \
		   $tmp/${base}_new_vocab.txt || exit 1;
    cat $cleaned/${base}.clean.txt >> ${cleaned}/punctuation_text.train.txt || exit 1;
  ) & 
done
  
echo "Clean the 2016 althingi data"
for textin in <(grep rad2016 $all/all_nov2016/text_orig_endanlegt.txt) ; do
  base=$(basename $(dirname $textin))
  utils/slurm.pl $cleaned/log/clean_${base}_test.log \
    local/clean_new_speech.sh \
	   $textin $tmp/abbr_pattern.tmp \
	   $prondict $cleaned/${base}_test.clean.txt \
	   $tmp/${base}_test_new_vocab.txt || exit 1;

  nlines_half=$(echo $((($(wc -l $cleaned/${base}_test.clean.txt | cut -d" " -f1)+1)/2)))
  head -n $nlines_half $cleaned/${base}_test.clean.txt > ${cleaned}/punctuation_text.dev.txt
  tail -n +$[$nlines_half+1] $cleaned/${base}_test.clean.txt > ${cleaned}/punctuation_text.test.txt
done
    
echo "Preprocess the data for training"
utils/slurm.pl --mem 8G ${out}/log/preprocessing_trainingdata_cs.log \
	       python punctuator/local/preprocessing_trainingdata_cs.py ${cleaned}/punctuation_text.train.txt ${out}/althingi.train.txt || exit 1;

python punctuator/local/preprocessing_trainingdata_cs.py \
       ${cleaned}/punctuation_text.dev.txt \
       ${out}/althingi.dev.txt || exit 1;

python punctuator/local/preprocessing_trainingdata_cs.py \
       ${cleaned}/punctuation_text.test.txt \
       ${out}/althingi.test.txt || exit 1;

echo "Prepare the pause annotated data"
punctuator/local/clean_AlthingiData_pause.sh \
  $all/all_sept2017/text_orig_endanlegt.txt \
  ${cleaned}/texts_pause_clean_for_punct_restoring.txt || exit 1;

echo "Preprocess the data"
utils/slurm.pl --mem 8G --time 0-04:00 ${out}/log/preprocessing_pause_data.log \
	       python punctuator/local/preprocessing_pause_data.py ${cleaned}/texts_pause_clean_for_punct_restoring.txt ${out_2nd_stage}/althingi.train_Sept2017_pause_simpleExp.txt || exit 1;

echo "Make the Sept 2017 data pause annotated"
utils/slurm.pl ${out_2nd_stage}/log/make_pause_annotated.log punctuator/local/make_pause_annotated.sh || exit 1;

# If I want to ignore commas in the training:
if [ ignore_commas = true ]; then
  out_noComma=${out}$suffix
  mkdir -p $out_noComma/log
  for f in althingi.{train,dev,test}.txt; do
    sed -re 's: ,COMMA::g' $out/$f > $out_noComma/$f
  done
  out=$out_noComma
  if [ -e $out_2nd_stage/althingi.train.txt ]; do
    out_2nd_stage_noComma=${out}/second_stage_${id}$suffix
    mkdir -p $out_2nd_stage_noComma/log
    for f in althingi.{train,dev,test}.txt; do
      sed -re 's: ,COMMA::g' ${out_2nd_stage}/$f > $out_2nd_stage_noComma/$f
    done
    out_2nd_stage=$out_2nd_stage_noComma
  fi
fi

echo "Preprocessing done."
    
exit 0;
