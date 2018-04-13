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

# Extract word that are only used capitalized.
comm -23 <(egrep '^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]' $pronDictdir/CaseSensitive_pron_dict_Fix19.txt \
		  | cut -f1 | sed -r 's:.*:\L&:' | sort -u) \
     <(cut -f1 $pronDictdir/CaseSensitive_pron_dict_Fix19.txt | sort -u) | sed -r 's:.*:\u&:' \
     > CaseSensitive_pron_dict_propernouns.txt

# Capitalize words in Althingi texts, that are capitalized in the pron dict

# Extract proper nouns from the althingi texts, which have to be capitalized
comm -12 <(sed 's:.*:\L&:' ${pronDictdir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(cut -d" " -f2- ${datadir}/text | tr " " "\n" | grep -Ev "^\s*$" | sort -u ) > ${pronDictdir}/propernouns_althingi.txt
# Make the regex pattern
tr "\n" "|" < ${pronDictdir}/propernouns_althingi.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${pronDictdir}/propernouns_althingi_pattern.tmp

# Capitalize
srun sed -r 's:(\b'$(cat ${pronDictdir}/propernouns_althingi_pattern.tmp)'\b):\u\1:g' ${datadir}/text > ${datadir}/text_CaseSens.txt

#rm ${pronDictdir}/*.tmp

