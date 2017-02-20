#!/bin/bash -eu
#
# Icelandic LVCSR built for the Icelandic parliament using
# text and audio data from the parliament. The text data
# consists of two sets of files, the intermediate text
# and the final text
# More training examples in: kaldi/egs/{rm,wsj}/s5/run.sh
#
# 2016 Inga
#
# 

nj=20
nj_decode=32 
stage=-100
corpus_zip=~/data/althingi/tungutaekni.tar.gz
datadir=data/local/corpus

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

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
        error "Corpus doesn not have correct structure"
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

if [ $stage -le -1 ]; then
    
    echo "Converting corpus to datadir"
    
    # Note if take text norm out from prep data then text_bb_SpellingFixed.txt
    # must be called text for validate_data_dir.sh to work.
    local/prep_althingi_data.sh ${datadir} data/all

    echo "Text normalization: Expansion of abbreviations and numbers"
    # train a language model for expansion
    ./local/train_LM_forExpansion2.sh

    # Expand numbers and abbreviations
    ./local/expand2.sh

   # Combine with 2013-2016 data
    cat data/all/text_bb_expanded.txt data/all100/text >> data/all/text

    # Validate the data dir
    utils/validate_data_dir.sh --no-feats data/all || utils/fix_data_dir.sh data/all

    # Get ready to do things again with new data
    mv data/lang data/lang100
    mv exp/ exp100

fi

if [ $stage -le 13 ]; then
    # I can't train without segmenting the audio and text first
    # I use the recognizer trained on 60 hrs of data from althingi
    # to transcribe the audio so that I can align	
    echo "Re-segment the data using and in-domain recognizer"
    local/run_segmentation.sh data/all data/lang100 exp100/tri3_0.2 20161128

    echo "Analyze the segments and filter based on a words/sec ratio"
    local/words-per-second.sh data/all_reseg_20161128
    #local/wps_hist.py wps.txt
    local/wps_speakerDependent.py data/all_reseg_20161128
    # Use 5% percentiles
    local/filter_segments.sh data/all_reseg_20161128 data/all_reseg_20161128_filtered
    
    echo "Extracting features"
    steps/make_mfcc.sh \
        --nj $nj       \
        --mfcc-config conf/mfcc.conf \
        --cmd "$train_cmd"           \
        data/all_reseg_20161128_filtered exp/make_mfcc mfcc

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh \
        data/all_reseg_20161128_filtered exp/make_mfcc mfcc

fi
    
if [ $stage -le 14 ]; then

    echo "Splitting into a train, dev and eval set"
    # Use the data from the year 2016 as my test data
    grep "rad2016" data/all_reseg_20161128_filtered/utt2spk | cut -d" " -f1 > test_uttlist
    grep -v "rad2016" data/all_reseg_20161128_filtered/utt2spk | cut -d" " -f1 > train_uttlist
    subset_data_dir.sh --utt-list train_uttlist data/all_reseg_20161128_filtered data/train
    subset_data_dir.sh --utt-list test_uttlist data/all_reseg_20161128_filtered data/dev_eval
    rm test_uttlist train_uttlist

    # Randomly split the dev_eval set 
    shuf <(cut -d" " -f1 data/dev_eval/utt2spk) > tmp
    m=$(echo $(($(wc -l tmp | cut -d" " -f1)/2)))
    head -n $m tmp > out1 # uttlist 1
    tail -n +$(( m + 1 )) tmp > out2 # uttlist 2
    utils/subset_data_dir.sh --utt-list out1 data/dev_eval data/dev
    utils/subset_data_dir.sh --utt-list out2 data/dev_eval data/eval

fi


