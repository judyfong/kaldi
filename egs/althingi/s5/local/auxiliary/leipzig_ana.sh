#!/bin/bash -e

# Check how many of my abbreviations are written out in the Leipzig data
# and look for some expanded numbers

# Check for each expanded abbr/number how many are in the filtered leipzig data
# Print to file 1st col = abbr/number , 2nd col = no of times written out in leipzig
# Get some statistics from this

IFS=$'\n'

leipzig=~/kaldi/egs/althingi/s5/text_norm/text/numbertexts.txt.gz
abbr_expanded=$(cut -f2 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_multiple_expansions.txt)

for abbr in $abbr_expanded
do
    count=$(gzip -cd $leipzig | grep "\b${abbr}\b" | wc -l)
    echo -e ${abbr}"\t"${count} >> text_norm/text/freq_of_expanded_abbr_leipzig.txt
done
