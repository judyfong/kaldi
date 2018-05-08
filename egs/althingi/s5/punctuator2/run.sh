#!/bin/bash -eu

set -o pipefail

ignore_commas=true
suffix=
$ignore_commas && suffix=_noCOMMA

#. ./cmd.sh
#. ./path.sh
#. ./utils/parse_options.sh

# Run from the punctuator2 dir 
#source theano-env/bin/activate # Activate the python virtual environment
source activate thenv

#data=/data/althingi/text_corpus
data=/mnt/scratch/inga/data/postprocessing
mkdir -p $data/log

# Identifier
id=april2018
s5dir=/home/staff/inga/kaldi/egs/althingi/s5
out=$s5dir/punctuator2/example/first_stage_$id
out_second_stage=$s5dir/punctuator2/example/second_stage_$id
mkdir -p $out

echo "Clean the scraped data"
#nohup $s5dir/local/punctuator/clean_scrapedAlthingiData.sh ${data}/../pronDict_LM/wp_lang.txt ${data}/scrapedTexts_clean_for_punct_restoring.txt &>log/clean_scraped.log &
nohup $s5dir/local/punctuator/clean_scrapedAlthingiData.sh ~/data/althingi/pronDict_LM/t131.txt ${data}/t131_clean_for_punct_restoring.txt &>${data}/log/clean_t131.log

echo "Clean the 2005-2015 althingi data and combine with the scraped data"
$s5dir/local/punctuator/clean_trainAlthingiData.sh <(grep -v rad2016 data/all_nov2016/text_orig_endanlegt.txt) ${data}/texts05-15_clean_for_punct_restoring.txt &>${data}/log/clean_nov2016_train.log
$s5dir/local/punctuator/clean_trainAlthingiData.sh data/all_okt2017/text_orig_endanlegt.txt ${data}/texts_okt2017_clean_for_punct_restoring.txt &>${data}/log/clean_okt2017.log
$s5dir/local/punctuator/clean_trainAlthingiData.sh data/all_sept2017/text_orig_endanlegt.txt ${data}/texts_sept2017_clean_for_punct_restoring.txt &>${data}/log/clean_sept2017.log
$s5dir/local/punctuator/clean_trainAlthingiData.sh /data/althingi/corpus_Des2016-March2018/text_orig_endanlegt.txt ${data}/texts_des16-march18_clean_for_punct_restoring.txt &>${data}/log/clean_des16-march18.log
wait

cat ${data}/t131_clean_for_punct_restoring.txt ${data}/texts05-15_clean_for_punct_restoring.txt ${data}/texts_okt2017_clean_for_punct_restoring.txt ${data}/texts_sept2017_clean_for_punct_restoring.txt ${data}/texts_des16-march18_clean_for_punct_restoring.txt > ${data}/text_for_punctRestoring.train.txt

echo "Clean the 2016 althingi data"
#$s5dir/local/punctuator/clean_testData.sh <(grep rad2016 ../data/all_nov2016/text_orig_endanlegt.txt) ${data}/text16_for_punctRestoring.dev.txt ${data}/text16_for_punctRestoring.test.txt
$s5dir/local/punctuator/clean_trainAlthingiData.sh <(grep rad2016 data/all_nov2016/text_orig_endanlegt.txt) ${data}/text16_for_punctRestoring.devtest.tmp &>${data}/log/clean_devtest.log
nlines_half=$(echo $((($(wc -l ${data}/text16_for_punctRestoring.devtest.tmp | cut -d" " -f1)+1)/2)))
head -n $nlines_half ${data}/text16_for_punctRestoring.devtest.tmp > ${data}/text16_for_punctRestoring.dev.txt
tail -n +$[$nlines_half+1] ${data}/text16_for_punctRestoring.devtest.tmp > ${data}/text16_for_punctRestoring.test.txt

echo "Preprocess the data for training"
srun --mem 8G --nodelist=terra python $s5dir/local/punctuator/preprocessing_trainingdata_cs.py ${data}/text_for_punctRestoring.train.txt ${out}/althingi.train.txt &> ${data}/log/preprocessing_trainingdata_cs.log &
# python $s5dir/local/punctuator/preprocessing_testdata_cs.py ${data}/text16_for_punctRestoring.dev.txt ${out}/althingi.dev.txt ${out}/numbers_dev.txt
# python $s5dir/local/punctuator/preprocessing_testdata_cs.py ${data}/text16_for_punctRestoring.test.txt ${out}/althingi.test.txt ${out}/numbers_test.txt
python $s5dir/local/punctuator/preprocessing_trainingdata_cs.py ${data}/text16_for_punctRestoring.dev.txt ${out}/althingi.dev.txt
python $s5dir/local/punctuator/preprocessing_trainingdata_cs.py ${data}/text16_for_punctRestoring.test.txt ${out}/althingi.test.txt

##################

echo "Prepare the pause annotated data"
$s5dir/local/punctuator/clean_AlthingiData_pause.sh data/all_sept2017/text_orig_endanlegt.txt ${data}/texts_pause_clean_for_punct_restoring.txt

