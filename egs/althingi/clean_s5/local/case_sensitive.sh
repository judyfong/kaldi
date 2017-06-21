#!/bin/bash -eu

set -o pipefail

. ./cmd.sh
. ./path.sh

pronDictdir=$1
datadir=$2

if [ $# != 2 ]; then
   echo "Usage: local/case_sensitive.sh <pron-dict-dir> <data-dir>"
   echo "e.g.: local/case_sensitive.sh ~/data/althingi/pronDict_LM data/all"
fi

# I went through capitalized words in the original Málföng's pron dict
# and corrected words that were incorrectly capitalized. I used the resulting
# list, as well as a list of capitalized words in BÍN and lists over countries
# and capitals to capitalize my pron dict. Which in turn I used to capitalize my texts.

# Capitalize words in Althingi texts, that are capitalized in the pron dict

# Extract proper nouns from the althingi texts, which have to be capitalized
comm -12 <(sed -e 's/\(.*\)/\L\1/' ${pronDictdir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(cut -d" " -f2- ${datadir}/text | tr " " "\n" | grep -Ev "^\s*$" | sort -u ) > ${pronDictdir}/propernouns_althingi.txt
# Make the regex pattern
tr "\n" "|" < ${pronDictdir}/propernouns_althingi.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > ${pronDictdir}/propernouns_althingi_pattern.tmp

# Capitalize
srun --mem 8G sed -e 's/\(\b'$(cat ${pronDictdir}/propernouns_althingi_pattern.tmp)'\b\)/\u\1/g' ${datadir}/text > ${datadir}/text_CaseSens.txt

# Capitalize words in the scraped Althingi texts, that are capitalized in the pron dict
comm -12 <(sed -e 's/\(.*\)/\L\1/' ${pronDictdir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(tr " " "\n" < scrapedAlthingiTexts_clean.txt | grep -Ev "^\s*$" | sort -u) > ${pronDictdir}/propernouns_scraped_althingi_texts.txt
# Make the regex pattern
tr "\n" "|" < ${pronDictdir}/propernouns_scraped_althingi_texts.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > ${pronDictdir}/propernouns_scraped_althingi_texts_pattern.tmp

# Capitalize
srun --mem 8G sed -e 's/\(\b'$(cat ${pronDictdir}/propernouns_scraped_althingi_texts_pattern.tmp)'\b\)/\u\1/g' ${pronDictdir}/scrapedAlthingiTexts_clean.txt > ${pronDictdir}/scrapedAlthingiTexts_clean_CaseSens.txt

rm ${pronDictdir}/*.tmp
