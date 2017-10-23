#!/bin/bash -eu

set -o pipefail

# Run from the s5 dir

data=~/data/althingi/postprocessing

out=example/out_cs
rm -rf $out
mkdir $out

echo "Clean the scraped data"
punctuator2/local/clean_scrapedAlthingiData.sh ${data}/../pronDict_LM/wp_lang.txt ${data}/scrapedTexts_clean_for_punct_restoring.txt

echo "Clean the 2005-2015 althingi data and combine with the scraped data"
punctuator2/local/clean_trainAlthingiData.sh data/all/text_orig_endanlegt.txt ~/data/althingi/postprocessing/texts05-15_clean_for_punct_restoring.txt

cat ${data}/scrapedTexts_clean_for_punct_restoring.txt ${data}/text05-15_clean_for_punct_restoring.txt > ${data}/text_for_punctRestoring.train.txt

echo "Clean the 2016 althingi data"
punctuator2/local/clean_TestData.sh data/all/text_orig_endanlegt.txt ${data}/text16_for_punctRestoring.dev.txt ${data}/text16_for_punctRestoring.test.txt

echo "Preprocess the data for training"
srun --mem 8G --time 0-04:00 python punctuator2/local/preprocessing_trainingdata_cs.py ${data}/text_for_punctRestoring.train.txt ${out}/althingi.train.txt &
python punctuator2/local/preprocessing_testdata_cs.py ${data}/text16_for_punctRestoring.dev.txt ${out}/althingi.dev.txt ${out}/numbers_dev.txt
python punctuator2/local/preprocessing_testdata_cs.py ${data}/text16_for_punctRestoring.test.txt ${out}/althingi.test.txt ${out}/numbers_test.txt

echo "Cleaning up..."
rm ${data}/*.tmp
echo "Preprocessing done."

echo "Convert data"
srun --mem 12G --time 0-12:00 python data.py ${out} &> data.log &

echo "Train the model using first stage data"
srun --gres gpu:1 --mem 12G --time 0-12:00 sh -c "python main.py althingi 256 0.02" &> first_stage.log &

echo "Train the second stage"
srun --gres gpu:1 --mem 12G --time 0-12:00 sh -c "python main2.py althingi 256 0.02 /home/staff/inga/kaldi/egs/althingi/s5/punctuator2" &> second_stage.log &

# Punctuate the dev and test sets using the first stage model
srun --nodelist=terra sh -c "cat ${out}/althingi.dev.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_althingi_h256_lr0.02.pcl ${out}/dev_punctuated_stage1.txt &>${out}/dev_punctuated_stage1.log" &
srun --nodelist=terra sh -c "cat ${out}/althingi.test.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_althingi_h256_lr0.02.pcl ${out}/test_punctuated_stage1.txt &>${out}/test_punctuated_stage1.log" &

# Punctuate the dev and test sets using the second stage model
srun --nodelist=terra sh -c "cat ${out}/althingi.dev.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_stage2_althingi_h256_lr0.002.pcl ${out}/dev_punctuated_stage2.txt 1 &>${out}/dev_punctuated_stage2.log" &
srun --nodelist=terra sh -c "cat ${out}/althingi.test.txt | THEANO_FLAGS='device=cpu' python punctuator.py Model_stage2_althingi_h256_lr0.002.pcl ${out}/test_punctuated_stage2.txt 1 &>${out}/test_punctuated_stage2.log" &

# Calculate the prediction errors
python error_calculator.py ${out}/althingi.dev.txt ${out}/dev_punctuated_stage1.txt > ${out}/dev_error_stage1.txt
python error_calculator.py ${out}/althingi.dev.txt ${out}/dev_punctuated_stage2.txt > ${out}/dev_error_stage2.txt
python error_calculator.py ${out}/althingi.test.txt ${out}/test_punctuated_stage1.txt > ${out}/test_error_stage1.txt
python error_calculator.py ${out}/althingi.test.txt ${out}/test_punctuated_stage2.txt > ${out}/test_error_stage2.txt

# Total number of training labels: 38484992
# Total number of validation labels: 131712
# Validation perplexity is 1.0905
# Finished!
# Best validation perplexity was 1.08477152664