if [ $stage -le 15 ]; then
    echo "Lang preparation"

    # Found first which words were not in the pron dict and
    # Find words which appear more than three times in the Althingi data but not in the pron. dict
    cut -d" " -f2- data/train/text \
	| tr " " "\n" \
	| grep -v '[cqwzåäø]' \
	| sed '/[a-z]/!d' \
	| egrep -v '^\s*$' \
	| sort | uniq -c \
	| sort -k1 -n \
	| awk '$2 ~ /[[:print:]]/ { if($1 > 2) print $2 }' \
	> data/train/words_text3.txt
    comm -13 <(cut -f1 /data/malromur_models/current_pron_dict_20161005.txt | sort) \
	 <(sort data/train/words_text3.txt) > data/train/only_text_NOTlex.txt

    # Filter out bad words
    local/filter_by_letter_ngrams.py /data/malromur_models/current_pron_dict_20161005.txt data/train/only_text_NOTlex.txt
    local/filter_wordlist.py potential_not_valid_leipzig_malromur.txt
    mv no_pattern_match.txt potential_valid_althingi.txt
 
    # # This would probably have been fine but I decided to go through the output list from filter_by_letter_ngrams, called "potential_not_valid_leipzig_malromur.txt", clean it and add what I wanted to keep to the newly created "scraped_words_notPronDict_3_filtered.txt"
    # local/filter_non_ice_chars.py potential_not_valid_leipzig_malromur.txt
    # local/filter_wordlist.py potential_not_valid_leipzig_malromur.txt
    # join -1 1 -2 1 <(sort ice_words.txt) <(sort no_pattern_match.txt) > potential_words3.tmp # I ran through this list and cleaned it further by hand (ended in 3183 words)
    # cat potential_words3.tmp >> ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt
    # LC_ALL=C sort ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt > tmp \
    # 	&& mv tmp ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt
    rm cons_patterns.txt digit_patterns.txt foreign_words.txt ice_words.txt punct_patterns.txt potential_valid_leipzig_malromur.txt potential_not_valid_leipzig_malromur.txt

    echo "Transcribe using g2p"
    local/transcribe_g2p.sh data/local/g2p potential_valid_althingi.txt \
        > ~/data/althingi/pronDict_LM/transcribed_althingi_words.txt
    # Checked the transcription of the most common words

    # Althingi webcrawl data is already ready: transcribed_scraped_althingi_words3.txt
    
    # Combine with Anna's pronunciation dictionary
    cat /data/malromur_models/current_pron_dict_20161005.txt ~/data/althingi/pronDict_LM/transcribed_althingi_words.txt \
	~/data/althingi/pronDict_LM/transcribed_scraped_althingi_words3.txt \
	| LC_ALL=C sort | uniq > ~/data/althingi/pronDict_LM/pron_dict_20161205.txt

    mkdir -p data/local/dict
    frob=~/data/althingi/pronDict_LM/pron_dict_20161205.txt
    local/prep_lang.sh \
        $frob             \
        data/train         \
        data/local/dict     \
        data/lang

    # echo "Preparing bigram language model"
    # mkdir -p data/lang_bg
    # for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
    #                         topo words.txt; do
    #     [ ! -e data/lang_bg/$s ] && cp -r data/lang/$s data/lang_bg/$s
    # done
    
    # echo "Making lm.arpa"
    # local/make_arpa.sh --order 2 data/train data/lang_bg

    # echo "Making G.fst"
    # utils/format_lm.sh data/lang data/lang_bg/lm_bg.arpa.gz data/local/dict/lexicon.txt data/lang_bg

    # #local/prep_LM.sh --order 2 --lm_suffix bg data/train data/lang

    echo "Preparing trigram language model"
    mkdir -p data/lang_tg
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_tg/$s ] && cp -r data/lang/$s data/lang_tg/$s
    done

    echo "Making lm.arpa"
    # cat ~/data/althingi/pronDict_LM/t130_131_clean.txt <(cut -f2- data/train/text) > data/train/LMtext
    cat ~/data/althingi/pronDict_LM/t130_131_clean.txt <(cut -f2- data/train/text) > data/train/LMtext
    local/make_arpa.sh --order 3 data/train/LMtext data/lang_tg

    echo "Making G.fst"
    utils/format_lm.sh data/lang data/lang_tg/lm_tg.arpa.gz data/local/dict/lexicon.txt data/lang_tg

    # fstprint --{o,i}symbols=data/lang/words.txt data/lang_tg/G.fst | head
  
fi

