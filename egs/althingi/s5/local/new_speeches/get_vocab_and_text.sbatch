#! /bin/bash
#
#SBATCH --get-user-env
#SBATCH --mem=8G

# Declare the variables
# To run: sbatch --export=xml=$xml,outdir=$outdir local/new_speeches/get_vocab_and_text.sbatch

speechname=$(basename "$xml")
speechname="${speechname%.*}" # remove the extension
mkdir -p $outdir/log

srun -n1 --exclusive local/new_speeches/extract_new_vocab_and_text.sh $xml $outdir &> $outdir/log/$speechname.log

