#!/bin/bash -eux
set -o pipefail
# Idea from: Sproat, R. (2010). Lightly supervised learning of text normalization: Russian number names.

# Run from one directory up

# TODO: map words not in our chosen word symbol table to <unk> (which is in the symtab, btw)
# TODO: (in grammar) try to limit false positives, such as "eins og -> 1 og"
# TODO: Remove all lines in ARPA n-gram which contain numerals. The LM should only be for expanded nums

# NOTE! I add all the althingi data to the language model too make sure everything prints out. It would
# probably be way better to map to <unk> and then try to reverse it later.

nj=25
stage=0
textnorm=text_norm
dir=text_norm/text
utf8syms=text_norm/utf8.syms
datadir=data/all
data998=data/all100

run_tests=false

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p $dir

if [ $stage -le 1 ]; then
    # I already have a list of words from Leipzig + the first 100 hrs of data: text_norm/text/wordlist30_plusAlthingi.txt

    # Get the vocab of the new althingi data
    cut -d" " -f2- ${datadir}/text_bb_SpellingFixed.txt | tr " " "\n" | egrep -v "^\s*$" | LC_ALL=C sort -u > ${datadir}/words_SpellingFixed.txt
    
    # Get a list of words solely in the althingi data and add it to wordlist30.txt
    comm -23 <(sort ${datadir}/words_SpellingFixed.txt) <(sort ${dir}/wordlist30_plusAlthingi998.txt) > ${dir}/vocab_alth_only.tmp
    cat ${dir}/wordlist30_plusAlthingi998.txt ${dir}/vocab_alth_only.tmp > ${dir}/wordlist30_plusAlthingi_all.txt
      
    # Make a word symbol table. Code from prepare_lang.sh
    cat ${dir}/wordlist30_plusAlthingi_all.txt | LC_ALL=C sort | uniq  | awk '
    BEGIN {
      print "<eps> 0";
    }
    {
      if ($1 == "<s>") {
        print "<s> is in the vocabulary!" | "cat 1>&2"
        exit 1;
      }
      if ($1 == "</s>") {
        print "</s> is in the vocabulary!" | "cat 1>&2"
        exit 1;
      }
      printf("%s %d\n", $1, NR);
    }
    END {
      printf("<unk> %d\n", NR+1);
    }' > $dir/words30all.txt
 
fi

if [ $stage -le 4 ]; then
    # We need a FST to map from utf8 tokens to words in the words symbol table.
    # f1=word, f2-=utf8_tokens (0x0020 always ends a utf8_token seq)
    utils/slurm.pl \
        ${dir}/log/words30all_to_utf8.log \
        awk '$2 != 0 {printf "%s %s \n", $1, $1}' \< ${dir}/words30all.txt \
        \| fststringcompile ark:- ark:- \
        \| fsts-to-transcripts ark:- ark,t:- \
        \| int2sym.pl -f 2- ${utf8syms} \> ${dir}/words30all_to_utf8.txt
 
    utils/slurm.pl \
        ${dir}/log/utf8_to_words30all.log \
        utils/make_lexicon_fst.pl ${dir}/words30all_to_utf8.txt \
        \| fstcompile --isymbols=${utf8syms} --osymbols=${dir}/words30all.txt --keep_{i,o}symbols=false \
        \| fstarcsort --sort_type=ilabel \
        \| fstclosure --closure_plus     \
        \| fstrmepsilon \| fstminimize   \
        \| fstarcsort --sort_type=ilabel \> ${dir}/utf8_to_words30all.fst

 
    # EXPAND_UTT is an obligatory rewrite rule that accepts anything as input
    # and expands what can be expanded. Note! It does not accept capital letters.
    # Create the fst that works with expand-numbers, using words30_expanded.txt as
    # symbol table. NOTE! I changed map_type from rmweight to arc_sum to fix weight problem
    utils/slurm.pl \
        ${dir}/log/expand_to_words30all.log \
        fstcompose ${textnorm}/EXPAND_UTT.fst ${dir}/utf8_to_words30all.fst \
        \| fstrmepsilon \| fstmap --map_type=arc_sum \
        \| fstarcsort --sort_type=ilabel \> ${textnorm}/expand_to_words30all.fst &

fi

if [ $stage -le 6 ]; then
    if [ -f ${dir}/numbertexts.txt.gz ]; then
        mkdir -p ${dir}/.backup
        mv ${dir}/{,.backup/}numbertexts.txt.gz
    fi

    # Here the lines in text that are rewriteable are selected, based on key.
    IFS=$' \t\n'
    sub_nnrewrites=$(for j in `seq 1 $nj`; do printf "${dir}/abbreviated_fsts/abbreviated.%s.scp " $j; done)
    # cat $sub_nnrewrites \
    #     | awk '{print $1}' \
    #     | sort -k1 \
    #     | join - ${dir}/texts_no_oovs.txt \ 
    #     | cut -d ' ' -f2- \
    #     | gzip -c > ${dir}/numbertexts.txt.gz
    cat $sub_nnrewrites | awk '{print $1}' | sort -k1 | join - ${dir}/text_no_oovs.txt | cut -d ' ' -f2- > ${dir}/numbertexts.txt

    # Add the Althingi data to numbertexts to make sure everything will be printed out after expansion.
    cut -d" " -f2- ${data998}/text >> ${dir}/numbertexts.txt
    cut -d" " -f2- ${datadir}/text_bb_SpellingFixed.txt >> ${dir}/numbertexts.txt
    gzip -c ${dir}/numbertexts.txt > ${dir}/numbertexts.txt.gz
    rm ${dir}/numbertexts.txt
