#!/bin/bash

. ./path.sh

dir=/home/staff/inga/data/althingi/pronDict_LM
# DO NOT RUN!

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
local/filter_wordlist.py potential_not_valid_leipzig_malromur.txt # name of file from Anna
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

# Fix transcriptions starting with: tj kj pj tv kv tæ pæ kæ pl kl ky kn ki ke (Both UC and LC) 
perl -pe 's/^(t|k|p)(j|l|v|æ)([a-záðéíóúýþæö]+)\s([^ ]) /$1$2$3\t$4ʰ /' ${dir}/CaseSensitive_pron_dict_Fix2.txt | perl -pe 's/^(T|K|P)(j|l|v|æ)([a-záðéíóúýþæö]+)\s([^ ]) /$1$2$3\t$4ʰ /' | perl -pe 's/^k(e|i|n|y)([a-záðéíóúýþæö]+)\s([^ ]) /k$1$2\t$3ʰ /' | perl -pe 's/^K(e|i|n|y)([a-záðéíóúýþæö]+)\s([^ ]) /K$1$2\t$3ʰ /' | sort > ${dir}/CaseSensitive_pron_dict_Fix3.txt

# Fix "kór"
perl -pe 's/([^\s]*[^s]kór[a-záðéíóúýþæö]*)\s(([^ ]+ )+)k ouː? r/$1\t$2kʰ ou r/' ${dir}/CaseSensitive_pron_dict_Fix3.txt > ${dir}/CaseSensitive_pron_dict_Fix4.txt

# Fix missing "fráblástur" within words
#Search for words that start with these sound in the pron dict. If they have "fráblástur" there then search for them inside other words. Then I can use some commands like before to fix these words and overwrite them in the original pron dict

#NOTE Not just these words.
grep -ie "^\(k\|p\|t\)" ${dir}/CaseSensitive_pron_dict_Fix6.txt | sort -k1,1 | uniq > ${dir}/frablastursord.txt

# I removed all words shorter than 4 characters:
cut -f1 ${dir}/frablastursord.txt | awk '{ print length, $0 }' | sort -n | cut -d" " -f2 | sed -e '1,102d' | grep -v "\bkinn\b" | sort -u > ${dir}/frablastursord2.txt
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

	     
# Then I extract the words in CaseSensitive_pron_dict_Fix6.txt that do not have frablastur, when the respective word in frablasturord.txt, has. Check if there is an s in front, or the same letter again (f.ex. "kul" has fráblástur but "skulda" and "súkkulaði" do not.)

# I don't add the words if there is an s in front of the word part
IFS=$'\n'
for line in $(cat ${dir}/frablastursord.txt | grep -v "\bkinn\b"); do
    word=$(echo $line | cut -f1);
    phonemes=$(echo $line | cut -f2-);
    IFS=$' ';
    character1=$(echo $phonemes | cut -d" " -f1);
    newphonemes="${character1/ː/}ː?";
    for character in $(echo $phonemes | cut -d" " -f2-) ; do
	newphonemes="$newphonemes ${character/ː/}ː?";
    done;
    IFS=$'\n';
    # Get rid of words containing these phonemes (wo/ "fráblástur") if there is and s in front of them
    phonemes2=$(echo $newphonemes | perl -pe 's/^(.)ʰ/$1/');
    phonemes3=${phonemes2::-4};
    grep $word ${dir}/CaseSensitive_pron_dict_Fix6.txt \
	| egrep -v "^$word" | egrep -v "$newphonemes" | egrep -v "s $phonemes3" \
	>> ${dir}/words_missingfrablastur.txt;
done

# This one was called words_missingfrablastur2.txt because I had already found them once using the method commented out below.
sort -u ${dir}/words_missingfrablastur.txt > tmp && mv tmp ${dir}/words_missingfrablastur.txt

# Now I need to fix these words.
# Search for the words in frablastursord.txt inside words_missingfrablastur.txt, if I find them and the "frablastur" is missing and there is not an "s" in front, I need to insert fráblástur
IFS=$'\n'
for line in $(cat ${dir}/words_missingfrablastur.txt); do
    word=$(echo $line | cut -f1); echo "word: $word" ;
    phonemes=$(echo $line | cut -f2-); echo "phonemes: $phonemes";
    for line2 in $(cat ${dir}/frablastursord.txt | grep -v "\bkinn\b"); do
        frabword=$(echo $line2 | cut -f1);
        if (echo "$word" | grep -q "$frabword"); then
            echo "frabword: $frabword" ;
            frabphonemes=$(echo $line2 | cut -f2-); echo "frabphonemes: $frabphonemes";
            IFS=$' ';
            character1=$(echo $frabphonemes | cut -d" " -f1);
            newfrabphonemes="${character1/ː/}ː\?";
            for character in $(echo $frabphonemes | cut -d" " -f2-) ; do
                newfrabphonemes="$newfrabphonemes ${character/ː/}ː\?";
            done;
            IFS=$'\n'; echo "newfrabphonemes: $newfrabphonemes";
            # Get rid of words containing these phonemes (wo/ "fráblástur") if there is and s in front of them
            frabphonemes2=$(echo $newfrabphonemes | perl -pe 's/^(.)ʰ/$1/'); echo "frabphonemes2: $frabphonemes2";
            if ! (echo "$phonemes" | grep -q "s $frabphonemes2") && ! (echo "$phonemes" | grep -q "$newfrabphonemes") ; then
                echo "Inside if";
                newphonemes=$(echo $phonemes | sed -e 's/'$frabphonemes2'/'$frabphonemes'/'); echo "newphonemes: $newphonemes";
                echo -e $word $newphonemes >> ${dir}/words_missingfrablastur_fixed.txt;
            fi
        fi
    done
done

# Substitute the incorrect words with the fixed words


# Add transcribed country and city names + foreign words (companies, contries, names of parliament memebers)
cat ${dir}/CaseSensitive_pron_dict_Fix4.txt NotInPronDict_ice_transcribed.txt NotInPronDict_foreign.txt | sort > ${dir}/CaseSensitive_pron_dict_Fix5.txt

# Fix problems with spaces and tabs in the pron dict:
tr '\t' ' ' < ${dir}/CaseSensitive_pron_dict_Fix5.txt | tr -s " " | sed 's/ /\t/1' | sed -e 's/[ \t]*$//' > ${dir}/CaseSensitive_pron_dict_Fix6.txt

# Make a case sensitive dictionary which I will use to train g2p models on:
tr '\t' ' ' < ${dir}/CaseSensitive_pron_dict_Fix4.txt | tr -s " " | sed 's/ /\t/1' | sed -e 's/[ \t]*$//' > ${dir}/g2p_pron_dict.txt
