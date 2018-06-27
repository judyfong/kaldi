#!/bin/bash

. ./path.sh

dir=/home/staff/inga/data/althingi/pronDict_LM
# DO NOT RUN!

# Found first which words were not in the pron dict and
# Find words which appear more than three times in the Althingi data but not in the pron. dict
cut -d" " -f2- data/train/text \
    | tr " " "\n" \
    | egrep -v '[cqwzåäø]' \
    | sed '/[a-záðéíóúýþæö]/!d' \
    | egrep -v '^\s*$' \
    | sort | uniq -c \
    | sort -k1 -n \
    | awk '$2 ~ /[[:print:]]/ { if($1 > 2) print $2 }' \
	  > data/train/words_text3.txt
comm -13 <(cut -f1 /data/malromur_models/current_pron_dict_20161005.txt | sort) \
     <(sort data/train/words_text3.txt) > data/train/only_text_NOTlex.txt

# Filter out bad words
local/auxiliary/filter_by_letter_ngrams.py /data/malromur_models/current_pron_dict_20161005.txt data/train/only_text_NOTlex.txt
local/auxiliary/filter_wordlist.py potential_not_valid_leipzig_malromur.txt # name of file from Anna
mv no_pattern_match.txt potential_valid_althingi.txt

# # This would probably have been fine but I decided to go through the output list from filter_by_letter_ngrams, called "potential_not_valid_leipzig_malromur.txt", clean it and add what I wanted to keep to the newly created "scraped_words_notPronDict_3_filtered.txt"
# auxiliary/local/filter_non_ice_chars.py potential_not_valid_leipzig_malromur.txt
# auxiliary/local/filter_wordlist.py potential_not_valid_leipzig_malromur.txt
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

# Step missing where find words that were correctly uppercased
# in the original Málföngs pron dict and put them in upper case in my dict

# Also missing where I compile a list of proper nouns that are still in lowercase
# in the pron dict.

# Uppercase proper nouns
join -1 1 -2 1 <(sed 's/.\+/\L&/g' ${dir}/propernouns/propernouns_pron_dict_LC.txt | sort) <(sort -k1,1 ${dir}/CaseSensitive_pron_dict_Fix1.txt) -t $'\t' | sed 's/.\+/\u&/g' > ${dir}/UCpart2_CaseSens_pron_dict.txt

# Extract the rest (UC and LC)
comm -13 <(sed 's/.\+/\L&/g' ${dir}/UCpart2_CaseSens_pron_dict.txt | sort) <(sort ${dir}/CaseSensitive_pron_dict_Fix1.txt) > ${dir}/rest_of_CaseSens_pron_dict2.txt

# Combine
cat ${dir}/UCpart2_CaseSens_pron_dict.txt ${dir}/rest_of_CaseSens_pron_dict2.txt | sort > ${dir}/CaseSensitive_pron_dict_Fix2.txt

# Fix transcriptions starting with: tj kj pj tv kv tæ pæ kæ pl kl ky ký kn ki kí ke and hv (hv also inside words) (Both UC and LC) 
perl -pe 's:^([Tt]|[Pp]|[kk])([a-záðéíóúýþæö]+)\t[ptkc] :$1$2\t$3ʰ :' ${dir}/CaseSensitive_pron_dict_Fix2.txt | perl -pe 's:^([Hh]v[a-záðéíóúýþæö]+)\tk v:$1\tkʰ v:' | perl -pe 's:(hv[^\s]+)\t(.+?)k v:$1\t$2kʰ v:' | sort > ${dir}/CaseSensitive_pron_dict_Fix3.txt

# Fix transcription starting with hv and Hv:
#perl -pe 's:^([Hh]v[a-záðéíóúýþæö]+)\tk v:$1\tkʰ v:' CaseSensitive_pron_dict_Fix7_okt2017.txt | perl -pe 's:(hv[^\s]+)\t(.+?)k v:$1\t$2kʰ v:' > CaseSensitive_pron_dict_Fix8.txt

# Misc:
# perl -pe 's/([^ ]*?kerf[a-záðéíóúýþæö]*?)\s(([^ ]+ )+)c ɛ r v/$1\t$2cʰ ɛ r v/' ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix7_okt2017.txt | > ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix8.txt

# Fix "kór"
perl -pe 's/([^\s]*?[^s]kór[a-záðéíóúýþæö]*)\s(([^ ]+ )+)k ouː? r/$1\t$2kʰ ou r/' ${dir}/CaseSensitive_pron_dict_Fix3.txt > ${dir}/CaseSensitive_pron_dict_Fix4.txt

# Fix missing "fráblástur" within words
#Search for words that start with these sound in the pron dict. If they have "fráblástur" there then search for them inside other words. Then I can use some commands like before to fix these words and overwrite them in the original pron dict

#NOTE Not just these words. Also words starting with hv f.ex.
grep -ie "^\(k\|p\|t\)" ${dir}/CaseSensitive_pron_dict_Fix6.txt | sort -k1,1 | uniq > ${dir}/frablastursord.txt

