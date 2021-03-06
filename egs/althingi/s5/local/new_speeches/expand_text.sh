#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Expand abbreviations and numbers in the texts to use for training and testing.
# In this script the expansion fst is not adapted to the input text

set -o pipefail

stage=-1
order=4

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh # Defines also $root_* and $data,$exp
. utils/parse_options.sh
. local/utils.sh

text_norm_lex=$root_thraxgrammar_lex
base_norm_data=$root_expansionLM_cs_data
base_norm_model=$root_base_text_norm_model

if [ $# != 2 ]; then
  echo "Text normalize a single speech, i.e. expand numbers and abbreviations"
  echo "using the basic expansion language model, based on the Leipzig corpora"
  echo "and a small Althingi data set."
  echo ""
  echo "Usage: local/expand.sh [options] <input-text-file> <output-text-file>"
  echo "e.g.: local/expand.sh data/cleantext.txt data/text_expanded"
fi

infile=$1
outfile=$2
dir=$(dirname $infile);

for f in $infile ${base_norm_data}/numbertexts_althingi100.txt.gz \
  ${text_norm_lex}/abbr_lexicon.txt $base_norm_model/{baseLM_words.txt,base_expand_to_words.fst,base_expansionLM_${order}g.fst}; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done  


if [ $stage -le 2 ]; then
  echo "Make a list over all the words in numbertexts if necessary"
  if [ ! -f ${base_norm_data}/wordlist_numbertexts_althingi100.txt ]; then
    gzip -cd ${base_norm_data}/numbertexts_althingi100.txt.gz | cut -d" " -f2- | tr " " "\n" | grep -v "^\s*$" | sort -u > ${base_norm_data}/wordlist_numbertexts_althingi100.txt || exit 1;
  elif [ ${base_norm_data}/wordlist_numbertexts_althingi100.txt -ot ${base_norm_data}/numbertexts_althingi100.txt.gz ]; then
    gzip -cd ${base_norm_data}/numbertexts_althingi100.txt.gz | cut -d" " -f2- | tr " " "\n" | grep -v "^\s*$" | sort -u > ${base_norm_data}/wordlist_numbertexts_althingi100.txt || exit 1;
  fi
fi

if [ $stage -le 3 ]; then
  echo "Extract words that are only in the althingi texts, excluding unexpanded abbrs, numbers and punctuations."
  echo "Map words which are not seen in context in numbertexts to <word>."
  cut -d" " -f2- ${dir}/cleantext.txt | tr " " "\n" | grep -v "^\s*$" | sort -u > ${dir}/words_cleantext.tmp || exit 1;
  # Extract words that are only in the althingi texts, excluding unexpanded abbrs, numbers and punctuations
  comm -23 <(comm -23 ${dir}/words_cleantext.tmp ${base_norm_data}/wordlist_numbertexts_althingi100.txt | egrep -v "[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]") <(cut -f1 ${text_norm_lex}/abbr_lexicon.txt | sort -u) > ${dir}/words_speech_only.tmp
  
  if [ -s ${dir}/words_speech_only.tmp ]; then
    # Map words which are not seen in context in numbertexts to <word>
    source venv3/bin/activate
    #pip install nltk
    $train_cmd ${dir}/log/save-OOVwords.log python3 local/save_OOVwords.py ${dir}/cleantext.txt ${dir}/words_speech_only.tmp ${dir}/cleantext_afterWordMapping.txt ${dir}/mappedWords.txt
    deactivate
  else
    cp ${dir}/cleantext.txt ${dir}/cleantext_afterWordMapping.txt
  fi
  # I get problems if encounter more than one space between words after the thrax step. Temporary fix is this:
  sed -i -re 's:([0-9]) (%|‰):\1\2:g' -e 's:< ([a-z]+) >:<\1>:g' -e 's: +: :g' ${dir}/cleantext_afterWordMapping.txt
fi

if [ $stage -le 4 ]; then
  echo "Expand"
  $decode_cmd ${dir}/log/expand-numbers.log expand-numbers --word-symbol-table=$base_norm_model/baseLM_words.txt ark,t:$dir/cleantext_afterWordMapping.txt $base_norm_model/base_expand_to_words.fst $base_norm_model/base_expansionLM_${order}g.fst ark,t:$dir/text_expanded_${order}g.txt

  echo "Check if all the speeches were expanded"
  if egrep -q "rad[0-9T]+ *$" ${dir}/text_expanded_${order}g.txt; then
    echo "The speech was not expanded"
    exit 1;
  else
    echo "The speech is expanded :)"
  fi
fi

if [ $stage -le 5 ]; then

  echo "Insert words back"
  if [ -s ${dir}/mappedWords.txt ]; then
    local/re-insert-oov.sh ${dir}/text_expanded_${order}g.txt ${dir}/mappedWords.txt || exit 1;
  else
    cp ${dir}/text_expanded_${order}g.txt ${dir}/text_expanded_${order}g.wOOV.txt
  fi  
fi

if [ $stage -le 6 ]; then

  if [ -e ${outfile} ] ; then
    # we don't want to overwrite old stuff, ask the user to delete it.
    echo "$0: ${outfile} already exists: "
    echo "Are you sure you want to proceed?"
    echo "It will overwrite the file"
    echo ""
    echo "  If so, please delete and then rerun this part"
    exit 1;
  else
    cp ${dir}/text_expanded_${order}g.wOOV.txt ${outfile}
  fi
fi

# Change back the slurm config file 
#sed -r -i 's:(command sbatch .*?) --nodelist=terra:\1:' conf/slurm.conf

exit 0;
