#!/bin/bash -e

. ./path.sh

# Run from s5 directory

# Compile the grammar to expand numbers and abbreviations
# also the one used when selecting which utterances
# to keep for training an expansion language model
thraxmakedep local/expand.grm
make

# Extract the fst from the compiled grammar
farextract --filename_suffix=".fst" local/expand.far
mv EXPAND_UTT.fst text_norm
mv ABBREVIATE_forExpansion.fst text_norm

# Compile the grammar to abbreviate numbers and abbreviations
# after transcribing text, also the one used to insert periods
# into abbreviations
thraxmakedep local/abbreviate.grm
make

# Extract the fst from the compiled grammar
farextract --filename_suffix=".fst" local/abbreviate.far
mv ABBREVIATE.fst text_norm
mv INS_PERIODS.fst text_norm