# I removed all words shorter than 4 characters and longer than 8:
cut -f1 ${dir}/frablastursord.txt | awk '{ print length, $0 }' | sort -n | cut -d" " -f2 | grep -o -w -E '^[^ ]{4,8}' | grep -v "\bkinn\b" | sort -u > ${dir}/frablastursord2.txt
join -1 1 -2 1 <(sort -k 1,1 ${dir}/frablastursord.txt) <(sort -k 1,1 ${dir}/frablastursord2.txt) > tmp && mv tmp ${dir}/frablastursord.txt

# Change back to using a tab between the words and their phonemes
tr '\t' ' ' < ${dir}/frablastursord.txt | tr -s " " | sed 's/ /\t/1' | sort > tmp && mv tmp ${dir}/frablastursord.txt

# I sort the words, and keep only the words that do not contain any of the other ones as a substring NOTE! SLOW
IFS=$'\n'
touch ${dir}/frablastursord_uniq.txt
for line in $(awk '{ print length, $0 }' ${dir}/frablastursord.txt | sort -n | cut -d" " -f2-); do
    #echo "line: $line"
    j=0
    for line2 in $(cat ${dir}/frablastursord_uniq.txt); do
	phonemes2=$(echo $line2 | cut -f2- )
	#echo "line2: $line2"
	#echo "phonemes2: $phonemes2"
        if (echo "$line" | grep -q "$phonemes2"); then
	    #echo "line contains phonemes2"
	    j=1
	    break
	fi
    done
    if [ "$j" = 0 ] ; then
        #echo "Line does not contain phonemes2 so write it"
        echo -e $line >> ${dir}/frablastursord_uniq.txt
    fi
done
sed -r 's:ʰ::' frablastursord_4to8_uniq.txt > frablastursord_4to8_uniq_frab_removed.txt

# Now I need to fix these words.
# Search for the words in frablastursord.txt inside words in the pron dict, if I find them and the "frablastur" is missing and there is neither an "s" in front nor the same letter, I insert fráblástur
IFS=$'\n'
cp ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix10_frab_inside_words.txt ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix11_frab_inside_words.txt
for line in $(cat frablastursord_4to8_uniq_frab_removed.txt); do
    word=$(echo $line | cut -d" " -f1);
    phonemes=$(echo $line | cut -d" " -f2-);
    phon1=$(echo $phonemes | cut -d" " -f1);
    phon_rest=$(echo $phonemes | cut -d" " -f2-);
    sed -r -i "s:([^skpt]${word}[a-záðéíóúýþæö]*)\t(([^ ]+ )*?${phon1}) (${phon_rest})\b:\1\t\2ʰ \4:" CaseSensitive_pron_dict_Fix11_frab_inside_words.txt
done

# I did a lot of manual fixing of shorter words. F.ex. fixing word with different prefixes.

# Add transcribed country and city names + foreign words (companies, contries, names of parliament memebers)
cat ${dir}/CaseSensitive_pron_dict_Fix4.txt NotInPronDict_ice_transcribed.txt NotInPronDict_foreign.txt | sort > ${dir}/CaseSensitive_pron_dict_Fix5.txt

# Fix problems with spaces and tabs in the pron dict:
tr '\t' ' ' < ${dir}/CaseSensitive_pron_dict_Fix5.txt | tr -s " " | sed 's/ /\t/1' | sed -e 's/[ \t]*$//' > ${dir}/CaseSensitive_pron_dict_Fix6.txt

# Fix missing fráblástur in words starting with "hv"
sed -r 's:^(hv[^    ]+)     k v:\1  kʰ v:' ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix6.txt > ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix7.txt

# Make a case sensitive dictionary which I will use to train g2p models on:
tr '\t' ' ' < ${dir}/CaseSensitive_pron_dict_Fix4.txt | tr -s " " | sed 's/ /\t/1' | sed -e 's/[ \t]*$//' > ${dir}/g2p_pron_dict.txt

# Missing a step where I fix compound words where the first part ends with an s and the second one starts with an l or an n. F.ex. heimilislæknir

# Find incomplete transcriptions based on a proportion of letters in word vs hljóðritun
sed 's: ::g' ~/data/althingi/pronDict_LM/CaseSensitive_pron_dict_Fix17.txt | awk '{print $0"\t"length($1)"\t"length($2)}' | awk '{$5=($3)/($4)}1' | awk '{if ($5 > 1.4) print;}' > incomplete_transcriptions.tmp &

# Cleaned my training set without lowercasing. Added to the pronunciation dictionary the missing case of words that appear in both cases.

# There are often errors in compound words where the first word ends with an r and the second one starts with an s. Then the r is often incorrectly written as r̥

# I have foreign words within the prondict, but I try to have them in a list as well, erlend_ord.txt, so that I can remove them from my g2p training set.
