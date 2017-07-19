#!/bin/bash -eu

set -o pipefail

# Run from the example dir

data=~/data/althingi/postprocessing
dataall=~/kaldi/egs/althingi/s5/data/all
dataall100=~/kaldi/egs/althingi/s5/data/all100

out=example/out_cs
rm -rf $out
mkdir $out

echo "Clean the scraped data"
./example/local/clean_scrapedAlthingiData.sh ${data}/../pronDict_LM/wp_lang.txt ${data}/scrapedTexts_clean_for_punct_restoring_CS.txt

#grep "rad2012" ${dataall}/text_noXML_bb.txt | cut -d" " -f2- > ${data}/text12_noXML.tmp

echo "Clean the 2005-2015 althingi data and combine with the scraped data"
perl -pe 's/<mgr>\/\/[^\/<]*?\/\/<\/mgr>|<!--[^>]*?-->|<[^>]*?>[^<]*?http[^<]*?<\/[^>]*?>|<[^>]*?>:[^<]*?ritun[^<]*?<\/[^>]*?>|<mgr>[^\/]*?\/\/<\/mgr>|<ræðutexti> +<mgr>[^\/]*?\/<\/mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+<\/mgr>|<truflun>[^<]*?<\/truflun>|<atburður>[^<]*?<\/atburður>|<málsheiti>[^<]*?<\/málsheiti>/ /g' <(egrep "rad201[345]" ${dataall100}/text_orig_bb.txt | cut -d" " -f2-) | perl -pe 's/\b([0-9])\/([0-9]{1,2})\b/$1 $2\./g' | perl -pe 's/\/?([0-9]+)\/([0-9]+)/ $1 $2/g' | perl -pe 's/([0-9]+)\/([A-Z]{2,})/$1 $2/g' | perl -pe 's/([0-9])\/ ([0-9])/$1 $2/g' | perl -pe 's/\([^\/\(<>]*?\)/ /g' | perl -pe 's/\([^\/<>\)]*?\/+/ /g' | perl -pe 's/\/[^\/<>\)]*?\)+\/?/ /g' | perl -pe 's/\/+[^\/<>\)]*?\/+/ /g' | perl -pe 's/<[^<>]*?>/ /g' | sed -e "s/[[:space:]]\+/ /g" > ${data}/text13-15_noXML.tmp

#cat ${data}/text12_noXML.tmp ${data}/text13-15_noXML.tmp > ${data}/text12-15_noXML.tmp
cat <(cut -d" " -f2- ${dataall}/text_noXML_bb.txt) ${data}/text13-15_noXML.tmp > ${data}/text05-15_noXML.tmp

#./local/clean_scrapedAlthingiData.sh ${data}/text12-15_noXML.tmp ${data}/text12-15_clean_for_punctRest_CS.txt
./example/local/clean_scrapedAlthingiData.sh ${data}/text05-15_noXML.tmp ${data}/text05-15_clean_for_punctRest_CS.txt
#cat ${data}/scrapedTexts_clean_for_punct_restoring_CS.txt ${data}/text12-15_clean_for_punctRest_CS.txt > ${data}/text_for_punctRestoring.train_CS.txt
cat ${data}/scrapedTexts_clean_for_punct_restoring_CS.txt ${data}/text05-15_clean_for_punctRest_CS.txt > ${data}/text_for_punctRestoring.train_CS.txt

echo "Clean the 2016 althingi data"
perl -pe 's/<mgr>\/\/[^\/<]*?\/\/<\/mgr>|<!--[^>]*?-->|<[^>]*?>[^<]*?http[^<]*?<\/[^>]*?>|<[^>]*?>:[^<]*?ritun[^<]*?<\/[^>]*?>|<mgr>[^\/]*?\/\/<\/mgr>|<ræðutexti> +<mgr>[^\/]*?\/<\/mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+<\/mgr>|<truflun>[^<]*?<\/truflun>|<atburður>[^<]*?<\/atburður>|<málsheiti>[^<]*?<\/málsheiti>/ /g' <(grep "rad2016" ${dataall100}/text_orig_bb.txt | cut -d" " -f2-) | perl -pe 's/\b([0-9])\/([0-9]{1,2})\b/$1 $2\./g' | perl -pe 's/\/?([0-9]+)\/([0-9]+)/ $1 $2/g' | perl -pe 's/([0-9]+)\/([A-Z]{2,})/$1 $2/g' | perl -pe 's/([0-9])\/ ([0-9])/$1 $2/g' | perl -pe 's/\([^\/\(<>]*?\)/ /g' | perl -pe 's/\([^\/<>\)]*?\/+/ /g' | perl -pe 's/\/[^\/<>\)]*?\)+\/?/ /g' | perl -pe 's/\/+[^\/<>\)]*?\/+/ /g' | perl -pe 's/<[^<>]*?>/ /g' | sed -e "s/[[:space:]]\+/ /g" > ${data}/text16_noXML.tmp
./example/local/clean_TestData.sh ${data}/text16_noXML.tmp ${data}/text16_for_punctRestoring.dev_CS.txt ${data}/text16_for_punctRestoring.test_CS.txt

echo "Preprocess the data for training"
srun --mem 8G --time 0-04:00 python example/local/preprocessing_trainingdata.py ${data}/text_for_punctRestoring.train_CS.txt ${out}/althingi.train_LC.txt &
python example/local/preprocessing_testdata.py ${data}/text16_for_punctRestoring.dev_CS.txt ${out}/althingi.dev_LC.txt ${out}/numbers_dev.txt
python example/local/preprocessing_testdata.py ${data}/text16_for_punctRestoring.test_CS.txt ${out}/althingi.test_LC.txt ${out}/numbers_test.txt

echo "Capitalize proper nouns"
cat ~/data/althingi/pronDict_LM/LMtexts_CaseSens.txt <(cut -d" " -f2- ~/kaldi/egs/althingi/s5/data/all/text2016_CaseSens.txt) | grep -o '[^ ]*[A-ZÁÐÉÍÓÚÝÞÆÖ][^ ]*' | sort -u > ${out}/propernouns_all.txt

tr "\n" "|" < ${out}/propernouns_all.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > ${out}/propernouns_pattern.tmp

# Capitalize
srun --mem 8G --time 0-12:00 sed -e 's/\(\b'$(cat ${out}/propernouns_pattern.tmp)'\b\)/\u\1/g' ${out}/althingi.train_LC.txt > ${out}/althingi.train.txt
srun --mem 8G sed -e 's/\(\b'$(cat ${out}/propernouns_pattern.tmp)'\b\)/\u\1/g' ${out}/althingi.dev_LC.txt > ${out}/althingi.dev.txt
srun --mem 8G sed -e 's/\(\b'$(cat ${out}/propernouns_pattern.tmp)'\b\)/\u\1/g' ${out}/althingi.test_LC.txt > ${out}/althingi.test.txt


echo "Cleaning up..."
rm ${data}/*.tmp
echo "Preprocessing done."

echo "Convert data"
srun --mem 12G --time 0-12:00 python data.py ${out}

echo "Train the model"
srun --gres gpu:1 --mem 12G --time 0-12:00 sh -c "python main.py althingi_CS 256 0.02" &


# Total number of training labels: 38484992
# Total number of validation labels: 131712
# Validation perplexity is 1.0905
# Finished!
# Best validation perplexity was 1.08477152664
