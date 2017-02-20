#!/bin/bash -eu

set -o pipefail

# 2017 Inga Rún Helgadóttir
# Denormalize speech recognition transcript

# local/denormalize.sh <text-input> <denormalized-text-output>

ifile=$1
ofile=$2

# An implementation of thraxrewrite-tester that takes in a file and returns an output file where the option with the lowest weight is chosen
thraxrewrite-fileio --far=abbreviate.far --rules=ABBREVIATE --noutput=1 --input_mode=utf8 --output_mode=utf8 $ifile thrax_out.tmp

# Restore punctuations
srun python ~/punctuator/example/preprocessing_testfiles.py thrax_out.tmp punctuator_in.tmp numlist.tmp

srun --gres gpu:1 sh -c 'cat punctuator_in.tmp | python ~/punctuator/punctuator.py ~/punctuator/Model_althingi_h256_lr0.02.pcl punctuator_out.tmp &>~/punctuator/log/punctuator_test.log' &

srun python ~/punctuator/example/local/re-inserting-numbers.py punctuator_out.tmp numlist.tmp 0 punctuator_out_wNumbers.tmp

# Capitalize proper names, location and organization names
# Implement!

# Capitalize sentence beginnings and add periods to abbreviations.
# Implement! Regex for capitalization and thrax for the periods.
