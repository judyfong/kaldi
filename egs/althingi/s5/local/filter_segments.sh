#!/bin/bash -eu

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

for s in spk2utt text utt2spk wav.scp wps_stats.txt wps.txt; do
  [ ! -e ${newdir}/$s ] && cp -r ${dir}/$s ${newdir}/$s
done

LC_ALL=C sort -k2,2 ${newdir}/wps.txt > temp && mv temp ${newdir}/wps.txt
LC_ALL=C sort -k1,1 ${newdir}/wps_stats.txt > temp && mv temp ${newdir}/wps_stats.txt

wps10percentile=$(cut -d" " -f1 ${newdir}/wps.txt | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.10 + 0.5)]}')
wps90percentile=$(cut -d" " -f1 ${newdir}/wps.txt | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.90 - 0.5)]}')

# Find the ID of the segments that fulfill the requirements.
IFS=$'\n'
for line in $(cat ${newdir}/wps_stats.txt); do
  ID=$(echo $line | cut -d" " -f1)
  p5=$(echo $line | cut -d" " -f10)
  p95=$(echo $line | cut -d" " -f14)
  awk -v var1="$ID" -v var2="$p5" -v var3="$p95" -v var4="$wps10percentile" -v var5="$wps90percentile" '{if ($3 ~ var1 && ($1 > var2 || $1 > var4) && ($1 < var3 || $1 < var5)) print $2}'  \
      < ${newdir}/wps.txt >> ${newdir}/segm_keep.tmp
done

# Filter the segments
join -1 1 -2 1 <(sort ${newdir}/segm_keep.tmp) <(sort ${dir}/segments) | LC_ALL=C sort > ${newdir}/segments

# Sort and filter the other files
utils/validate_data_dir.sh --no-feats ${newdir} || utils/fix_data_dir.sh ${newdir}

rm *.tmp
exit 0
