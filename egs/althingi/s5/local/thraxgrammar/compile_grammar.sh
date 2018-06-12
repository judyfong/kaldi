#!/bin/bash -e

. ./path.sh

# Run from s5 directory
indir=local/thraxgrammar
outdir=~/models/text_norm

# Compile the grammar to expand numbers and abbreviations
# also the one used when selecting which utterances
# to keep for training an expansion language model
thraxmakedep $indir/expand.grm
make

# Compile the grammar to abbreviate numbers and abbreviations
# after transcribing text, also the one used to insert periods
# into abbreviations
thraxmakedep $indir/abbreviate.grm
make

# Extract the fst from the compiled grammar
# and move the fst to the output dir
farextract --filename_suffix=".fst" $indir/expand.far $indir/abbreviate.far
mv -t $outdir *.fst