if [ $stage -le 16 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"

    # Now make subset with 40000 utterances from train.
    utils/subset_data_dir.sh data/train 40000 data/train_40k

    # Now make subset with the shortest 5k utterances from train_40k.
    utils/subset_data_dir.sh --shortest data/train_40k 5000 data/train_5kshort

    # Now make subset with half of the data from train_40k.
    utils/subset_data_dir.sh data/train 20000 data/train_20k

    # Make one for the dev set so that I can get a quick estimate for the first training steps
    utils/subset_data_dir.sh data/dev 1000 data/dev_1k || exit 1;
fi

if [ $stage -le 16 ]; then
    echo "Training mono system"
    steps/train_mono.sh    \
        --nj $nj           \
        --cmd "$train_cmd" \
        --totgauss 4000    \
        data/train_5kshort \
        data/lang          \
        exp/mono

    echo "Creating decoding graph (trigram lm), monophone model"
    utils/mkgraph.sh       \
        --mono             \
        data/lang_tg        \
        exp/mono           \
        exp/mono/graph_tg

    echo "Decoding, monophone model, trigram LM"
    steps/decode.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/mono/graph_tg  \
	data/dev  \
	exp/mono/decode_tg_dev

    echo "Decode also the eval set"
    steps/decode.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/mono/graph_tg  \
	data/eval  \
	exp/mono/decode_tg_eval
fi

if [ $stage -le 17 ]; then
    echo "mono alignment. Align train_20k to mono"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train_20k data/lang exp/mono exp/mono_ali

    echo "first triphone training"
    steps/train_deltas.sh  \
        --cmd "$train_cmd" \
        2000 10000         \
        data/train_20k data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 18 ]; then

    echo "First triphone decoding"
    
    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri1      \
        exp/tri1/graph_tg

    echo "Decoding dev and eval sets with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri1/graph_tg \
        data/dev \
        exp/tri1/decode_tg_dev

    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri1/graph_tg \
        data/eval \
        exp/tri1/decode_tg_eval
    
fi

if [ $stage -le 19 ]; then
    echo "Aligning train_40k to tri1"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train_40k data/lang \
        exp/tri1 exp/tri1_ali

    #ATH What splice-opts to use?? Start with a total of 7 frames. Try maybe later 9 frames
    echo "Training LDA+MLLT system tri2"
    steps/train_lda_mllt.sh \
        --cmd "$train_cmd" \
	--splice-opts "--left-context=3 --right-context=3" \
        3000 25000 \
        data/train_40k \
        data/lang  \
        exp/tri1_ali \
        exp/tri2
	
fi

if [ $stage -le 20 ]; then
    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri2      \
        exp/tri2/graph_tg

    echo "Decoding dev and eval sets with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri2/graph_tg \
        data/dev \
        exp/tri2/decode_tg_dev

    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri2/graph_tg \
        data/eval \
        exp/tri2/decode_tg_eval
fi

if [ $stage -le 7 ]; then
    echo "Aligning train_40k to tri2"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train_40k data/lang \
        exp/tri2 exp/tri2_ali

fi

if [ $stage -le 21 ]; then

    # ATH which options to use??
    echo "From system 2 train tri3 which is LDA + MLLT + SAT"
    steps/train_sat.sh    \
        --cmd "$train_cmd" \
        4000 40000    \
        data/train_40k    \
        data/lang     \
        exp/tri2_ali   \
	exp/tri3

    echo "Creating decoding graph"
    utils/mkgraph.sh       \
        data/lang_tg          \
        exp/tri3           \
        exp/tri3/graph_tg

    # I can send three models into decode_fmllr.sh
    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3/graph_tg  \
	data/dev  \
	exp/tri3/decode_tg_dev & 

    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3/graph_tg  \
	data/eval  \
	exp/tri3/decode_tg_eval
fi

if [ $stage -le 22 ]; then
    echo "Aligning train to tri3"
    steps/align_fmllr.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train data/lang \
        exp/tri3 exp/tri3_ali

fi

f [ $stage -le 21 ]; then

    # ATH which options to use??
    echo "Train SAT again, now on the whole training set"
    steps/train_sat.sh    \
        --cmd "$train_cmd" \
        4000 40000    \
        data/train   \
        data/lang     \
        exp/tri3_ali   \
	exp/tri4

    echo "Creating decoding graph"
    utils/mkgraph.sh       \
        data/lang_tg          \
        exp/tri4           \
        exp/tri4/graph_tg

    # I can send three models into decode_fmllr.sh
    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri4/graph_tg  \
	data/dev  \
	exp/tri4/decode_tg_dev & 

    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri4/graph_tg  \
	data/eval  \
	exp/tri4/decode_tg_eval
fi

# Move the following into a shell script of its own. It is really computationally intensive
# if [ $stage -le 23 ]; then
#     echo "MMI on top of tri3 (i.e. LDA+MLLT+SAT+MMI)"
#     local/run_mmi_tri3.sh
# fi

