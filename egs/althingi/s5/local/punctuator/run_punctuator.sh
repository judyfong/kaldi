#! /bin/bash
#
#SBATCH --ntasks=8

id=april2018
suffix=_noCOMMA
out=/home/staff/inga/kaldi/egs/althingi/s5/punctuator2/example/first_stage_${id}$suffix

for d in dev test
do
  srun --nodelist=terra sh -c "cat ${out}/althingi.$d.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_althingi_${id}${suffix}_h256_lr0.02.pcl ${out}/${d}_punctuated_stage1_${id}${suffix}.txt &>${out}/log/${d}_punctuated_stage1_${id}${suffix}.log" &
done
wait
