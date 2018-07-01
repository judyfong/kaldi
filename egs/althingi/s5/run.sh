#!/bin/bash -eu

# The script contains the steps taken to train an Icelandic LVCSR
# built for the Icelandic parliament using text and audio data
# from the parliament. It is assumed that the text data provided
# consists of two sets of files, the intermediate text
# and the final text. The text needs to be normalized and
# and audio and text has to be aligned and segmented before
# training.
#
# If you have already segmented data, you just need to create the kaldi files
# (done in the first part of prep_althingi_data.sh) and can then go to
# stage 5.
#
# This script is thought as a template. Changes might have to be made.
#
# The file structure I use can be seen in conf/path.conf and the
# projects root dir is in s5/path.sh.
# When a bunch of files is created simultaneously, e.g. by training,
# they end up in a common directory marked by the creation date
# Files which are updated one by one like lists, get the date in its name,
# e.g. acronyms_as_words.20180601.txt
# 
# Copyright 2017 Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# NOTE! If obtaining the audio and text files from althingi.is run
# extract_new_files.sh and skip stage -1 instead

set -o pipefail

nj=20
decode_nj=32 
stage=-100
corpus_zip=/data/althingi/tungutaekni_145.tar.gz # Data from Althingi

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh
. ./conf/path.conf # Here $data, $exp and $mfcc are defined, as well as all $root_*
# path.conf defines the file structure used and where the data and output from experiments is put

#date
d=$(date +'%Y%m%d')

# Raw data
corpusdir=$root_corpus/corpus_$d # Where to store the corpus, default: /data/althingi
Leipzig_corpus=$root_leipzig_corpus/isl_sentences_10M.txt

# Intermediate data dir
outdir=$root_intermediate/all_$d

# Dir with a subdir, base, containing expansionLM models,
# dirs, named after the date, containing Thrax grammar FSTs.
norm_modeldir=$root_text_norm_modeldir

# Text data used for the expansion language model
base_expansionLM_datadir=$root_expansionLM_cs_data

# Newest pronunciation dictionary
prondict=$(ls -t $root_lexicon/prondict.*.txt | head -n1)

# An in-domain model, used for segmentation
tri2=$root_gmm/tri2_cleaned 

# Directories for punctuation, language and acoustic model training data, respectively
am_datadir=$root_am_datadir/$d
punct_datadir=$root_punctuation_datadir/$d
lm_datadir=$root_lm_datadir/$d
rnnlm_datadir=$root_lm_datadir/rnn/$d

# Directories for punctuation, language and acoustic models, respectively
punct_modeldir=$root_punctuation_modeldir/$d
lm_modeldir=$root_lm_modeldir/$d
am_modeldir=$root_am_modeldir/$d