# Try extending the LM and use an upgraded pronunctiation dictionary
if [ $stage -le 25 ]; then
    mkdir -p data/local/dict_bd
    frob=~/data/althingi/pronDict_LM/pron_dict_20161205.txt # I added single letters and fixed some errors
    local/prep_lang.sh \
        $frob             \
        data/train         \
        data/local/dict_bd     \
        data/lang_bd

    echo "Preparing a bigger trigram language model"
    mkdir -p data/lang_tg_bd
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_tg_bd/$s ] && cp -r data/lang_bd/$s data/lang_tg_bd/$s
    done

    echo "Making lm.arpa"
    # cat ~/data/althingi/pronDict_LM/t130_131_clean.txt <(cut -f2- data/train/text) > data/train/LMtext
    cat ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean.txt <(cut -f2- data/train/text) > data/train/LMtext_big
    local/make_arpa.sh --order 3 data/train/LMtext_big data/lang_tg_bd

    
    echo "Making G.fst"
    utils/format_lm.sh data/lang_bd data/lang_tg_bd/lm_tg.arpa.gz data/local/dict_bd/lexicon.txt data/lang_tg_bd

    echo "Make a 5g LM"
    mkdir -p data/lang_fg_bd
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_fg_bd/$s ] && cp -r data/lang_bd/$s data/lang_fg_bd/$s
    done
    # NOTE! Since I made the td file I seem to have renames LMtext_bd to LMtext
    local/make_arpa.sh --order 5 data/train/LMtext data/lang_fg_bd
    utils/slurm.pl data/lang_fg_bd/format_lm.log utils/format_lm.sh data/lang_bd data/lang_fg_bd/lm_fg.arpa.gz data/local/dict_bd/lexicon.txt data/lang_fg_bd
    
    echo "Trying the larger dictionary ('big-dict'/bd) + locally produced LM."
    utils/mkgraph.sh \
	data/lang_tg_bd \
        exp/tri3 \
	exp/tri3/graph_tg_bd

    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3/graph_tg_bd  \
	data/dev  \
	exp/tri3/decode_tg_bd_dev & 

    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3/graph_tg_bd \
	data/eval \
        exp/tri3/decode_tg_bd_eval
    
fi

if [ $stage -le 26 ]; then
    echo "Aligning train to tri3"
    steps/align_fmllr.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train data/lang_bd \
        exp/tri3 exp/tri3_ali_bd

fi

if [ $stage -le 27 ]; then
    echo "Clean and resegment the training data"
    steps/cleanup/clean_and_segment_data.sh \
        --stage 3 \
        --nj $nj_decode \
        --cmd "$decode_cmd" \
        data/train data/lang \
        exp/tri3 exp/tri3_cleanup \
        data/train_cleaned &
fi

