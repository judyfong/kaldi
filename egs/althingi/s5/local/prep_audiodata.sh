#!/bin/bash -eu

# Prepare a directory on Kaldi format, containing audio data and some auxiliary info.

datadir=$1
#destdir=$2
#mkdir -p ${destdir}

stage=-1
nj=1

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

if ! [[ $n_files > 0 ]]; then
    error "$audio_zip didn't contain audio files"
fi

encoding=$(file -i ${datadir}/metadata.csv | cut -d" " -f3)
if [[ "$encoding"=="charset=iso-8859-1" ]]; then
    iconv -f ISO-8859-1 -t UTF-8 ${datadir}/metadata.csv > tmp && mv tmp ${datadir}/metadata.csv
fi

# NOTE! Maybe I will be able to get name, ID and gender info from metadata. Check!
# Make name-id-gender file from metadata info.

name_id_file=${datadir}/name_id_gender.tsv
meta=${datadir}/metadata.csv

# NOTE! Could I get the audio files in wav format??
# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing
wav_cmd="sox -tmp3 - -c1 -esigned -r$samplerate -G -twav - "
#wav_cmd="sox -tflac - -c1 -esigned -twav - "

if [ $stage -le 0 ]; then
    
    echo "a) spk2gender" # I use the abbreviation of parliament members' names as speaker IDs
    cut -f2- $name_id_file > ${datadir}/spk2gender

    echo "b) utt2spk" # Connect each utterance to a speaker.
    echo "c) wav.scp" # Connect every utterance with an audio file
    cut -d"," -f1,6 ${meta} | tr "," "\t" | LC_ALL=C sort > spkname_filename.tmp

    rm ${datadir}/utt2spk ${datadir}/filename_uttID.txt ${datadir}/wav.scp
    IFS=$'\n' # Want to separate on new lines
    for line in $(cat spkname_filename.tmp)
    do
	filename=$(echo $line | cut -f2)
	spkname=$(echo $line | cut -f1)
	spkID=$(grep $spkname ${name_id_file} | cut -f2)

	# Print to utt2spk
	printf "%s %s\n" ${spkID}-${filename} ${spkID} | tr -d $'\r' >> ${datadir}/utt2spk

	# Make a helper file with mapping between the filenames and uttID
	echo -e ${filename} ${spkID}-${filename} | tr -d $'\r' | LC_ALL=C sort -n >> ${datadir}/filename_uttID.txt
	
	#Print to wav.scp
	echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f ${datadir}/audio/${filename}".mp3")" |" | tr -d $'\r' >> ${datadir}/wav.scp
	#echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f ${datadir}/audio/${filename}".flac")" |" | tr -d $'\r' >> ${datadir}/wav.scp
    done
    rm spkname_filename.tmp

    echo "d) spk2utt"
    utils/utt2spk_to_spk2utt.pl < ${datadir}/utt2spk > ${datadir}/spk2utt
fi

if [ $stage -le 1 ]; then
    echo "Extracting features"
    steps/make_mfcc.sh \
	--nj $num_jobs      \
	--mfcc-config conf/mfcc.conf \
	--cmd "$train_cmd"           \
	${datadir} || exit 1;

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh \
	${datadir} || exit 1;
fi

if [ $stage -le 2 ]; then
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-text ${datadir} || utils/fix_data_dir.sh ${datadir}
fi

IFS=$' \t\n'
exit 0

