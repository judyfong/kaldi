#!/bin/bash
#
# The script contains the steps taken to train an
# Icelandic LVCSR built for the Icelandic parliament using
# text and audio data from the parliament. The text data
# provided consists of two sets of files, the intermediate text
# and the final text. The text needs to be normalized and
# and audio and text has to be aligned and segmented before
# training.
#
# Those that got already segmented data need to create kaldi files
# done in the first part of prep_althingi_data.sh and can just go to
# stage 15
#
# 2016 Reykjavík University (Inga Rún Helgadóttir)
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

fi

if [ $stage -le -1 ]; then
    
    echo "Make Kaldi data files, do initial text normalization and clean spelling errors in the text"
    local/prep_althingi_data.sh ${datadir} data/all

    echo "Text normalization: Expansion of abbreviations and numbers"
    # train a language model for expansion
    ./local/train_LM_forExpansion2.sh

    # Expand numbers and abbreviations
    ./local/expand2.sh

    # Validate the data dir
    utils/validate_data_dir.sh --no-feats data/all || utils/fix_data_dir.sh data/all

fi

if [ $stage -le -13 ]; then
    
    info "Make the texts case sensitive (althingi and LM training text)"

    # I went through capitalized words in the original Málföng's pron dict
    # and corrected words that were incorrectly capitalized. I used the resulting
    # list, as well as a list of capitalized words in BÍN and lists over countries
    # and capitals to capitalize my pron dict. I used it to capitalize my texts.
    
    # Capitalize words in Althingi texts, that are capitalized in the pron dict

    # Extract proper nouns from the althingi texts, which have to be capitalized
    comm -12 <(sed -e 's/\(.*\)/\L\1/' propernouns/CaseSensitive_pron_dict_propernouns.txt | sort) <(cut -d" " -f2- ~/kaldi/egs/althingi/s5/data/all/text | tr " " "\n" | grep -Ev "^\s*$" | sort -u ) > propernouns/propernouns_althingi.txt
    # Make the regex pattern
    tr "\n" "|" < propernouns/propernouns_althingi.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > propernouns/propernouns_althingi_pattern.tmp

    # Capitalize
    srun --mem 8G sed -e 's/\(\b'$(cat propernouns/propernouns_althingi_pattern.tmp)'\b\)/\u\1/g' ~/kaldi/egs/althingi/s5/data/all/text > ~/kaldi/egs/althingi/s5/data/all/text_CaseSens.txt

    # Capitalize words in the scraped Althingi texts, that are capitalized in the pron dict
    comm -12 <(sed -e 's/\(.*\)/\L\1/' propernouns/CaseSensitive_pron_dict_propernouns.txt | sort) <(tr " " "\n" < scrapedAlthingiTexts_clean.txt | grep -Ev "^\s*$" | sort -u) > propernouns/propernouns_scraped_althingi_texts.txt
    # Make the regex pattern
    tr "\n" "|" < propernouns/propernouns_scraped_althingi_texts.txt | sed -e '$s/|$//' | sed -e '$a\' | perl -pe "s/\|/\\\b\\\|\\\b/g" | sed -e 's/\(.*\)/\L\1/' > propernouns/propernouns_scraped_althingi_texts_pattern.tmp

    # Capitalize
    srun --mem 8G sed -e 's/\(\b'$(cat propernouns/propernouns_scraped_althingi_texts_pattern.tmp)'\b\)/\u\1/g' scrapedAlthingiTexts_clean.txt > scrapedAlthingiTexts_clean_CaseSens.txt

    # Combine into a new case sensitive LM training sample
    cat scrapedAlthingiTexts_clean_CaseSens.txt <(grep -v rad2016 ~/kaldi/egs/althingi/s5/data/all/texts2005to15_CaseSens.txt | cut -d" " -f2-) > LMtexts_CaseSens.txt

    # Make the CS text be the main text
    mv data/all/text data/all/LCtext
    mv data/all/text_CaseSens.txt data/all/text
fi

if [ $stage -le 14 ]; then
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
    
