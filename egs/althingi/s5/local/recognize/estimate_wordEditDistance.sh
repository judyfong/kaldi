#!/bin/bash

# Calculate the edit distance between the ASR output and the manually transcribed text.
# I only compair the two texts, no scoring for different LM weights or word insertion penalty.

# Config
ignore_punctuations=false
suffix=

echo "$0 $@"  # Print the command line for logging
. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

if [ $# -ne 3 ]; then
    echo "Usage: $0 [options] <textfile1> <textfile2> <output-dir>"
    echo "e.g.:  local/recognize/estimate_wordEditDistance.sh \\"
    echo "  recognize/notendaprof2/Lestur/rad20180219T150803.xml \\"
    echo "  recognize/notendaprof2/ASR/rad20180219T150803.txt recognize/notendaprof2/edit_dist/rad20180219T150803_A_B"
    exit 1;
fi

# If one of the texts is and ASR transcription and one is either a manual transcription
# or an edited ASR text, then text2 should be the unedited ASR transcription
textfile1=$1
textfile2=$2
dir=$3
mkdir -p $dir

base=$(basename "$textfile1")
extension1="${text1##*.}"
base="${base%.*}"

# If the text files are xml files I first need to extract the text
n=0
for file in $textfile1 $textfile2; do
    n=$[$n+1]
    # check if the extension is xml 
    if [ "${file##*.}" = 'xml' ] ; then
        tr "\n" " " < $file | sed -re 's:</mgr></ræðutexti></ræða> <ræðutexti><mgr>: :g' -e 's:(.*)?<ræðutexti>(.*)</ræðutexti>(.*):\2:' \
	    -e 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
	    -e 's:<[^<>]*?>: :g' \
	    -e 's:(.*):1 \1:' -e 's:[[:space:]]+: :g' \
        > $dir/text$n.tmp
    else
	sed -r 's:(.*):1 \1:' < $file > $dir/text$n.tmp
    fi
done

# Remove punctuations if I want a score on just the speech transcription
if [ $ignore_punctuations = true ]; then
    suffix=_noPuncts
    for f in $dir/text1.tmp $dir/text2.tmp; do
        sed -i -re 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9 ]//g' $f
    done
fi

# Get the word count
file1path=$(dirname "$textfile1")
dir1="${file1path##*/}"
file2path=$(dirname "$textfile2")
dir2="${file2path##*/}"
if [ $dir1 = "Lestur" -a $dir2 = "notendaprof2" ]; then
    wc -w $dir/text1.tmp > $dir/wc_A
    wc -w $dir/text2.tmp > $dir/wc_B
elif [ $dir1 = "ASR_Edit_Text_D" -a $dir2 = "notendaprof2" ]; then
    wc -w $dir/text1.tmp > $dir/wc_D
    wc -w $dir/text2.tmp > $dir/wc_B
elif [ $dir1 = "Vefur" -a $dir2 = "Lestur" ]; then
    wc -w $dir/text1.tmp > $dir/wc_C
    wc -w $dir/text2.tmp > $dir/wc_A
else
    wc -w $dir/text1.tmp > $dir/wc_C
    wc -w $dir/text2.tmp > $dir/wc_D
fi

# Align the two texts
align-text --special-symbol="'***'" ark:$dir/text1.tmp ark:$dir/text2.tmp ark,t:$dir/${base}_aligned$suffix.txt &>/dev/null

# Remove the text spoken by the speaker of the house
i=2
refword=$(cut -d" " -f$i $dir/${base}_aligned$suffix.txt)
while [ "$refword" = "'***'" ]; do
    i=$[$i+3]
    refword=$(cut -d" " -f$i $dir/${base}_aligned$suffix.txt)
done
idx1=$[($i-2)/3+2]
cut -d" " -f1,$idx1- $dir/text2.tmp > $dir/${base}_trimmed.tmp

j=$[$(wc -w $dir/${base}_aligned$suffix.txt | cut -d" " -f1)-1]
refword=$(cut -d" " -f$j $dir/${base}_aligned$suffix.txt)
while [ "$refword" = "'***'" ]; do
    j=$[$j-3]
    refword=$(cut -d" " -f$j $dir/${base}_aligned$suffix.txt)
done
idx2=$[($j-2)/3+2+1-$idx1]
cut -d" " -f1-$idx2 $dir/${base}_trimmed.tmp > $dir/${base}_trimmed$suffix.txt
rm $dir/${base}_trimmed.tmp

# Get a percentage value over the edit distance
cat $dir/${base}_trimmed$suffix.txt | \
    compute-wer --text --mode=present \
    ark:$dir/text1.tmp ark,p:- >& $dir/dist_$base$suffix || exit 1;

# Get a view of the alignment between the texts, plus values of
# correct words, substituions, insertions and deletions
cat $dir/${base}_trimmed$suffix.txt | \
    align-text --special-symbol="'***'" ark:$dir/text1.tmp ark:- ark,t:- |  \
    utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" > $dir/per_utt_$base$suffix || exit 1;

# Get statistics over correct words, substituions, insertions and deletions.
# F.ex. how often "virðulegi" is switched out for "virðulegur" and so on. 
cat $dir/per_utt_$base$suffix | \
    utils/scoring/wer_ops_details.pl --special-symbol "'***'" | \
    sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 > $dir/ops_$base$suffix || exit 1;

#rm $dir/text{1,2}.tmp
