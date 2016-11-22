#!/bin/bash -eu
#
# Icelandic LVCSR built using open/freely accessible data
#
# 2016 Inga but mostly stuff from Robert Kjaran
#

nj=20
nj_decode=30 # 30 Usually I would use a high number but I only have 3 speakers in my dev set now
stage=-100
corpus_zip=~/data/althingi/tungutaekni.tar.gz
datadir=data/local/corpus

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

if [ $stage -le -1 ]; then
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

    # NOTE! I manually add the gender column
fi

if [ $stage -le -1 ]; then
    
    echo "Converting corpus to datadir"
    echo "Text normalization: Expansion of abbreviations and numbers"
    # Note if take text norm out from prep data then text_no_puncts.txt
    # must be called text for validate_data_dir.sh to work.
    local/prep_althingi_data.sh ${datadir} data/all

    # I can't train without segmenting the audio and text first
    # I use a preliminary ASR from Anna to transcribe the audio
    # so that I can align
    echo "Make segmentations"
    local/run_segmentation.sh data/all malromur/lang malromur

    echo "Analyze the segments and filter based on a words/sec ratio"
    mkdir data/all_reseg_filtered
    cp data/all_reseg/* data/all_reseg_filtered
    local/words-per-second.sh data/all_reseg
    #local/wps_hist.py wps.txt
    local/wps_speakerDependent.py data/all_reseg
    # Use 5% percentiles
    local/filter_segments.sh data/all_reseg data/all_reseg_filtered
    
    echo "Extracting features"
    steps/make_mfcc.sh \
        --nj $nj       \
        --mfcc-config conf/mfcc.conf \
        --cmd "$train_cmd"           \
        data/all_reseg_filtered exp/make_mfcc mfcc

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh \
        data/all_reseg_filtered exp/make_mfcc mfcc

fi
    
if [ $stage -le 0 ]; then   
    echo "Splitting into a train, dev and test set"
    echo "Making a small recognizer to split the data up again and include more data"
    utils/subset_data_dir_tr_cv.sh \
        --cv-utt-percent 5        \
        data/{all_reseg_filtered,train,dev_tmp}

    utils/subset_data_dir_tr_cv.sh \
        --cv-utt-percent 50        \
        data/{dev_tmp,dev,test}
fi

if [ $stage -le 1 ]; then
    echo "Lang preparation"

        # I want to use the utterances from the Althingi webcrawl in the language model and in the pronunciation dictionary
    local/prep_scrapedAlthingiData.sh ~/data/althingi/pronDict_LM/wp_lang.txt ~/data/althingi/scrapedAlthingiTexts_clean.txt
    

    # Found first which words were not in the pron dict and
    # Find words which appear more than three times in the Althingi data but not in the pron. dict
    cut -d" " -f2- data/all/text \
	| tr " " "\n" \
	| grep -v '[cqwzåäø]' \
	| sed '/[a-z]/!d' \
	| egrep -v '^\s*$' \
	| sort | uniq -c \
	| sort -k1 -n \
	| awk '$2 ~ /[[:print:]]/ { if($1 > 2) print $2 }' \
	> data/all/words_text3.txt
    comm -13 <(cut -f1 ~/data/current_pron_dict_20161005.txt | sort) \
	 <(sort data/all/words_text3.txt) > data/all/only_text_NOTlex.txt
    # Removed acronyms > 1165 words. # ATH done by hand. NOTE!
    mkdir -p data/local/dict

    echo "Transcribe using g2p"
    local/transcribe_g2p.sh data/local/g2p data/all/only_text_NOTlex.txt \
        > ~/data/althingi/pronDict_LM/transcribed_althingi_words.txt
    # Checked the transcription of the most common words

    # Combine with Anna's pronunciation dictionary
    cat ~/data/althingi/pronDict_LM/current_pron_dict_20161005.txt ~/data/althingi/pronDict_LM/transcribed_althingi_words.txt \
	| LC_ALL=C sort | uniq > ~/data/althingi/pronDict_LM/pron_dict_20161005_plusAlthingi.txt
    
    # Add also words from the scraped Althingi texts
    # Use scripts from Anna to validate the words
    tr " " "\n" < ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean.txt \
	| grep -v '[cqwzåäø]' \
	| sed '/[a-z]/!d' \
	| egrep -v '^\s*$' \
	| sort | uniq -c \
	| sort -k1 -n \
	| awk '$2 ~ /[[:print:]]/ { if($1 > 2) print $2 }' \
	      > ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean_words3.txt
    comm -13 <(cut -f1 ~/data/althingi/pronDict_LM/pron_dict_20161005_plusAlthingi.txt | sort) \
	 <(sort ~/data/althingi/scrapedAlthingiTexts_clean_words3.txt) > ~/data/althingi/scrapedAlthingiTexts_clean_words3.txt

    # Filter out bad words
    local/filter_by_letter_ngrams.py ~/data/althingi/pronDict_LM/pron_dict_20161005_plusAlthingi.txt ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3.txt
    local/filter_non_ice_chars.py potential_valid_leipzig_malromur.txt
    local/filter_wordlist.py potential_valid_leipzig_malromur.txt
    join -1 1 -2 1 <(sort potential_valid_leipzig_malromur.txt) <(sort ice_words.txt) > tmp
    join -1 1 -2 1 <(sort tmp) <(sort no_pattern_match.txt) > ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt

    # # This would probably have been fine but I decided to go through the output list from filter_by_letter_ngrams, called "potential_not_valid_leipzig_malromur.txt", clean it and add what I wanted to keep to the newly created "scraped_words_notPronDict_3_filtered.txt"
    # local/filter_non_ice_chars.py potential_not_valid_leipzig_malromur.txt
    # local/filter_wordlist.py potential_not_valid_leipzig_malromur.txt
    # join -1 1 -2 1 <(sort ice_words.txt) <(sort no_pattern_match.txt) > potential_words3.tmp # I ran through this list and cleaned it further by hand (ended in 5509 words)
    # cat potential_words3.tmp >> ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt
    # LC_ALL=C sort ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt > tmp \
    # 	&& mv tmp ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt

    echo "Transcribe using g2p"
    local/transcribe_g2p.sh data/local/g2p ~/data/althingi/pronDict_LM/scraped_words_notPronDict_3_filtered.txt > ~/data/althingi/pronDict_LM/transcribed_scraped_althingi_words3.txt
    
    # Combine with Anna's pronunciation dictionary
    cat ~/data/althingi/pronDict_LM/transcribed_scraped_althingi_words3.txt ~/data/althingi/pronDict_LM/pron_dict_20161005_plusAlthingi.txt \
	| LC_ALL=C sort | uniq > ~/data/althingi/pronDict_LM/pron_dict_20161005_dataAll_scraped.txt

    frob=~/data/althingi/pronDict_LM/pron_dict_20161005_dataAll_scraped.txt
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
    cat ~/data/althingi/pronDict_LM/scrapedAlthingiTexts_clean.txt <(cut -f2- data/train/text) > data/train/LMtext 
    local/make_arpa.sh --order 3 data/train/LMtext data/lang_tg

    echo "Making G.fst"
    utils/format_lm.sh data/lang data/lang_tg/lm_tg.arpa.gz data/local/dict/lexicon.txt data/lang_tg

    # fstprint --{o,i}symbols=data/lang/words.txt data/lang_tg/G.fst | head
  
fi

# I don't think neither silence probabilities nor pronunciation
# probabilities are included. ATH!
# I can add pronunciation probabilities using
# steps/get_prons.sh and utils/dict_dir_add_pronprobs.sh.
# I would have to run prepare_lang.sh again and make a new
# lang. model (G.fst) But in the example run scripts that
# is done later when they have a good acoustic model.
# The outdir must already contain alignments or lattices.

if [ $stage -le 2 ]; then
    echo "Training mono system"
    steps/train_mono.sh    \
        --nj $nj           \
        --cmd "$train_cmd" \
        --totgauss 4000    \
        data/train         \
        data/lang          \
        exp/mono

    echo "Creating decoding graph (trigram lm), monophone model"
    utils/mkgraph.sh       \
        --mono             \
        data/lang_tg        \
        exp/mono           \
        exp/mono/graph_tg

    echo "Decoding, monophone model, trigram LM"
    # My dev data only has 3 speakers so used nj=3
    steps/decode.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/mono/graph_tg  \
	data/dev  \
	exp/mono/decode_tg
 
fi

if [ $stage -le 3 ]; then
    echo "mono alignment"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train data/lang exp/mono exp/mono_ali

    echo "first triphone training"
    steps/train_deltas.sh  \
        --cmd "$train_cmd" \
        2000 10000         \
        data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 4 ]; then

    echo "First triphone decoding"
    
    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri1      \
        exp/tri1/graph_tg

    echo "Decoding dev set with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri1/graph_tg \
        data/dev \
        exp/tri1/decode_tg
    
fi

# Is the following anything for me?
# # Check the results from word_align_lattices.sh
# # demonstrate how to get lattices that are "word-aligned" (arcs coincide with
# # words, with boundaries in the right place).
# sil_label=`grep '!SIL' data/lang_tg/words.txt | awk '{print $2}'` # ATH! Isn't my sil symbol in words <eps>???
# steps/word_align_lattices.sh --cmd "$train_cmd" --silence-label $sil_label \
#   data/lang_tg exp/tri1/decode_tg \
#   exp/tri1/decode_tg_aligned || exit 1;


if [ $stage -le 5 ]; then
    echo "Aligning train to tri1"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train data/lang \
        exp/tri1 exp/tri1_ali

    #ATH What splice-opts to use?? Start with a total of 7 frames. Try maybe later 9 frames
    echo "Training LDA+MLLT system tri2"
    steps/train_lda_mllt.sh \
        --cmd "$train_cmd" \
	--splice-opts "--left-context=3 --right-context=3" \
        3000 25000 \
        data/train \
        data/lang  \
        exp/tri1_ali \
        exp/tri2
	
fi

if [ $stage -le 6 ]; then
    echo "Creating decoding graph (trigram), triphone model"
    utils/mkgraph.sh   \
        data/lang_tg   \
        exp/tri2      \
        exp/tri2/graph_tg

    echo "Decoding dev set with trigram language model"
    steps/decode.sh    \
        --nj $nj_decode --cmd "$decode_cmd" \
        exp/tri2/graph_tg \
        data/dev \
        exp/tri2/decode_tg
    
fi

# ATH! Should I run VTLN scripts?
# and  Try Minimum Bayes Risk decoding?
# and hence run decode_fromlats.sh

if [ $stage -le 7 ]; then
    echo "Aligning train to tri2"
    steps/align_si.sh \
        --nj $nj --cmd "$train_cmd" \
        --use-graphs true \
        data/train data/lang \
        exp/tri2 exp/tri2_ali

fi

# if [ $stage -le 8 ]; then
#     echo "Do MMI on top of LDA+MLLT"
#     steps/make_denlats.sh \
# 	--nj $nj --cmd "$train_cmd" \
#         data/train data/lang \
# 	exp/tri2_ali exp/tri2_denlats 
    
#     steps/train_mmi.sh  \
# 	--cmd "$train_cmd" \
# 	data/train data/lang  \
# 	exp/tri2_ali exp/tri2_denlats \
#         exp/tri2_mmi

#     # Should I use --iter?? What does that do?
#     # Iteration of model to use
#     steps/decode.sh  \
# 	--config conf/decode.config \
#         --nj $nj_decode \
# 	--cmd "$decode_cmd" \
#         exp/tri2/graph_tg data/dev  \
# 	exp/tri2_mmi/decode_tg
# fi

# Should I also do mmi with boosting?
# And MPE (minimum phone error?

if [ $stage -le 9 ]; then

    # ATH which options to use??
    echo "From system 2 train tri3 which is LDA + MLLT + SAT"
    steps/train_sat.sh    \
        --cmd "$train_cmd" \
        4000 40000    \
        data/train    \
        data/lang     \
        exp/tri2_ali   \
	exp/tri3

    echo "Creating decoding graph"
    utils/mkgraph.sh       \
        data/lang_tg          \
        exp/tri3           \
        exp/tri3/graph_tg

    # I can send three models into decode_fmllr.sh
    # But I don't know how to make final.alimdl. ATH!
    echo "Decoding"
    steps/decode_fmllr.sh   \
	--config conf/decode.config \
        --nj $nj_decode   \
	--cmd "$decode_cmd" \
	exp/tri3/graph_tg  \
	data/dev  \
	exp/tri3/decode_tg

fi

if [ $stage -le 10 ]; then
    echo "Aligning train to tri3"
    steps/align_fmllr.sh \
        --nj $nj --cmd "$train_cmd" \
        data/train data/lang \
        exp/tri3 exp/tri3_ali

fi

# Here I can add pronunciation probabilities using
# steps/get_prons.sh and utils/dict_dir_add_pronprobs.sh
# I would have to run prepare_lang.sh again and make a
# new lang. model (G.fst)

if [ $stage -le 10 ]; then
    # Scripts that will help you find portions of your data
    # that has bad transcripts, so you can filter it out.  
    steps/cleanup/find_bad_utts.sh \
	--nj $nj --cmd "$train_cmd" \
	--use-graphs true \
	--transform-dir exp/tri3_ali \
	data/train data/lang \
	exp/tri3_ali exp/tri3_cleanup

    # The following command will show you some of
    # the hardest-to-align utterances in the data.
    head  exp/tri3_cleanup/all_info.sorted.txt

    # Get WER per utterance
    awk '{$4=$2/$3}1' < exp/tri3_cleanup/all_info.sorted.txt \
	| cut -d" " -f1-4 | sort -nr -k4 > exp/tri3_cleanup/info.ratio.txt

    # Sort speakers by WER
    grep "sys" per_spk_details.txt | tr -s "\t" | sort -n -k9,9 > per_spk_error_sorted.txt
    sed -i -e '1iSPEAKER         id       #SENT      #WORD       Corr        Sub        Ins        Del        Err      S.Err\' per_spk_error_sorted.txt
    
    # Filter away the hardest-to-align utterances
    local/run_data_cleaning.sh
fi

if [ $stage -le 11 ]; then
    echo "MMI on top of tri3 (i.e. LDA+MLLT+SAT+MMI)"
    steps/make_denlats.sh \
	--config conf/decode.config \
	--nj $nj --cmd "$train_cmd" \
	--transform-dir exp/tri3_0.2_ali \
	data/train_thresh0.2 data/lang \
	exp/tri3_0.2 exp/tri3_0.2_denlats

    steps/train_mmi.sh \
	--boost 0.1 \
	data/train_thresh0.2 data/lang \
	exp/tri3_0.2_ali \
	exp/tri3_0.2_denlats \
	exp/tri3_0.2_mmi_b0.1

    steps/decode_fmllr.sh \
	--config conf/decode.config \
	--nj $nj_decode --cmd "$decode_cmd" \
	--alignment-model exp/tri3_0.2/final.alimdl \
	--adapt-model exp/tri3_0.2/final.mdl \
	exp/tri3_0.2/graph_tg data/dev \
	exp/tri3_0.2_mmi_b0.1/decode_tg

    # # Which decode script do I want to use? decode_fmllr.sh gives better results
    # echo "Do a decoding that uses the exp/tri3_0.2/decode_tg directory
    #   to get transforms from, to see the difference"
    # steps/decode.sh \
    # 	--config conf/decode.config \
    # 	--nj $nj_decode --cmd "$decode_cmd" \
    # 	--transform-dir exp/tri3_0.2/decode_tg \
    # 	exp/tri3_0.2/graph_tg data/dev \
    # 	exp/tri3_0.2_mmi/decode_tg2
fi

# The following gave worse results:
if [ $stage -le 12 ]; then
    echo "Train UBM for fMMI experiments."
    steps/train_diag_ubm.sh \
	--silence-weight 0.5 \
	--nj $nj --cmd "$train_cmd" \
	600 data/train_thresh0.2 \
	data/lang exp/tri3_0.2_ali exp/dubm3 &

    echo "Train fMMI+MMI."
    steps/train_mmi_fmmi.sh \
	--boost 0.1 --cmd "$train_cmd" \
	data/train_thresh0.2 \
	data/lang exp/tri3_0.2_ali \
	exp/dubm3 exp/tri3_0.2_denlats \
	exp/tri3_0.2_fmmi &

    for iter in 3 4 5 6 7 8; do
	steps/decode_fmmi.sh \
	    --nj $nj_decode \
	    --cmd "$decode_cmd" \
	    --iter $iter \
	    --transform-dir exp/tri3_0.2/decode_tg \
	    exp/tri3_0.2/graph_tg data/dev \
	    exp/tri3_0.2_fmmi/decode_tg_it$iter &
    done
fi


# See more in kaldi/egs/{rm,wsj}/s5/run.sh

# Split the data up again

if [ $stage -le 13 ]; then
    echo "Re-segment the data using and in-domain recognizer"
    local/run_segmentation.sh data/all data/lang exp/tri3_0.2_mmi
fi
