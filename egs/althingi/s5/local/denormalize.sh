#!/bin/bash -eu

set -o pipefail

# 2017 Inga Rún Helgadóttir
# Denormalize speech recognition output

# An implementation of thraxrewrite-tester that takes in a file and returns an output file where the option with the lowest weight is chosen
thraxrewrite-fileio --far=abbreviate.far --rules=ABBREVIATE --noutput=1 --input_mode=utf8 --output_mode=utf8 <input-text-file> <output-text-file>

# Restore punctuations
srun python ~/punctuator/example/preprocessing_testfiles.py <input_text> <output_text> <num_list>

srun --gres gpu:1 sh -c 'cat ~/punctuator/example/out/althingi.test.txt | python ~/punctuator/punctuator.py ~/punctuator/Model_althingi_h256_lr0.02.pcl ~/punctuator/example/out/punctuator_test.txt &>~/punctuator/log/punctuator_puntuator_test.log' &

srun python ~/punctuator/example/local/re-inserting-numbers.py <punctuator_output_text> <num_list> <starting-index-in-num_list> <output_wNumbers>

# Capitalize proper names, location and organization names

# Capitalize sentence beginnings and add periods to abbreviations.