echo "Preprocess the data"
srun --mem 8G --time 0-04:00 --nodelist=terra python $s5dir/local/punctuator/preprocessing_pause_data.py ${data}/texts_pause_clean_for_punct_restoring.txt ${out_second_stage}/althingi.train_Sept2017_pause_simpleExp.txt &

echo "Make the Sept 2017 data pause annotated"
$s5dir/local/punctuator/make_pause_annotated.sh

##################

echo "Cleaning up..."
rm ${data}/*.tmp
echo "Preprocessing done."

##################

# If I want to ignore commas in the training:
if [ ignore_commas = true ]; then
  out_noComma=$s5dir/punctuator2/example/first_stage_${id}$suffix
  mkdir -p $out_noComma/log
  for f in althingi.{train,dev,test}.txt; do
    sed -re 's: ,COMMA::g' $out/$f > $out_noComma/$f
  done
  out=$out_noComma
  if [ -e $out_second_stage/althingi.train.txt ]; do
    out_second_stage_noComma=$s5dir/punctuator2/example/second_stage_${id}$suffix
    mkdir -p $out_second_stage_noComma/log
    for f in althingi.{train,dev,test}.txt; do
      sed -re 's: ,COMMA::g' ${out_second_stage}/$f > $out_second_stage_noComma/$f
    done
    out_second_stage=$out_second_stage_noComma
  fi
fi
  
##################
  
echo "Convert data"
#srun --mem 12G --time 0-12:00 python data.py ${out} &> data.log &
if [ -e $out_second_stage/althingi.train.txt ]; do
  srun --mem 12G --time 0-12:00 --nodelist=terra python data.py ${out} ${out_second_stage} &> $out/log/data_${id}.log &
else
  srun --mem 12G --time 0-12:00 --nodelist=terra python data.py ${out} &> $out/log/data_${id}$suffix.log &
fi

echo "Train the model using first stage data"
sbatch --job-name=main_first_stage --output=$out/log/main_first_stage.log --gres=gpu:1 --mem=12G --time=0-10:00 --nodelist=terra --wrap="srun python main.py althingi_${id}${suffix} 256 0.02"

#sbatch --export=id=$id,suffix=$suffix,out=$out ../local/punctuator/run_main.sh
  
#srun --gres gpu:1 --mem 12G --time 0-12:00 --nodelist=terra python main.py althingi_${id}$suffix 256 0.02 &> $out/log/first_stage_${id}$suffix.log &

if [ -e $out_second_stage/althingi.train.txt ]; do
  echo "Train the second stage"
  srun --gres gpu:1 --mem 12G --time 0-12:00 --nodelist=terra python main2.py althingi_${id}$suffix 256 0.02 Model_althingi_${id}${suffix}_h256_lr0.02.pcl &> $out/log/second_stage_${id}$suffix.log &
fi

# Punctuate the dev and test sets using the 1st stage model
sbatch ../local/punctuator/run_punctuator.sh
  
# srun --nodelist=terra sh -c "cat ${out}/althingi.dev.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_althingi_${id}${suffix}_h256_lr0.02.pcl ${out}/dev_punctuated_stage1_${id}$suffix.txt &>${out}/log/dev_punctuated_stage1_${id}$suffix.log" &
# srun --nodelist=terra sh -c "cat ${out}/althingi.test.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_althingi_${id}${suffix}_h256_lr0.02.pcl ${out}/test_punctuated_stage1_${id}$suffix.txt &>${out}/log/test_punctuated_stage1_${id}$suffix.log" &

if [ -e $out_second_stage/althingi.train.txt ]; do
  # Punctuate the dev and test sets using the 2nd stage model
  srun --nodelist=terra sh -c "cat ${out}/althingi.dev.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_stage2_althingi_${id}${suffix}_h256_lr0.02.pcl ${out}/dev_punctuated_stage2_${id}$suffix.txt 1 &>${out}/log/dev_punctuated_stage2_${id}$suffix.log" &
  srun --nodelist=terra sh -c "cat ${out}/althingi.test.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_stage2_althingi_${id}${suffix}_h256_lr0.02.pcl ${out}/test_punctuated_stage2_${id}$suffix.txt 1 &>${out}/log/test_punctuated_stage2_${id}$suffix.log" &
fi

# Calculate the prediction errors - 1st stage model
python error_calculator.py ${out}/althingi.dev.txt ${out}/dev_punctuated_stage1_${id}$suffix.txt > ${out}/dev_error_stage1_${id}$suffix.txt
python error_calculator.py ${out}/althingi.test.txt ${out}/test_punctuated_stage1_${id}$suffix.txt > ${out}/test_error_stage1_${id}$suffix.txt

if [ -e $out_second_stage/althingi.train.txt ]; do
  # Calculate the prediction errors - 2nd stage model
  python error_calculator.py ${out}/althingi.dev.txt ${out}/dev_punctuated_stage2_${id}$suffix.txt > ${out}/dev_error_stage2_${id}$suffix.txt
  python error_calculator.py ${out}/althingi.test.txt ${out}/test_punctuated_stage2_${id}$suffix.txt > ${out}/test_error_stage2_${id}$suffix.txt
fi

# Total number of training labels: 38484992
# Total number of validation labels: 131712
# Validation perplexity is 1.0905
# Finished!
# Best validation perplexity was 1.08477152664
