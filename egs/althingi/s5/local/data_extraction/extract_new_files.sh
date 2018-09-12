#!/bin/bash -eu

set -o pipefail

. ./path.sh # $data defined here
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "This script extract audio files and corresponding transcripts from althingi.is given the start and finish session numbers."
  echo ""
  echo "Usage: $0 <path-to-original-data> <output-data-dir>" >&2
  echo "e.g.: $0 /data/local/corpus_20180612 132 148" >&2
  exit 1;
fi
# $data is defined in path.conf
corpusdir=$1; shift #/data/althingi/corpus_jun2018
start=$1; shift #146
stop=$1; #148

datadir=$data/data_extraction/althingi_info

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# Extract info about the speeches from althingi.is
srun --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_info.php $datadir/thing $start $stop &> $datadir/log/scraping_althingi_info.log" &

#Parse the info
source venv3/bin/activate
for session in $(seq $start $stop); do
    if [ $session -gt 146 ]; then
        python local/data_extraction/parsing_xml_new.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_mp3_xml_all.txt
    else
	python local/data_extraction/parsing_xml.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_mp3_xml_all.txt
    fi
    sort -u ${datadir}/thing${session}_mp3_xml_all.txt > tmp && mv tmp ${datadir}/thing${session}_mp3_xml_all.txt
done
deactivate

# All speeches already in training and testing sets:
cat $root_intermediate/all*/text | cut -d" " -f1 | cut -d"-" -f2 | sort -u > $tmp/ids_in_use
ls ${corpusdir}/audio/ | cut -d"." -f1 | sort -u >> $tmp/ids_in_use

# Extract the ids of speeches that we don't already have in our data
if [ -s $tmp/ids_in_use ]; then
  for session in $(seq $start $stop); do
    grep -f $tmp/ids_in_use ${datadir}/thing${session}_mp3_xml_all.txt > $tmp/used.tmp
    comm -13 <(sort -u $tmp/used.tmp) <(sort -u ${datadir}/thing${session}_mp3_xml_all.txt) > ${datadir}/thing${session}_mp3_xml_new.txt
  done
else
  mv ${datadir}/thing${session}_mp3_xml_all.txt ${datadir}/thing${session}_mp3_xml_new.txt
fi

# Download the corresponding audio and xml
for session in $(seq $start $stop); do
    # Make sure all the files contain xml files
    awk -F $'\t' 'NF==4{print}{}' ${datadir}/thing${session}_mp3_xml_new.txt > $tmp/withXML.tmp && mv $tmp/withXML.tmp ${datadir}/thing${session}_mp3_xml_new.txt
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml_mp3.php ${datadir}/thing${session}_mp3_xml_new.txt /data/althingi/corpus_jun2018/audio/ /data/althingi/corpus_jun2018/text_endanlegt/ &> ${datadir}/log/extraction_thing${session}.log" &
done

# I got almost 12000 errors of the form: <html><body>Það hefur komið upp villa. Reyndu aftur síðar.</body></html>, error status 403. Fetching them again worked for a lot of them.

exit 0;