if [ $stage -le 15 ]; then

    echo "Splitting into a train, dev and eval set"
    # Ideal would have been to hold back a little of the training data, called f.ex. train-dev
    # to use for bias estimation. Then have a dev/eval set to check the decoding on and finally
    # have a test set that is never touched, until in the end. In the following I did not do that.
    
    # Use the data from the year 2016 as my eval data
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

     echo "Make a 4g LM"
    mkdir -p data/lang_4g_bd
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_4g_bd/$s ] && cp -r data/lang_bd/$s data/lang_4g_bd/$s
    done
    # NOTE! Since I made the td file I seem to have renames LMtext_bd to LMtext
    local/make_arpa.sh --order 4 data/train/LMtext data/lang_4g_bd
    utils/slurm.pl data/lang_4g_bd/format_lm.log utils/format_lm.sh data/lang_bd data/lang_4g_bd/lm_4g.arpa.gz data/local/dict_bd/lexicon.txt data/lang_4g_bd
    
    echo "Make a 5g LM"
    mkdir -p data/lang_fg_bd
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_fg_bd/$s ] && cp -r data/lang_bd/$s data/lang_fg_bd/$s
    done
    # NOTE! Since I made the td file I seem to have renames LMtext_bd to LMtext
    local/make_arpa.sh --order 5 data/train/LMtext data/lang_fg_bd
    utils/slurm.pl data/lang_fg_bd/format_lm.log utils/format_lm.sh data/lang_bd data/lang_fg_bd/lm_fg.arpa.gz data/local/dict_bd/lexicon.txt data/lang_fg_bd


    echo "Preparing bigram language model"
    mkdir -p data/lang_bg_bd
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_bg_bd/$s ] && cp -r data/lang_bd/$s data/lang_bg_bd/$s
    done
    
    echo "Making lm.arpa"
    local/make_arpa.sh --order 2 data/train/LMtext data/lang_bg_bd

    echo "Making G.fst"
    utils/format_lm.sh data/lang_bd data/lang_bg_bd/lm_bg.arpa.gz data/local/dict/lexicon.txt data/lang_bg_bd

    ########################

    echo "pruned 3g LM"
    mkdir -p data/lang_tg_bd_023pruned
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_tg_bd_023pruned/$s ] && cp -r data/lang_bd/$s data/lang_tg_bd_023pruned/$s
    done

    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
        -o 3 -S 70% --prune 0 2 3 \
        --text data/train/LMtext \
        --limit_vocab_file <(cat data/lang_tg_bd_023pruned/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
        | gzip -c > data/lang_tg_bd_023pruned/kenlm_3g.arpa_023pruned.gz

    utils/slurm.pl data/lang_tg_bd_023pruned/format_lm.log utils/format_lm.sh data/lang_bd data/lang_tg_bd_023pruned/kenlm_tg.arpa.gz data/local/dict_bd/lexicon.txt data/lang_tg_bd_023pruned

    echo "4-gram"
    mkdir -p data/lang_4g_3march
    for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                            topo words.txt; do
        [ ! -e data/lang_4g_3march/$s ] && cp -r data/lang_bd/$s data/lang_4g_3march/$s
    done  
    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
        -o 4 -S 70% --prune 0 0 0 1 \
        --text data/train/LMtext \
        --limit_vocab_file <(cat data/lang_4g_3march/words.txt | egrep -v "<eps>|<unk>" | cut -d' ' -f1) \
        | gzip -c > data/lang_4g_3march/kenlm_4g.arpa.gz

    utils/slurm.pl data/lang_4g_3march/format_lm.log utils/format_lm.sh data/lang_bd data/lang_4g_3march/kenlm_4g.arpa.gz data/local/dict_bd/lexicon.txt data/lang_4g_3march
	
    ########################

    
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

    echo "Run the main tdnn recipe on top of fMLLR features"
    #local/nnet3/run_tdnn.sh
    echo "Use speed perturbations"
    local/nnet3/run_tdnn.sh  --train-set train --gmm tri3 --nnet3-affix "_sp" --stage 12 &>tdnn_stout.out &

    # echo "Run the wsj lstm recipe without sp"
    # local/nnet3/run_lstm_noSP.sh --stage 8 >>lstm_noSP_stout_Feb20.out 2>&1 &

    # echo "Run the swbd lstm recipe with sp"
    # local/nnet3/run_lstm.sh --stage 11 >>lstm_stout.out 2>&1 &

    echo "Run the swbd lstm recipe without sp"
    local/nnet3/run_lstm.sh --stage 13 --speed-perturb false >>lstm_stout_Feb24.out 2>&1 &

    echo "Run the swbd chain tdnn_lstm recipe without sp"
    local/chain/run_tdnn_lstm.sh --stage 12 --speed-perturb false >>tdnn_lstm_March31.out 2>&1 &

    echo "Run the swbd chain tdnn_lstm recipe with sp"
    local/chain/run_tdnn_lstm.sh --stage 15 >>exp/chain/tdnn_lstm_1e_sp/tdnn_lstm_April26.out 2>&1 &
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

# steps/decode_fmllr.sh   \
#     --config conf/decode.config \
#     --si-dir exp/tri3/decode_bg_bd_eval_cleaned.si \
#     --stage 3 \
#     --nj 59 \
#     --cmd "$decode_cmd" \
#     exp/tri3/graph_bg_bd  \
#     data/eval  \
#     exp/tri3/decode_bg_bd_eval_cleaned &

# Case sensitive graph for chain model:
#utils/slurm.pl --mem 4G mkgraph_cs.log utils/mkgraph.sh --self-loop-scale 1.0 data/lang_3g_cs_023pruned exp/chain/tdnn_lstm_1e exp/chain/tdnn_lstm_1e/graph_3g_cs_023pruned &

################

# I want to see if I have bias and variance in my data. Hence I'm going to decode a subset of my training data,
# using my normal lstm model and the chain tdnn-lstm model and compare with the dev/eval WER rates.
#utils/subset_data_dir.sh data/train 7000 data/train_7k
. ./path.sh
. ./cmd.sh
datadir=data/train_cs_40uttperspk
utils/subset_data_dir.sh --per-spk data/train_cs 40 ${datadir}
num_jobs=64
echo "Create high resolution MFCC features"
utils/copy_data_dir.sh ${datadir} ${datadir}_hires
steps/make_mfcc.sh \
    --nj $num_jobs --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd" ${datadir}_hires || exit 1;
steps/compute_cmvn_stats.sh ${datadir}_hires || exit 1;
utils/fix_data_dir.sh ${datadir}_hires

echo "Extracting iVectors"
mkdir -p ${datadir}_hires/ivectors_hires
steps/online/nnet2/extract_ivectors_online.sh \
    --cmd "$train_cmd" --nj $num_jobs \
    ${datadir}_hires exp/chain/extractor \
    ${datadir}_hires/ivectors_hires || exit 1;

# Normal lstm decoding
graph_dir=exp/tri3/graph_3g_cs_023pruned #exp/tri4_cs/graph_3g_023pruned
chunk_width=20
chunk_left_context=40
chunk_right_context=0
if [ -z $extra_left_context ]; then
    extra_left_context=$chunk_left_context
fi
if [ -z $extra_right_context ]; then
    extra_right_context=$chunk_right_context
fi
if [ -z $frames_per_chunk ]; then
    frames_per_chunk=$chunk_width
fi

steps/nnet3/decode.sh \
    --nj $num_jobs --cmd "$decode_cmd" \
    --extra-left-context $extra_left_context  \
    --extra-right-context $extra_right_context  \
    --frames-per-chunk "$frames_per_chunk" \
    --online-ivector-dir ${datadir}_hires/ivectors_hires \
    $graph_dir ${datadir}_hires exp/nnet3/lstm_ld5/decode_train7k_3g_cs_023pruned || exit 1;
steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" \
    data/lang_3g_cs_023pruned \
    data/lang_5g_cs_const ${datadir}_hires \
    exp/nnet3/lstm_ld5/decode_train7k_3g_cs_023pruned \
    exp/nnet3/lstm_ld5/decode_train7k_5g_cs || exit 1;

# "Chain" model decoding, tdnn-lstm model
dir=exp/chain/tdnn_lstm_1e
graph_dir=$dir/graph_3g_cs_023pruned
extra_left_context=50
extra_right_context=0
frames_per_chunk_primary=140
steps/nnet3/decode.sh \
    --num-threads 4 \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --nj $num_jobs --cmd "$decode_cmd" \
    --extra-left-context $extra_left_context  \
    --extra-right-context $extra_right_context  \
    --extra-left-context-initial 0 \
    --extra-right-context-final 0 \
    --frames-per-chunk "$frames_per_chunk_primary" \
    --online-ivector-dir ${datadir}_hires/ivectors_hires \
    $graph_dir ${datadir}_hires \
    $dir/decode_train7k_3g_cs_023pruned || exit 1;
steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" \
    data/lang_3g_cs_023pruned data/lang_5g_cs_const ${datadir}_hires \
    $dir/decode_train7k_3g_cs_023pruned $dir/decode_train7k_5g_cs || exit 1;
