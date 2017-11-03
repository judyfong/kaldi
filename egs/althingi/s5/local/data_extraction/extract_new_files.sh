#!/bin/bash -eu

set -o pipefail

datadir=data/althingiUploads
corpusdir=/data/althingi/corpus_okt2017/AlthingiUploads

# Extract info about the speeches from althingi.is
srun --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_info.php &> data/althingiUploads/log/scraping_althingi_info.log" &

#Parse the info
for session in $(seq 132 145); do
    python local/data_extraction/parsing_xml.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_mp3_xml_all.txt
    sort -u ${datadir}/thing${session}_mp3_xml_all.txt > tmp && mv tmp ${datadir}/thing${session}_mp3_xml_all.txt
done

# All speeches already in training and testing sets:
cat data/train_combined/text data/dev/text data/eval/text | cut -d" " -f1 | cut -d"-" -f2 | cut -d"_" -f1 | sort -u > ids_in_use
ls ${corpusdir}/audio/ | cut -d"." -f1 | sort -u >> ids_in_use
sort -u ids_in_use > tmp && mv tmp ids_in_use

# Extract the ids of speeches that we don't already have in our data
for session in $(seq 132 145); do
    comm -13 <(sort -u ids_in_use) <(cut -f1 ${datadir}/thing${session}_mp3_xml_all.txt | sort -u) > ${datadir}/new${session}.txt

    while [ "$(wc -l ${datadir}/new${session}.txt | cut -d" " -f1)" -gt 3000 ]; do
	head -n3000 ${datadir}/new${session}.txt > ${datadir}/new${session}_head.txt
	sed -r -i '1,3000d' ${datadir}/new${session}.txt

	# Make the regex pattern. Need to split up the lists!
        tr "\n" "|" < ${datadir}/new${session}_head.txt | sed '$s/|$//' > ${datadir}/pattern_session${session}_head.tmp

        # keep the lines that reference new files
        sed -nr '/'$(cat ${datadir}/pattern_session${session}_head.tmp)'/p' ${datadir}/thing${session}_mp3_xml_all.txt >> ${datadir}/thing${session}_mp3_xml_new.txt
    done
    
    # Make the regex pattern from the last lines.
    tr "\n" "|" < ${datadir}/new${session}.txt | sed '$s/|$//' > ${datadir}/pattern_session${session}.tmp

    # keep the lines that reference new files
    sed -nr '/'$(cat ${datadir}/pattern_session${session}.tmp)'/p' ${datadir}/thing${session}_mp3_xml_all.txt >> ${datadir}/thing${session}_mp3_xml_new.txt
done
#rm ${datadir}/*.tmp

# Download the corresponding audio and xml
for session in $(seq 132 145); do
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml_mp3.php /home/staff/inga/kaldi/egs/althingi/s5/data/althingiUploads/thing${session}_mp3_xml_new.txt &> data/althingiUploads/log/extraction_thing${session}.log" &
done

# # Since I got almost 12000 errors of the form: <html><body>Það hefur komið upp villa. Reyndu aftur síðar.</body></html>, error status 403, I try fetching them again
# while [ "$(wc -l only_audio.txt | cut -d" " -f1)" -gt 3000 ]; do
#     head -n3000 only_audio.txt > only_audio_head.txt
#     sed -r -i '1,3000d' only_audio.txt

#     # Make the regex pattern. Need to split up the lists!
#     tr "\n" "|" < only_audio_head.txt | sed '$s/|$//' > only_audio_head_pattern.tmp

#     # keep the lines that reference new files
#     sed -nr '/'$(cat only_audio_head_pattern.tmp)'/p' <(cat thing*_mp3_xml_all.txt) >> only_audio_mp3_xml.txt
# done
    
# # Make the regex pattern from the last lines.
# tr "\n" "|" < only_audio.txt | sed '$s/|$//' > only_audio_pattern.tmp

# # keep the lines that reference new files
# sed -nr '/'$(cat only_audio_pattern.tmp)'/p' <(cat thing*_mp3_xml_all.txt) >> only_audio_mp3_xml.txt

# # Extract the text again
# srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml.php /home/staff/inga/kaldi/egs/althingi/s5/data/althingiUploads/only_audio_mp3_xml.txt &> data/althingiUploads/log/extract_xml_to_only_audio.log" &
