#!/bin/bash -eu

# Prepare a directory on Kaldi format, containing audio data and some auxiliary info.

speech=$1
datadir=$2

stage=-1

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

# NOTE! Maybe I will be able to get name, ID and gender info from metadata. Check!
# Make name-id-gender file from metadata info.

name_id_file="data/local/corpus/name_id_gender.tsv"
meta="data/local/corpus/metadata.csv"

encoding=$(file -i ${meta} | cut -d" " -f3)
if [[ "$encoding" == "charset=iso-8859-1" ]]; then
    iconv -f ISO-8859-1 -t UTF-8 ${meta} > tmp && mv tmp ${meta}
fi

# NOTE! Could I get the audio files in wav format??
# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing
#wav_cmd="sox -tmp3 - -c1 -esigned -r$samplerate -G -twav - "
wav_cmd="sox -tflac - -c1 -esigned -twav - "

IFS=$'\n' # Split on new line

if [ $stage -le 0 ]; then

    # Extract the speaker info
    cut -d"," -f1,6 ${meta} | tr "," "\t" | grep "$speech" > ${datadir}/spkname_filename.tmp
    filename=$(cut -f2 ${datadir}/spkname_filename.tmp)
    spkname=$(cut -f1 ${datadir}/spkname_filename.tmp)
    spkID=$(grep $spkname ${name_id_file} | cut -f2)

    #echo "a) spk2gender" # I use the abbreviation of parliament members' names as speaker IDs
    #grep "$spkname" $name_id_file | cut -f2- > ${datadir}/spk2gender
 
    echo "a) utt2spk" # Connect each speech ID to a speaker ID.
    printf "%s %s\n" ${spkID}-${filename} ${spkID} | tr -d $'\r' > ${datadir}/utt2spk

    # Make a helper file with mapping between the filenames and uttID
    echo -e ${filename} ${spkID}-${filename} | tr -d $'\r' | LC_ALL=C sort -n > ${datadir}/filename_uttID.txt
    
    echo "b) wav.scp" # Connect every speech ID with an audio file location.
    #echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f data/local/corpus/audio/${filename}".mp3")" |" | tr -d $'\r' >> ${datadir}/wav.scp
    echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f data/local/corpus/audio/${filename}".flac")" |" | tr -d $'\r' > ${datadir}/wav.scp
    rm ${datadir}/spkname_filename.tmp

    echo "c) spk2utt"
    utils/utt2spk_to_spk2utt.pl < ${datadir}/utt2spk > ${datadir}/spk2utt
fi

if [ $stage -le 1 ]; then
    echo "Extracting features"
    steps/make_mfcc.sh \
	--nj 1 \
	--mfcc-config conf/mfcc.conf \
	--cmd "$train_cmd"           \
	${datadir} || exit 1;

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh ${datadir} || exit 1;
fi

if [ $stage -le 2 ]; then
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-text ${datadir} || utils/fix_data_dir.sh ${datadir}
fi

IFS=$' \t\n'
exit 0

