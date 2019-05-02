# List of commands to use when testing the keras model
# NOTE! This script is not to be run in whole!

n=bn4
source ~/virtualenvs/tfenv/bin/activate

sbatch --get-user-env --mem 12G --time 0-12:00 --job-name=data_stage1 --output=/mnt/scratch/inga/data/log/data.log --wrap="srun python local/keras_punctuation/data.py ~/data/punctuation/20180927/first_stage_noCOMMA/"

sbatch --get-user-env --job-name=main_first_stage --output=/mnt/scratch/inga/exp/punctuation/log/main_first_stage${n}.log --gres=gpu:1 --mem=12G --time=0-10:00 --wrap="srun python local/keras_punctuation/main_attention_batchnorm.py /mnt/scratch/inga/exp/punctuation keras_test${n} 256 0.0001"

srun --mem 4G python local/keras_punctuation/punctuator.py /mnt/scratch/inga/exp/punctuation/Model_keras_test${n}_h256_lr0.02.hdf5 ~/data/punctuation/20180927/first_stage_noCOMMA/althingi.test.txt /mnt/scratch/inga/exp/punctuation/test_punctuated${n}.txt &>/mnt/scratch/inga/exp/punctuation/log/test_punctuated.log &

python local/keras_punctuation/error_calculator.py ~/data/punctuation/20180927/first_stage_noCOMMA/althingi.test.txt /mnt/scratch/inga/exp/punctuation/test_punctuated${n}.txt > /mnt/scratch/inga/exp/punctuation/error_test_punctuated${n}.txt
