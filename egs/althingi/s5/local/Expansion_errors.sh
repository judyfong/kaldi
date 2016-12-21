#!/bin/bash -eu

set -o pipefail

# Just a trash file to store a bunch of commands I used when checkeing expansion error rates. In case I need them again. More info in the work log

outdir=data/all

LC_ALL=C sort ${outdir}/text_exp2_bb.txt | tail -n18 > ${outdir}/tail18_text_unexpanded.txt
perl -pe 's/<bjalla>//g' ${outdir}/tail18_text_unexpanded.txt | tr -s " " > tmp && mv tmp ${outdir}/tail18_text_unexpanded.txt
IFS=$'\n'
rm data/all/tail18_text_bb_SpellingFixed.txt
for speech in $(cat ${outdir}/tail18_text_unexpanded.txt); do
    uttID=$(echo $speech | cut -d" " -f1)
    echo $speech | cut -d" " -f2- | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | grep -v "^$" | sort -u > vocab_speech.tmp
    comm -23 <(cat vocab_speech.tmp) <(cat  ${outdir}/words_text_endanlegt.txt) > vocab_speech_only.tmp
    grep $uttID ${outdir}/text_exp2_endanlegt.txt > text_endanlegt_speech.tmp
    cut -d" " -f2- text_endanlegt_speech.tmp | perl -pe 's/\.|,|[0-9]|%|°c|ºc//g' | tr " " "\n" | grep -v "^$" | sort -u > vocab_text_endanlegt_speech.tmp
    python3 local/MinEditDist.py "$speech" ${outdir}/tail18_text_bb_SpellingFixed.txt vocab_speech_only.tmp vocab_text_endanlegt_speech.tmp
done
rm *.tmp

cat data/all/tail18_text_bb_SpellingFixed.txt | utils/sym2int.pl --map-oov "<unk>" -f 2- text_norm/text/words30.txt | utils/int2sym.pl -f 2- text_norm/text/words30.txt > data/all/tail18_text_bb_SpellingFixed_noOOV.txt

nj=18
mkdir -p ${outdir}/split$nj/
IFS=$' \t\n'
split_text=$(for j in `seq 1 $nj`; do printf "${outdir}/split%s/tail18_text_bb_SpellingFixed_noOOV.%s.txt " $nj $j; done)
utils/split_scp.pl ${outdir}/tail18_text_bb_SpellingFixed_noOOV.txt $split_text

for n in 2 3 5; do
    utils/slurm.pl JOB=1:$nj ${outdir}/log/tail18_expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/text/words30.txt ark,t:${outdir}/split${nj}/tail18_text_bb_SpellingFixed_noOOV.JOB.txt text_norm/expand_to_words30.fst text_norm/text/numbertext_${n}g.fst ark,t:${outdir}/split${nj}/tail18_text_expanded_${n}g.JOB.txt &

    cat ${outdir}/split${nj}/tail18_text_expanded_${n}g.*.txt > ${outdir}/tail18_text_expanded_${n}g.txt
    LC_ALL=C sort ${outdir}/tail18_text_expanded_${n}g.txt > tmp && mv tmp ${outdir}/tail18_text_expanded_${n}g.txt
done

#####

cut -f2 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_lexicon.txt | cut -d" " -f1 > tmp
cut -f2 ../../text_norm/lex/ordinals_*?_lexicon.txt >> tmp
cut -f2 ../../text_norm/lex/units_lexicon.txt >> tmp
sort tmp | uniq > multiple_expansions.txt

# 183 difficult_multiple_expansions.txt  - Those that I focused on fixing, (hv., hæstv., þm., ordinals and numbers 1-4, kr., gr., mgr. o.fl.) I ficed by hand
cut -d" " -f2- tail18_text_unexpanded.txt | tr " " "\n" | egrep -v "^\s*$" | sort | uniq -c > words_tail18_unexpanded.cnt
tail -n18 text | cut -d" " -f2- | tr " " "\n" | egrep -v "^\s*$" | sort | uniq -c > words_text_tail18.cnt
for n in 2 3 5; do
    cut -d" " -f2- tail18_text_expanded_${n}g.txt | tr " " "\n" | egrep -v "^\s*$" | sort | uniq -c > words_tail18_expanded_${n}g.cnt
done

# Number of times the multiply expandable words are already written out in the unexpanded text:
join -1 1 -2 1 <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' words_tail18_unexpanded.cnt | sort -t" " -k1,1) difficult_multiple_expansions.txt > words_text_tail18_unexpanded_mult_exp.tmp
num_exp_in_unexp=$(awk '{ total += $2 } END { print total }' words_text_tail18_unexpanded_mult_exp.tmp)

# Number of times the multiply expandable words are written out in the last 18 speeches of text:
join -1 1 -2 1 <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' words_text_tail18.cnt | sort -t" " -k1,1) difficult_multiple_expansions.txt > words_text_tail18_mult_exp.tmp
num_exp_after_exp_true=$(awk '{ total += $2 } END { print total }' words_text_tail18_mult_exp.tmp)

# Number of times thrax expands words
num_exp_w_thrax=$(($num_exp_after_exp_true - $num_exp_in_unexp))
echo "Number of words expanded with thrax: "$num_exp_w_thrax

# Number of times the multiply expandable words are written out in the last 18 speeches of the newly expanded text:

for n in 2 3 5; do
    join -1 1 -2 1 <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' words_tail18_expanded_${n}g.cnt | sort -t" " -k1,1) difficult_multiple_expansions.txt > words_tail18_expanded_mult_exp_${n}g.tmp
declare num_exp_in_exp_${n}g=$(awk '{ total += $2 } END { print total }' words_tail18_expanded_mult_exp_${n}g.tmp)
done

#Col 2 is word freq in text and col 3 is word freq in the newly expanded file. Col 4 is the difference in between, i.e. errors
for n in 2 3 5; do
join -1 1 -2 1 words_text_tail18_mult_exp.tmp words_tail18_expanded_mult_exp_${n}g.tmp > tail18_text_newexp_word_freq_mult_exp_${n}g.txt

awk -F' ' 'function abs(v) {return v < 0 ? -v : v} {$4=abs($2-$3)}1' < tail18_text_newexp_word_freq_mult_exp_${n}g.txt | sort -nr -k4 > tail18_freq_diff_mult_exp_${n}g.txt

# Total number of those words in text
#awk '{ total += $2 } END { print total }' tail18_freq_diff_difficult_multiple_expansions_${n}g.txt

# number of differences between text and the newly expanded file
declare num_wrong_exp_${n}g=$(awk '{ total += $4 } END { print total }' tail18_freq_diff_mult_exp_${n}g.txt)
done
echo "Number of bad expansions 2g: "$num_wrong_exp_2g
echo "Number of bad expansions 3g: "$num_wrong_exp_3g
echo "Number of bad expansions 5g: "$num_wrong_exp_5g

echo "Proportion of bad expansions: "$(echo "scale=1;$num_wrong_exp_2g*100/$num_exp_w_thrax" | bc)
echo "Proportion of bad expansions: "$(echo "scale=1;$num_wrong_exp_3g*100/$num_exp_w_thrax" | bc)
echo "Proportion of bad expansions: "$(echo "scale=1;$num_wrong_exp_5g*100/$num_exp_w_thrax" | bc)
# If something was expanded to something which is not in difficult_multiple_expansions.txt then that is not taken into account.