# Newest lang directory, output of local/prep_lang.sh
langdir=$lm_modeldir/lang # I put it in the lm modeldir since it follows them
localdict=$root_localdict # Byproduct of local/prep_lang.sh

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $stage -le -1 ]; then
  echo "Extracting corpus"
  [ -f $corpus_zip ] || error 1 "$corpus_zip not a file"
  mkdir -p ${corpusdir}
  tar -zxvf $corpus_zip --directory ${corpusdir}/
  c=$(ls $corpusdir)
  [ $(ls ${corpusdir} | wc -l) = 1 ] && mv ${corpusdir}/$c/* ${corpusdir}/ && rm -r ${corpusdir}/$c
  # validate
  if ! [[ -d ${corpusdir}/audio && \
	    -d ${corpusdir}/text_bb && \
	    -d ${corpusdir}/text_endanlegt && \
	    -f ${corpusdir}/metadata.csv ]]; then
    error 1 "Corpus doesn not have the correct structure"
  fi
  encoding=$(file -i ${corpusdir}/metadata.csv | cut -d" " -f3)
  if [[ "$encoding"=="charset=iso-8859-1" ]]; then
    iconv -f ISO-8859-1 -t UTF-8 ${corpusdir}/metadata.csv > $tmp/tmp && mv $tmp/tmp ${corpusdir}/metadata.csv
  fi

fi

if [ $stage -le 1 ]; then

  echo "Compile Thrax grammar into FSTs, used both for text normalization and de-normalization"
  mkdir -p $norm_modeldir/$d
  local/compile_grammar.sh local/thraxgrammar $norm_modeldir/$d

fi

if [ $stage -le 2 ]; then

  # NOTE! I need to improve the correcting of casing 
  echo "Create a Kaldi dir for the data, do initial text normalization,"
  echo "fix spelling errors and casing in the text"
  mkdir -p $outdir/log
  local/prep_althingi_data.sh ${corpusdir} ${outdir}
  cp ${outdir}/text ${outdir}/text_bb_uttID.txt

  # The text as it is now, is fit for punctuation model preprocessing
  mkdir -p $punct_datadir/first_stage
  cut -d' ' -f2- ${outdir}/text_PunctuationTraining.txt > $punct_datadir/first_stage/althingi_text_before_preprocess.txt
fi

if [ $stage -le 3 ]; then

  echo "Create a base text set to use for the expansion language model"
  echo "NOTE! This can only be run in you have access to the Leipzig corpus for Icelandic"
  echo "And the manually fixed 100 hour Althingi set"
  # This part is in a strange loop because the expansion of many parliamentary abbreviations
  # was often incorrect because they didn't exist expanded in the Leipzig corpora so I re-did
  # the expansion text set by going through the initial expansion and fixing the ones that
  # usually were incorrect.
  if [ ! -f $base_expansionLM_datadir/numbertexts_althingi100.txt.gz -o ! -f $base_expansionLM_datadir/wordlist_numbertexts_althingi100.txt ]; then
    for f in $Leipzig_corpus $root_manually_fixed/althingi100_textCS; do
      [ ! -f $f ] || echo "expected $f to exist" && exit 1;
    done
    mkdir -p $base_expansionLM_datadir/log
    utils/slurm.pl $base_expansionLM_datadir/log/prep_base_expansion_training_subset.log local/prep_expansionLM_training_subset_Leipzig.sh $Leipzig_corpus $root_manually_fixed/althingi100_textCS $prondict
  fi
  
fi

if [ $stage -le 4 ]; then
  
  echo "Expand numbers and abbreviations"
  ./local/expand_big.sh ${outdir}/text_bb_uttID.txt ${outdir}/text || error 1 "Expansion failed"

  echo "Validate the data dir"
  utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir}
  
  echo "Make a language model training text from the expanded text"
  # NOTE! I remove 2016 data since that I have in my ASR test sets
  egrep -v "rad2016" $outdir/text | cut -d' ' -f2- | sed -re 's:[.:?!]+ :\n:g' -e 's:[.:?!]+ *$::g' -e 's:[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ]::g' -e 's: +: :g' > $lm_datadir/text_$(basename $outdir).txt || exit 1;

  echo "Remove punctuations to make the text better fit for acoustic modelling"
  cp ${outdir}/text ${outdir}/text_general_purpose
  sed -i -re 's:[.:?!]+ : :g' -e 's:[.:?!]+ *$::g' -e 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ]: :g' -e 's: +: :g' ${outdir}/text || exit 1;
  
  echo "Validate the data dir"
  utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir}
fi

# if [ $stage -le 3 ]; then
  
#   echo "Make the texts case sensitive (althingi and LM training text)"
#   local/case_sensitive.sh $prondict $outdir
  
#   # Make the CS text be the main text
#   mv ${outdir}/text ${outdir}/LCtext
#   mv ${outdir}/text_CaseSens.txt ${outdir}/text
# fi

if [ $stage -le 3 ]; then
  
  echo "Lang preparation"

  # Make lang dir
  [ -d $localdict ] && rm -r $localdict
  mkdir -p $localdict $lm_modeldir/lang
  local/prep_lang.sh \
    $prondict        \
    $localdict   \
    $lm_modeldir/lang
fi

if [ $stage -le 4 ]; then
  
  # I can't train without segmenting the audio and text first.
  # I use a small tri2 model, trained on ~60 hrs of data to
  # transcribe the audio so that I can align the new data	
  echo "Segment the data using and in-domain recognizer"
  nohup local/run_segmentation.sh ${outdir} $langdir $tri2 ${outdir}_reseg &>${outdir}/log/segmentation.log

  # Should be unnecessary
  # echo "Analyze the segments and filter based on a words/sec ratio"
  # local/words-per-second.sh data/all_reseg
  # #local/hist/wps_perSegment_hist.py wps.txt
  
  # Filter away segments with extreme word-per-second values
  local/filter_segments.sh ${outdir}_reseg ${outdir}_reseg_filtered
fi

if [ $stage -le 5 ]; then
  
  echo "Extracting features"
  steps/make_mfcc.sh \
    --nj $nj       \
    --mfcc-config conf/mfcc.conf \
    --cmd "$train_cmd"           \
    ${outdir}_reseg_filtered $exp/make_mfcc $mfcc

  echo "Computing cmvn stats"
  steps/compute_cmvn_stats.sh \
    ${outdir}_reseg_filtered $exp/make_mfcc $mfcc

fi
    
if [ $stage -le 6 ]; then

  # NOTE! I want to do this differently. And put an upper limit on the quantity of data from one speaker
  
  echo "Splitting into a train, dev and eval set"

  # Use the data from the year 2016 as my eval data
  grep "rad2016" ${outdir}_reseg_filtered/utt2spk | cut -d" " -f1 > $tmp/test_uttlist
  grep -v "rad2016" ${outdir}_reseg_filtered/utt2spk | cut -d" " -f1 > $tmp/train_uttlist
  
  subset_data_dir.sh --utt-list $tmp/train_uttlist ${outdir}_reseg_filtered $data/train
  subset_data_dir.sh --utt-list $tmp/test_uttlist ${outdir}_reseg_filtered $data/dev_eval

  # # NOTE! Now I have multiple sources of training data. I need to combine them all
  # utils/combine_data.sh data/train_okt2017 data/train data/all_okt2017_reseg_filtered &
  
  # Randomly split the dev_eval set. NOTE! Not the best if I need to remake the same
  # sets.
  shuf <(cut -d" " -f1 $data/dev_eval/utt2spk) > $tmp/utt2spk_shuffled.tmp
  m=$(echo $(($(wc -l $tmp/utt2spk_shuffled.tmp | cut -d" " -f1)/2)))
  head -n $m $tmp/utt2spk_shuffled.tmp > $tmp/dev_uttlist
  tail -n +$(( m + 1 )) $tmp/utt2spk_shuffled.tmp > $tmp/eval_uttlist
  utils/subset_data_dir.sh --utt-list $tmp/dev_uttlist $data/dev_eval $data/dev
  utils/subset_data_dir.sh --utt-list $tmp/eval_uttlist $data/dev_eval $data/eval

  # In case I need to re-make these sets
  cp -t $am_datadir $tmp/train_uttlist $tmp/dev_uttlist $tmp/eval_uttlist

  # Save a symbolic link in my data structure. But for me $data is on another drive
  # where we run stuff so I need to have the training data there
  for dir in train dev eval; do
    ln -s $data/$dir $am_datadir/$dir
  done
    
  # NOTE! I removed later utterances that were both in train and dev_eval, from train if
  # the same speaker said both
  
fi

if [ $stage -le 7 ]; then
  
  # Expanded LM training text and split on EOS:
  #/home/staff/inga/data/althingi/pronDict_LM/LMtext_w_t131_split_on_EOS_expanded.txt
  # A newer one: /data/althingi/text_corpus/LMtext_2004-2018.txt
    
  echo "Preparing a pruned trigram language model"
  mkdir -p $lm_modeldir/log
  utils/slurm.pl $lm_modeldir/log/make_LM.log \
    local/make_LM.sh \
      --order 3 --small true --carpa false \
      $lm_datadir/text_$(basename $outdir).txt \
      $langdir $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating a pruned trigram language model"
		 
  echo "Preparing an unpruned trigram language model"
  mkdir -p $lm_modeldir/log
  utils/slurm.pl $lm_modeldir/log/make_LM.log \
    local/make_LM.sh \
      --order 3 --small false --carpa true \
      $lm_datadir/text_$(basename $outdir).txt \
      $langdir $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating an unpruned trigram language model"

  echo "Preparing an unpruned 5g LM"
  mkdir -p $lm_modeldir/log
  utils/slurm.pl $lm_modeldir/log/make_LM.log \
    local/make_LM.sh \
      --order 5 --small false --carpa true \
      $lm_datadir/text_$(basename $outdir).txt \
      $langdir $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating an unpruned 5-gram language model"
  
  echo "Make a zerogram language model to be able to check the effect of"
  echo "the language model in the ASR results"
  mkdir -p $lm_modeldir/log
  utils/slurm.pl $lm_modeldir/log/make_LM.log \
    local/make_LM.sh \
      --order 1 --small false --carpa false \
      $lm_datadir/text_$(basename $outdir).txt \
      $langdir $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating a zerogram language model"
  mv $lm_modeldir/lang_1g $lm_modeldir/lang_zg
  
fi

if [ $stage -le 8 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"

    # utils/subset_data_dir.sh data/train 40000 data/train_40k
    # utils/subset_data_dir.sh --shortest data/train_40k 5000 data/train_5kshort
    # utils/subset_data_dir.sh data/train 10000 data/train_10k
    utils/subset_data_dir.sh $data/train 20000 $data/train_20k

    # # Make one for the dev/eval sets so that I can get a quick estimate
    # # for the first training steps. Try to get 30 utts per speaker
    # # (~30% of the dev/eval set)
    # utils/subset_data_dir.sh --per-spk data/dev 30 data/dev_30
    # utils/subset_data_dir.sh --per-spk data/eval 30 data/eval_30
fi

if [ $stage -le 9 ]; then
    # NOTE! Should I rather start with SI alignment and then training LDA+MLLT?

    echo "Align and train on the segmented data"
    # Now there is no need to start from mono training since we already got a good recognizer.
    steps/align_fmllr.sh --nj 100 --cmd "$train_cmd --time 1-00" \
        $data/train $langdir $exp/tri4 $exp/tri4_ali || exit 1;

    echo "Train SAT"
    steps/train_sat.sh  \
	--cmd "$train_cmd" \
	7500 150000 $data/train \
	$langdir $exp/tri4_ali $exp/tri5 || exit 1;

    utils/mkgraph.sh $lm_modeldir/lang_3gsmall $exp/tri5 $exp/tri5/graph_3gsmall

    decode_num_threads=4
    for dset in dev eval; do
        (
            steps/decode_fmllr.sh \
                --nj $decode_nj --num-threads $decode_num_threads \
                --cmd "$decode_cmd" \
                $exp/tri5/graph_3gsmall $data/${dset} $exp/tri5/decode_${dset}_3gsmall
            steps/lmrescore_const_arpa.sh \
                --cmd "$decode_cmd" $lm_modeldir/lang_{3gsmall,3g} \
                $data/${dset} $exp/tri5/decode_${dset}_{3gsmall,3g}
            steps/lmrescore_const_arpa.sh \
                --cmd "$decode_cmd" $lm_modeldir/lang_{3gsmall,5g} \
                $data/${dset} $exp/tri5/decode_${dset}_{3gsmall,5g}
        ) &
    done

# if [ $stage -le 10 ]; then
#     echo "Clean and resegment the training data"
#     local/run_cleanup_segmentation.sh
# fi

# NNET Now by default running on un-cleaned data
# Input data dirs need to be changed
if [ $stage -le 11 ]; then

    echo "Run the swbd chain tdnn_lstm recipe with sp"
    local/chain/run_tdnn_lstm.sh >>tdnn_lstm.log 2>&1 &

    echo "Run the swbd chain tdnn recipe with sp"
    local/chain/run_tdnn.sh data/train data >>tdnn.log 2>&1 &
fi

# Here I need to create the bundles

if [ $stage -le 12 ]; then
  # Train and rescore with an RNN LM
  local/rnnlm/run_tdnn_lstm.sh --run-lat-rescore true >>rnnlm_tdnn_lstm.log 2>&1 &
fi

# Here I can have exemples of how to recognize new speeches

