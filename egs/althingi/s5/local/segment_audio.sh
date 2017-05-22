#!/bin/bash -eu

# 2017 Inga Rún

# Begin configuration section.
min_seg_length=5
min_sil_length=0.8 # 0.5
# End configuration section.

echo "$0 $@"

[ -f ./path.sh ] && . ./path.sh
#. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "This script takes in a Kaldi data dir, works out a segmentation for"
  echo "the audio and creates a new data directory for the segmentation."
  echo ""
  echo "Usage: $0 [options] <old-data-dir> <new-data-dir>"
  echo " e.g.: $0 data/recognize/radXXX data/recognize/radXXX_segm"
  echo ""
#  echo "Options:"
#  echo "    --min-seg-length        # minimum length of segments"
#  echo "    --min-sil-length        # minimum length of silence as split point"
  exit 1;
fi

datadir=$1
outdir=$2
mkdir -p $outdir

# Separate on new lines
IFS=$'\n'

for line in $(cat $datadir/wav.scp); do
    uttID=$(echo $line | cut -d" " -f1)
    audio=$(echo $line | awk '{print $(NF-1)}')
    filename=$(basename "$audio")
    extension="${filename##*.}"
    filename="${filename%.*}"

    echo "Extract the timestamps of silences in the audio and let each silence occupy one line in the file"
#     python3 -c "import shlex
# import subprocess
# process = subprocess.Popen(shlex.split('ffmpeg -i data/local/corpus/audio/rad20100216T155102.flac -af silencedetect=noise=-15dB:d=$min_sil_length -f null -'), stdout=subprocess.PIPE)
# ffmpegout=[]
# while True:
#     output = process.stdout.readline()
#     if output == '' and process.poll() is not None:
#         break
#     if output:
#         ffmpegout.append(output.strip())
# print('\n'.join(ffmpegout), file=ffmpeg.tmp)
# "
    ffmpeg -nostdin -i $audio -af silencedetect=noise=-15dB:d=$min_sil_length -f null - &>${outdir}/ffmpeg_out.tmp

    if grep -q "silencedetect" ${outdir}/ffmpeg_out.tmp; then
        grep "silence_start\|silence_end" ${outdir}/ffmpeg_out.tmp | awk 'ORS=NR%2?" ":"\n"' | cut -d" " -f4,5,9,10,12,13 > ${outdir}/${filename}_silence.txt
	
	
    	# Get total recording length, with 3 digits
    	total_dur=$(printf %.3f $(echo $(soxi -D $audio) | bc -l))
	
    	# Add uttID and total duration of the recording to the silence info file
    	awk -v id="$uttID" -v dur="$total_dur" '{print id, dur, $0}' ${outdir}/${filename}_silence.txt > ${outdir}/${filename}_silence2.tmp && mv ${outdir}/${filename}_silence2.tmp ${outdir}/${filename}_silence.txt
    	# When the audio ends in silence, the last line only contains the time when the silence starts.
    	# I fill out that line, so all lines contain 8 columns
    	num_col_last=$(tail -n1 ${outdir}/${filename}_silence.txt | wc -w)
    	if [ $num_col_last == 4 ]; then
    	    sil_start=$(awk 'END { print $NF }' ${outdir}/${filename}_silence.txt) 
    	    sil_dur=$(echo "$total_dur - $sil_start" | bc)
    	    sed -i -e "\$s/\(.*\)/\1 silence_end: $total_dur silence_duration: $sil_dur/" ${outdir}/${filename}_silence.txt
    	fi
	
    	# Used make_segmentation_data_dir.sh and create_segments_from_ctm.pl as bases for the segmentation step
    	echo "Make data dir with segmented audio"
    	local/make_audio_segmentation_data_dir.sh \
    	    --min-seg-length $min_seg_length \
    	    --min-sil-length $min_sil_length \
    	    ${outdir}/${filename}_silence.txt $datadir $outdir

    else
        echo "No silences observed. Keep speech as whole"
    	cp -r $datadir/* $outdir
    fi
    
    rm ${outdir}/ffmpeg_out.tmp
done
