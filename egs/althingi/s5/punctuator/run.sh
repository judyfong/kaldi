#!/bin/bash -e

set -o pipefail

# Prepare data for punctuation model training, train the model, compare with the test sets and calculate the errors. NOTE! Need updating!

#date
d=$(date +'%Y%m%d')

stage=0
ignore_commas=true
suffix=
$ignore_commas && suffix=_noCOMMA
id= #_april2018 or exp_lr_decay_k0.8
two_stage=false                 # one or two stage training
continue_with_previous=false    # continue training an existing model

. ./path.sh
. ./utils/parse_options.sh
. ./local/utils.sh
. ./local/array.sh
. ./conf/path.conf

cleaned=$data/postprocessing
mkdir -p $cleaned/log

modeldir=$root_punctuation_modeldir/${d}
datadir=$root_punctuation_datadir/$d/first_stage$id
datadir_2nd_stage=$root_punctuation_datadir/$d/second_stage$id
mkdir -p $datadir/log $modeldir/log
$two_stage && mkdir -p $datadir_2nd_stage/log

source activate $CONDAPATH/thenv || error 11 ${error_array[11]};

if [ $stage -le -1 ]; then
  
  echo "Clean and preprocess the training data"
  utils/slurm.pl $datadir/log/prep_punct_data.log \
    punctuator/local/prep_punct_data.sh \
      $id $cleaned $datadir $datadir_2nd_stage || exit 1;
fi

if [ $stage -le 1 ]; then

  if ! $continue_with_previous; then
    rm -r processed_data &>/dev/null
  fi
  
  echo "Convert data"
  if [ -e $datadir_2nd_stage/althingi.train.txt ]; then
    sbatch --get-user-env --mem 12G --time 0-12:00 --job-name=data_2nd_stage --output=$datadir/log/data${id}${suffix}_w2nd_stage.log --wrap="srun python punctuator/data.py ${datadir} ${datadir_2nd_stage}"
  else
    sbatch --get-user-env --mem 12G --time 0-12:00 --job-name=data_stage --output=$datadir/log/data${id}$suffix.log --wrap="srun python punctuator/data.py ${datadir}"
  fi
fi

if [ $stage -le 2 ]; then
 
  echo "Train the model using first stage data"
  sbatch --get-user-env --job-name=main_first_stage --output=$modeldir/log/main_first_stage${id}$suffix.log --gres=gpu:1 --mem=12G --time=0-10:00 --wrap="srun python punctuator/main.py $modeldir althingi${id}${suffix} 256 0.02"

  if [ -e $datadir_2nd_stage/althingi.train.txt ]; then
    echo "Train the 2nd stage"
    sbatch --job-name=main_2nd_stage --output=$datadir/log/main_2nd_stage${id}$suffix.log --gres=gpu:1 --mem=12G --time=0-10:00 --wrap="srun python punctuator/main2.py $modeldir althingi${id}${suffix} 256 0.02 $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl"
  fi
fi

if [ $stage -le 3 ]; then
  echo "Punctuate the dev and test sets using the 1st stage model"
  for d in dev test; do
    sbatch --get-user-env --job-name=punctuator --mem=4G --wrap="THEANO_FLAGS='device=cpu' srun python punctuator/punctuator_filein.py $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir}/althingi.${d}.txt ${datadir}/${d}_punctuated_stage1${id}${suffix}.txt"
  done
  # Why did the following stop working???
  # sbatch --export=id=$id,suffix=$suffix,datadir=$datadir,modeldir=$modeldir punctuator/local/run_punctuator.sh
  wait
  
  if [ -e $datadir_2nd_stage/althingi.train.txt ]; then
    echo "Punctuate the dev and test sets using the 2nd stage model"
    sbatch --get-user-env --job-name=punctuator_2nd_stage --mem=4G --wrap="THEANO_FLAGS='device=cpu' srun python punctuator/punctuator_filein.py $modeldir/Model_stage2_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir_2nd_stage}/althingi.${d}.txt ${datadir_2nd_stage}/${d}_punctuated_stage1${id}${suffix}.txt 1"
    #sbatch --export=id=$id,suffix=$suffix,datadir=$datadir_2nd_stage,modeldir=$modeldir punctuator/local/run_punctuator_2nd_stage.sh
    wait
  fi
fi

if [ $stage -le 4 ]; then
  echo "Calculate the prediction errors"
  for f in dev test; do
    (
      python punctuator/error_calculator.py \
        ${datadir}/althingi.${f}.txt \
        ${datadir}/${f}_punctuated_stage1${id}$suffix.txt \
        > ${datadir}/${f}_error_stage1${id}$suffix.txt \
      || error 12 ${error_array[12]};
    ) &
  done
  
  if [ -e $datadir_2nd_stage/althingi.train.txt ]; then
    for f in dev test; do
      (
        python punctuator/error_calculator.py \
          ${datadir}/althingi.${f}.txt \
          ${datadir}/${f}_punctuated_stage2${id}$suffix.txt \
          > ${datadir}/${f}_error_stage2${id}$suffix.txt \
	|| error 12 ${error_array[12]};
      ) &
    done
    
  fi
fi

exit 0;
