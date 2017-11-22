#!/bin/bash -eu

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

set -o pipefail

# Select segments to keep based on words/second ratio for each congressman.
# Cut out segments with wps outside 10 and 90 percentiles of all segments
# and with wps outside 5 and 95 percentiles for that particular speaker.

if [ $# -ne 2 ]; then
    echo "Usage: $0 <orig-data-dir> <new-data-dir>" >&2
    echo "Eg. $0 data/all_reseg data/all_reseg_filtered" >&2
    exit 1;
fi

dir=$1
newdir=$2
mkdir -p $newdir

#for s in spk2utt text utt2spk wav.scp wps_stats.txt wps.txt; do
for s in spk2utt text utt2spk wav.scp wps.txt; do
  [ ! -e ${newdir}/$s ] && cp -r ${dir}/$s ${newdir}/$s
done

# Filter using constant values
awk -F" " '{if ($1 > 0.4 && $1 < 5.5) print;}' < ${newdir}/wps.txt > ${newdir}/wps_filtered.txt

# Filter the segments
join -1 1 -2 1 <(cut -d" " -f2 ${newdir}/wps_filtered.txt | sort) <(sort ${dir}/segments) | LC_ALL=C sort > ${newdir}/segments

# LC_ALL=C sort -k2,2 ${newdir}/wps.txt > temp && mv temp ${newdir}/wps.txt
# LC_ALL=C sort -k1,1 ${newdir}/wps_stats.txt > temp && mv temp ${newdir}/wps_stats.txt

# wps1percentile=$(cut -d" " -f1 ${newdir}/wps.txt | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.01 + 0.5)]}')
# wps99percentile=$(cut -d" " -f1 ${newdir}/wps.txt | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.99 - 0.5)]}')

# # Find the ID of the segments that fulfill the requirements.
# IFS=$'\n'
# for line in $(cat ${newdir}/wps_stats.txt); do
#   ID=$(echo $line | cut -d" " -f1)
#   p1=$(echo $line | cut -d" " -f9)
#   p99=$(echo $line | cut -d" " -f15)
#   awk -v var1="$ID" -v var2="$p1" -v var3="$p99" -v var4="$wps1percentile" -v var5="$wps99percentile" '{if ($3 ~ var1 && ($1 > var2 || $1 > var4) && ($1 < var3 || $1 < var5)) print $2}'  \
#       < ${newdir}/wps.txt >> ${newdir}/segm_keep.tmp
# done

# # Filter the segments
# join -1 1 -2 1 <(sort ${newdir}/segm_keep.tmp) <(sort ${dir}/segments) | LC_ALL=C sort > ${newdir}/segments

# Sort and filter the other files
utils/validate_data_dir.sh --no-feats ${newdir} || utils/fix_data_dir.sh ${newdir}

# rm ${newdir}/*.tmp
exit 0