if [ $stage -le 16 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"

    # Now make subset with 40000 utterances from train.
    utils/subset_data_dir.sh data/train_cleaned 50000 data/train_cleaned_90hrs

    # Now make subset with the shortest 5k utterances from train_40k.
    utils/subset_data_dir.sh --shortest data/train_cleaned_90hrs 10000 data/train_10kshort

    # Now make subset with half of the data from train_40k.
    utils/subset_data_dir.sh data/train_cleaned_90hrs 25000 data/train_cleaned_90hrs_half

    # Make one for the dev set so that I can get a quick estimate for the first training steps
    utils/subset_data_dir.sh data/dev 1000 data/dev_1k || exit 1;
fi

if [ $stage -le 16 ]; then
    echo "Training mono system"
    steps/train_mono.sh    \
        --nj $nj           \
        --cmd "$train_cmd" \
        --totgauss 4000    \
        data/train_10kshort \
        data/lang          \
        exp/mono_cleaned

    echo "Creating decoding graph (trigram lm), monophone model"
    utils/mkgraph.sh       \
        --mono             \
        data/lang_tg        \
        exp/mono_cleaned           \
        exp/mono_cleaned/graph_tg

    echo "mono alignment. Align train_20k to mono"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train_cleaned_90hrs_half data/lang exp/mono_cleaned exp/mono_cleaned_ali

    echo "first triphone training"
    steps/train_deltas.sh  \
        --cmd "$train_cmd" \
        2000 10000         \
        data/train_cleaned_90hrs_half data/lang exp/mono_cleaned_ali exp/tri1_cleaned

    echo "First triphone decoding"
    
    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri1_cleaned      \
        exp/tri1_cleaned/graph_tg

    echo "Decoding dev and eval sets with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri1_cleaned/graph_tg \
        data/dev \
        exp/tri1_cleaned/decode_tg_dev

    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train_cleaned_90hrs data/lang \
        exp/tri1_cleaned exp/tri1_cleaned_ali

    #ATH What splice-opts to use?? Start with a total of 7 frames. Try maybe later 9 frames
    echo "Training LDA+MLLT system tri2"
    steps/train_lda_mllt.sh \
        --cmd "$train_cmd" \
	--splice-opts "--left-context=3 --right-context=3" \
        3000 25000 \
        data/train_cleaned_90hrs \
        data/lang  \
        exp/tri1_cleaned_ali \
        exp/tri2_cleaned

    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri2_cleaned      \
        exp/tri2_cleaned/graph_tg

    echo "Decoding dev and eval sets with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri2_cleaned/graph_tg \
        data/dev \
        exp/tri2_cleaned/decode_tg_dev

    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri2_cleaned/graph_tg \
        data/eval \
        exp/tri2_cleaned/decode_tg_eval

    echo "Aligning train_40k to tri2"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train_cleaned_90hrs data/lang \
        exp/tri2_cleaned exp/tri2_cleaned_ali

    # ATH which options to use??
    echo "From system 2 train tri3 which is LDA + MLLT + SAT"
    steps/train_sat.sh    \
        --cmd "$train_cmd" \
        4000 40000    \
        data/train_cleaned_90hrs    \
        data/lang     \
        exp/tri2_cleaned_ali   \
	exp/tri3_cleaned

    echo "Creating decoding graph"
    utils/mkgraph.sh       \
        data/lang_tg          \
        exp/tri3_cleaned           \
        exp/tri3_cleaned/graph_tg

    # I can send three models into decode_fmllr.sh
    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3_cleaned/graph_tg  \
	data/dev  \
	exp/tri3_cleaned/decode_tg_dev & 

    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3_cleaned/graph_tg  \
	data/eval  \
	exp/tri3_cleaned/decode_tg_eval

    echo "Aligning train to tri3"
    steps/align_fmllr.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train_cleaned data/lang \
        exp/tri3_cleaned exp/tri3_cleaned_ali

    
    echo "Trying the larger dictionary ('big-dict'/bd) + locally produced LM."
    utils/mkgraph.sh \
	data/lang_tg_bd \
        exp/tri3_cleaned \
	exp/tri3_cleaned/graph_tg_bd

    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3_cleaned/graph_tg_bd  \
	data/dev  \
	exp/tri3_cleaned/decode_tg_bd_dev

    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3_cleaned/graph_tg_bd  \
	data/eval  \
	exp/tri3_cleaned/decode_tg_bd_eval
fi

# NNET
if [ $stage -le 28 ]; then
    echo "Run the main nnet2 recipe on top of fMLLR features"
    local/nnet2/run_5d.sh

    #echo "Run the main dnn recipe on top of fMLLR features"
    #local/nnet/run_dnn.sh &

    echo "Run the main tdnn recipe on top of fMLLR features"
    #local/nnet3/run_tdnn.sh
    echo "Use speed perturbations"
    local/nnet3/run_tdnn.sh  --train-set train --gmm tri3 --nnet3-affix "_sp" --stage 12 &>tdnn_stout.out &

    echo "Run the wsj lstm recipe without sp"
    local/nnet3/run_lstm_noSP.sh --stage 8 >>lstm_noSP_stout_Feb20.out 2>&1 &

    echo "Run the swbd lstm recipe with sp"
    local/nnet3/run_lstm.sh --stage 11 >>lstm_stout.out 2>&1 &
fi

# steps/make_mfcc.sh \
#     --nj $nj       \
#     --mfcc-config conf/mfcc.conf \
#     --cmd "$train_cmd"           \
#     data/dev exp/make_mfcc mfcc

# steps/compute_cmvn_stats.sh \
#     data/dev exp/make_mfcc mfcc

# steps/decode_fmllr.sh   \
#     --config conf/decode.config \
#     --nj $nj_decode   \
#     --cmd "$decode_cmd" \
#     exp/tri3_cleaned/graph_tg_bd  \
#     data/dev  \
#     exp/tri3_cleaned/decode_tg_bd_dev_cleaned

# steps/decode_fmllr.sh   \
#     --config conf/decode.config \
#     --nj $nj_decode   \
#     --cmd "$decode_cmd" \
#     exp/tri3/graph_tg_bd  \
#     data/dev  \
#     exp/tri3/decode_tg_bd_dev_cleaned
