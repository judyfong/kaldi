#!/bin/bash -eu

# Prepare a directory on Kaldi format, containing audio data and some auxiliary info.

stage=-1

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

speechname=$1
ext=$2
meta=$3
datadir=$4

encoding=$(file -i ${meta} | cut -d" " -f3)
if [[ "$encoding" == "charset=iso-8859-1" ]]; then
    iconv -f ISO-8859-1 -t UTF-8 ${meta} > tmp && mv tmp ${meta}
fi

# NOTE! Could I get the audio files in wav format??
# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing
wav_cmd="sox -t$ext - -c1 -esigned -r$samplerate -G -twav - "
#wav_cmd="sox -tflac - -c1 -esigned -twav - "

IFS=$'\n' # Split on new line

if [ $stage -le 0 ]; then

    # Extract the speaker info (when using old speeches)
    grep "$speechname" ${meta} | tr "," "\t" > ${datadir}/spkname_speechname.tmp
    spkID=$(cut -f1 ${datadir}/spkname_speechname.tmp | perl -pe 's/[ \.]//g')

    # Extract the speaker info (to use with new speeches). What will be the format of the new meta files? F.ex. comma separated with speakers name in 1st col?
    #spkID=$(cut -f1 ${meta} | perl -pe 's/[ \.]//g')
    
    echo "a) utt2spk" # Connect each speech ID to a speaker ID.
    printf "%s %s\n" ${spkID}-${speechname} ${spkID} | tr -d $'\r' > ${datadir}/utt2spk

    # Make a helper file with mapping between the speechnames and uttID
    echo -e ${speechname} ${spkID}-${speechname} | tr -d $'\r' | LC_ALL=C sort -n > ${datadir}/speechname_uttID.tmp
    
    echo "b) wav.scp" # Connect every speech ID with an audio file location.
    echo -e ${spkID}-${speechname} $wav_cmd" < "$(readlink -f recognize/${speechname}".$ext")" |" | tr -d $'\r' > ${datadir}/wav.scp
    #echo -e ${spkID}-${speechname} $wav_cmd" < "$(readlink -f data/local/corpus/audio/${speechname}".flac")" |" | tr -d $'\r' > ${datadir}/wav.scp
    rm ${datadir}/spkname_speechname.tmp ${datadir}/speechname_uttID.tmp

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

