#!/bin/bash -eu

set -o pipefail

datadir=data/althingiUploads

# Extract info about the speeches from althingi.is
srun --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_info.php &> data/althingiUploads/log/scraping_althingi_info.log" &

#Parse the info
source venv3/bin/activate
for session in $(seq 120 130); do
    python3 local/data_extraction/parsing_xml_forSGML.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_sgml.txt
    sort -u ${datadir}/thing${session}_sgml.txt > tmp && mv tmp ${datadir}/thing${session}_sgml.txt
done
deactivate

# Download the corresponding sgml
for session in $(seq 120 130); do
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_sgml.php /home/staff/inga/kaldi/egs/althingi/s5/data/althingiUploads/thing${session}_sgml.txt &> data/althingiUploads/log/extraction_thing${session}.log" &
done
