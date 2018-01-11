#!/bin/bash -eu

#This script assumes this is a fresh install of the repo

#decode_install_dir=./decodeinstall
#decode_zip=./decodeinstall.tar.gz

#echo "Extracting necessary decoding files"
#[ -f $decode_zip ] || error "$decode_zip not a file"
#mkdir -p ${decode_install_dir}
#tar -zxvf $corpus_zip --directory ${decode_install_dir}/

. path.sh

stage=-1
#corpus_zip=./decodeinstall/tungutaekni.tar.gz
# The corpora is in /data/althingi/{corpus_nov2016,corpus_sept2017,corpus_okt2017}

#datadir=/data/althingi

display_usage() { 
    echo -e "Usage:\n$0 \
             \n\nSets up a version of the Althingi kaldi ASR for decoding, \n\
             using audio metadata for speeches before 2017 and existing \n\
             models.\n" 
} 
if [[ ( $1 == "--help") ||  $1 == "-h" ]] 
then 
    display_usage
    exit 0
fi

ln -sfn ../../wsj/s5/utils utils
ln -sfn ../../wsj/s5/steps steps
ln -sfn $KALDI_ROOT/egs/althingi/s5/punctuator2/theano-env/bin punctuator2/theano-env/local/bin
ln -sfn $KALDI_ROOT/egs/althingi/s5/punctuator2/theano-env/include punctuator2/theano-env/local/include
ln -sfn $KALDI_ROOT/egs/althingi/s5/punctuator2/theano-env/lib punctuator2/theano-env/local/lib

#Make folders if they don't exist

#Chain LSTM model
cp -r decodeinstall/exp  exp
#exp/chain/tdnn_lstm_1e_sp/graph_3gsmall
#exp/chain/tdnn_lstm_1e_sp/lang_3gsmall
#exp/chain/tdnn_lstm_1e_sp/lang_5g
#exp/chain/tdnn_lstm_1e_sp/final.mdl
#exp/chain/tdnn_lstm_1e_sp/final.ie.id
#exp/chain/tdnn_lstm_1e_sp/cmvn_opts
#exp/chain/tdnn_lstm_1e_sp/frame_subsampling_factor
cp -r decodeinstall/data data
#data/lang_3gsmall
#data/lang_5g

#Assuming that the LMs etc have been saved to decodeinstall
#Copy the files to the correct locations as dictated by the recognize.sh script
#Temporary ABBREVIATE measure until the version controlled fst is no longer corrupt
cp -r decodeinstall/text_norm/ABBREVIATE.fst text_norm/ABBREVIATE.fst
cp -r decodeinstall/punctuator2 punctuator2

#cp decodeinstall/lang_bd data/lang_bd
#cp decodeinstall/lang_tg_bd_023pruned data/lang_tg_bd_023pruned
#cp decodeinstall/graph_tg_bd_023pruned exp/tri3/graph_tg_bd_023pruned

#LSTM model
#mkdir data
#mkdir -p exp/tri3
#mkdir -p exp/nnet3/lstm_ld5
#cp -r decodeinstall/LSTMmodel/final.mdl exp/nnet3/lstm_ld5/final.mdl
#cp decodeinstall/LSTMmodel/final.ie.id exp/nnet3/lstm_ld5/final.ie.id
#cp decodeinstall/LSTMmodel/cmvn_opts exp/nnet3/lstm_ld5/cmvn_opts
#cp decodeinstall/LSTMmodel/combined.mdl exp/nnet3/lstm_ld5/combined.mdl
#cp -r decodeinstall/LSTMmodel/extractor exp/nnet3/extractor
#cp decodeinstall/LSTMmodel/lang_cs data/lang_cs 
#cp decodeinstall/LSTMmodel/graph_3g_cs_023pruned exp/tri3/graph_3g_cs_023pruned 
#cp decodeinstall/LSTMmodel/lang_3g_cs_023pruned data/lang_3g_cs_023pruned  
#cp decodeinstall/LSTMmodel/lang_5g_cs data/lang_5g_cs  


#?? Also needed??
#   data/dev  
#	exp/tri3/decode_tg_bd_dev
#	data/eval \
#        exp/tri3/decode_tg_bd_eval

#Extracts audio files, metadata.csv and makes the name_id_gender.tsv file
if [ $stage -le -0 ]; then
    echo "Extracting corpus"
    [ -f $corpus_zip ] || error "$corpus_zip not a file"
    mkdir -p ${datadir}
    tar -zxvf $corpus_zip --directory ${datadir}/
    mv ${datadir}/2016/* ${datadir}/
    rm -r ${datadir}/2016
    # validate
    if ! [[ -d ${datadir}/audio && \
		  -d ${datadir}/text_bb && \
		  -d ${datadir}/text_endanlegt && \
		  -f ${datadir}/metadata.csv ]]; then
        error "Corpus does not have correct structure"
    fi
    encoding=$(file -i ${datadir}/metadata.csv | cut -d" " -f3)
    if [[ "$encoding"=="charset=iso-8859-1" ]]; then
	iconv -f ISO-8859-1 -t UTF-8 ${datadir}/metadata.csv > tmp && mv tmp ${datadir}/metadata.csv
    fi

    # Make a name-id-gender file (remember to remove the carriage return):
    # NOTE! Categorize those with family names as male
    cut -d"," -f1 ${datadir}/metadata.csv | sort -u > ${datadir}/name.tmp
    IFS=$'\n'
    for name in $(cat ${datadir}/name.tmp); do
	speech=$(grep -m 1 $name ${datadir}/metadata.csv | cut -d"," -f6 | tr -d '\r')
	id=$(perl -ne 'print "$1\n" if /\bskst=\"([^\"]+)/' ${datadir}/text_endanlegt/${speech}.xml)
	last=$((${#name}-6))
	if [ "${name:$last:6}" == "dóttir" ]; then
	    gender="f"
	else
	    gender="m"
	fi
	echo -e $name'\t'$(echo $id | cut -d" " -f1)'\t'$gender >> ${datadir}/name_id_gender.tsv
    done
    rm ${datadir}/name.tmp
fi

python nltkdownload.py

echo "One of the audio files aborts due to bad silences at the segment audio data step i.e. rad20101012T154111.mp3"
