#!/bin/bash -e

set -o pipefail

# Clean new text, extract new vocabulary and create acoustic, language model and punctuation training texts
# I assume this is automatically run after each speech is submitted by transcribers
# To run from the s5 dir

stage=0
clean_stage=0
expand_stage=0

. ./path.sh # the $root_* variable are defined here
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

# #date
# d=$(date +'%Y%m%d')

g2p=$(ls -t $root_g2p/*/g2p.mdl | head -n1)

# Output dirs for LM and AM texts
amdir=$root_am_transcripts
lmdir=$root_lm_transcripts
punctdir=$root_punctuation_transcripts
vocabdir=$root_new_vocab
mkdir -p $amdir $lmdir $punctdir $vocabdir


# NOTE! I have to design this with Judy. It would probably be best if this runs automatically
# every time a transcriber has read through an ASR transcript. The editors would then see
# the new vocabulary when they start editing the text. The input and output could be defined
# from the speechname, f.ex.
# NOTE! But what if the editors are in a hurry and start immediately, before the vocab list is ready?
# we will have to make it allowed to not provide a vocab file
if [ $# != 2 ]; then 
  echo "Usage: local/extract_new_vocab_and_text.sh [options] <input-file> <output-dir>"
  echo "e.g.: local/extract_new_vocab_and_text.sh xmldata/speechname.xml temp"
fi

infile=$(readlink -f $1); shift
speechname=$(basename $infile)
speechname="${speechname%.*}"
outdir=$1; shift
outdir=${outdir}/$speechname

for f in $infile $g2p; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ -d $outdir ]; then 
  echo "$outdir already exists" && exit 1
fi

intermediate=$outdir/intermediate
mkdir -p $outdir/{intermediate,log}

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $stage -le 1 ]; then

  echo "Extract text from xml file"
  # Extract text, remove XML tags and carriage return and add the uttID in front.
  tr "\n" " " < $infile \
    | sed -re 's:</mgr></ræðutexti></ræða> <ræðutexti><mgr>: :g' -e 's:(.*)?<ræðutexti>(.*)</ræðutexti>(.*):\2:' \
          -e 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
          -e `echo "s/\r//"` -e 's: *<[^<>]*?>: :g' \
          -e "s:^.*:$speechname &:" -e 's: +: :g' \
  > $intermediate/text_orig.txt || error 13 $LINENO ${error_array[13]};
  
  # utils/slurm.pl $outdir/log/extract_text.log python3 local/extract_text.py $datadir $intermediate/text_orig.txt
  # ret=$?
  # if [ $ret -ne 0 ]; then
  #   error 1 $LINENO "extract_text.py failed";
  # fi

  echo "Clean the text for all uses (AM, LM and for punctuation modelling)"
  local/clean_new_speech.sh --stage $clean_stage $intermediate/text_orig.txt $outdir/cleantext.txt $outdir/punct_text.txt $outdir/new_vocab.txt || error 1 "ERROR: clean_new_speech.sh failed";

  # Save the new punctuation training text
  sed -r "s:^$speechname ::" < $outdir/punct_text.txt > $punctdir/$speechname.txt
fi

if [ $stage -le 2 ]; then
  
  if [ -s $outdir/new_vocab.txt ]; then
    echo "Get the phonetic transcriptions of the new vocabulary"
    local/transcribe_g2p.sh $g2p $outdir/new_vocab.txt \
      > $vocabdir/$speechname.txt \
    || error 1 "ERROR: transcribe_g2p.sh failed"
  fi
  
  # NOTE! The new vocab has to be available in the text editor used at Althingi
  # I need to know where the confirmed words end up!
 
fi

if [ $stage -le 3 ]; then

  echo "Expand numbers and abbreviations"
  local/expand_small.sh --nj 1 $outdir/cleantext.txt ${outdir}/text_expanded \
    || error 1 "Expansion failed";
  # Sometimes the "og" in e.g. "hundrað og sextíu" is missing
  perl -pe 's/(hundr[au]ð) ([^ ]+tíu|tuttugu) (?!og)/$1 og $2 $3/g' \
       < ${outdir}/text_expanded > $tmp/tmp && mv $tmp/tmp ${outdir}/text_expanded
  
  # The ${outdir}/text_expanded utterances fit for use in the stage 2 punctuation training

  # NOTE! I need to design with Judy where to put these files
  echo "Make a language model training text from the expanded text"
  cut -d' ' -f2- $outdir/text_expanded \
    | sed -re 's:[.:?!]+ *$::g' -e 's:[.:?!]+ :\n:g' \
          -e 's:[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö \n]::g' \
          -e 's: +: :g' \
    > $lmdir/$speechname.txt || exit 1;

  # Extract the speaker IDs
  ID=$(egrep "<ræða .*? skst=" $infile | sed -re 's:.*?id="([^\"]+?)".*?skst="([^\"]+?)".*?:\1 \2:g' | cut -d' ' -f2)
  
  echo "Remove punctuations to make the text better fit for acoustic modelling. Add a spkID."
  sed -re 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ] : :g' -e 's: +: :g' -e "s:.*:${ID}-&:" \
      < ${outdir}/text_expanded > $amdir/$speechname.txt || exit 1;
  
fi

# NOTE! Fix uttIDs!

# # Extract the speaker IDs
# cat $datadir/*.xml | egrep "<ræða .*? skst=" | sed -re 's:.*?id="([^\"]+?)".*?skst="([^\"]+?)".*?:\1 \2:g' -e 's:r20:rad20:' -e 's/[:-]//g' | awk '{print $0, $2"-"$1}'> $train_data_dir/language_model/$d/uttname_spkid_uttid.txt


# Remove $outdir if all previous steps finished successfully
#rm -r $outdir

exit 0;