fi

if [ $stage -le 7 ]; then
    for n in 3 5; do
        echo "Building ${n}-gram"
        if [ -f ${dir}/numbertextsAll_${n}g.arpa.gz ]; then
            mkdir -p ${dir}/.backup
            mv ${dir}/{,.backup/}numbertextsAll_${n}g.arpa.gz
        fi

        # KenLM is superior to every other LM toolkit (https://github.com/kpu/kenlm/).
        # multi-threaded and designed for efficient estimation of giga-LMs
        /opt/kenlm/build/bin/lmplz \
	    --skip_symbols \
            -o ${n} -S 70% --prune 0 0 1 \
            --text ${dir}/numbertexts.txt.gz \
            --limit_vocab_file <(cut -d " " -f1 ${dir}/words30all.txt | egrep -v "<eps>|<unk>") \
            | gzip -c > ${dir}/numbertextsAll_${n}g.arpa.gz
    done

    # Try out a bigram LM
    if [ -f ${dir}/numbertextsAll_2g.arpa.gz ]; then
        mv ${dir}/{,.backup/}numbertextsAll_2g.arpa.gz
    fi
    /opt/kenlm/build/bin/lmplz \
	--skip_symbols \
        -o 2 -S 70% --prune 0 1 \
            --text ${dir}/numbertexts.txt.gz \
            --limit_vocab_file <(cut -d " " -f1 ${dir}/words30all.txt | egrep -v "<eps>|<unk>") \
            | gzip -c > ${dir}/numbertextsAll_2g.arpa.gz
    
fi

if [ $stage -le 8 ]; then
    # Get the fst language model. Obtained using the rewritable sentences.
    for n in 3 5; do
        if [ -f ${dir}/numbertextsAll_${n}g.fst ]; then
            mkdir -p ${dir}/.backup
            mv ${dir}/{,.backup/}numbertextsAll_${n}g.fst
        fi

        arpa2fst "zcat ${dir}/numbertextsAll_${n}g.arpa.gz |" - \
            | fstprint \
            | utils/s2eps.pl \
            | fstcompile --{i,o}symbols=${dir}/words30all.txt --keep_{i,o}symbols=false \
            | fstarcsort --sort_type=ilabel \
                         > ${dir}/numbertextsAll_${n}g.fst
    done

    # A bigram LM
    if [ -f ${dir}/numbertextsAll_2g.fst ]; then
            mkdir -p ${dir}/.backup
            mv ${dir}/{,.backup/}numbertextsAll_2g.fst
        fi
    arpa2fst "zcat ${dir}/numbertextsAll_2g.arpa.gz |" - \
            | fstprint \
            | utils/s2eps.pl \
            | fstcompile --{i,o}symbols=${dir}/words30all.txt --keep_{i,o}symbols=false \
            | fstarcsort --sort_type=ilabel \
                         > ${dir}/numbertextsAll_2g.fst
    
fi

if [ $stage -le 9 ] && $run_tests; then
    # Let's test the training set, or a subset.

    # Combine, shuffle and subset
    sub_nnrewrites=$(for j in `seq 1 $nj`; do printf "${dir}/abbreviated_fsts/abbreviated.%s.scp " $j; done)
    all_cnt=$(cat $sub_nnrewrites | wc -l)
    test_cnt=$[all_cnt * 5 / 1000]
    cat $sub_nnrewrites | shuf -n $test_cnt | LC_ALL=C sort -k1b,1 > ${dir}/abbreviated_test.scp

    utils/split_scp.pl ${dir}/abbreviated_test.scp ${dir}/abbreviated_test.{1..8}.scp

    for n in 3 5; do
        # these narrowed lines should've had all OOVs mapped to <unk>
        # (so we can do the utf8->words30 mapping, without completely
        # skipping lines with OOVs)
        utils/slurm.pl JOB=1:8 ${dir}/log/expand_test${n}g.JOB.log fsttablecompose --match-side=left scp:${dir}/abbreviated_test.JOB.scp ${dir}/expand_to_words30.fst ark:- \| fsttablecompose --match-side=left ark:- ${dir}/numbertexts_${n}g.fst ark:- \| fsts-to-transcripts ark:- ark,t:"| utils/int2sym.pl -f 2- ${dir}/words30_expanded.txt > ${dir}/expand_texts_test_${n}g.JOB.txt"
    done

    wait
fi

