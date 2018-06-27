#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Clean old Althingi text data, i.e. text data that is more abbreviated than newer speeches.
# NOTE! I have never used this and without new expansion grammar, the old speeches will still be full of abbreviations after cleaning!

stage=-1
nj=10

. ./path.sh # Needed for KALDI_ROOT
. ./cmd.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
    echo "Usage: $0 <path-to-original-data> <output-data-dir>" >&2
    echo "Eg. $0 ~/data/local/corpus data/all" >&2
    exit 1;
fi

#datadir=data/local/corpus
#outdir=data/all
datadir=/data/althingi/text_corpus
prondir=~/data/althingi/pronDict_LM
out=text_session120_130_clean.txt

IFS=$'\n'
for file in $( ls ${datadir}/AlthingiUploads ); do
    uttid=$(echo $file | cut -d"." -f1)
    text=$(egrep "<p>[^<]" ${datadir}/AlthingiUploads/$file | cut -d">" -f2-)
    echo -e $uttid" "$text >> ${datadir}/text_orig.txt
done

# Remove comments in parentheses, remaining tags, leading spaces and reduce spaces to one between words
sed -re 's:\([^()]*?\): :g' -e 's:\([^()]*?\): :g' -e 's:</?su[bp]>|</?p>|</?b>::g' ${datadir}/text_orig.txt | sed -re 's/^[ \t]*//' -e 's/[[:space:]]+/ /g' > ${datadir}/text_noSGML.txt

# echo "Remove some punctuations and rewrite roman numerals to numbers"
sed -re 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–²³¼¾½ _)(-]+//g' -e 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' <${datadir}/text_noSGML.txt > ${datadir}/text_wRoman.tmp
python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${datadir}/text_wRoman.tmp', 'r')
text_out = open('${datadir}/text_noRoman.tmp', 'w')
for line in text:
    match_list = re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', line, flags=0)
    match_list = [elem for elem in match_list if len(elem)>0]
    match_list = list(set(match_list))
    match_list.sort(key=len, reverse=True) # Otherwise it will substitute parts of roman numerals
    line = line.split()
    tmpline=[]
    for match in match_list:
        for word in line:
            number = [re.sub(match,str(roman.fromRoman(match)),word) for elem in re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', word) if len(elem)>0]
            if len(number)>0:
                tmpline.extend(number)
            else:
                tmpline.append(word)
        line = tmpline
        tmpline=[]
    print(' '.join(line), file=text_out)

text.close()
text_out.close()
"

echo "Rewrite and remove punctuations that I'm not trying to learn how to restore"

# 1) Remove comments in parentheses and expand "&"
# 2) Fix errors like: "bla bla .Bla bla"
# 3) Remove punctuations which is safe to remove
# 4) Remove "ja" from numbers written like "22ja" and rewrite [ck]?m[23] to [ck]?m[²³]
# 5) Add missing space between sentences
# 6) Remove periods inside abbreviations
# 7) Remove periods after abbreviated middle names
# 8) In an itemized list, lowercase what comes after the numbering
# 9) Expand "--" between LC letters or numbers to "til"
# 10) Lowercase text
# 11) Switch hyphen out for space
# 12) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
# 13) Fix spacing around % and degrees celsius
# 14) Remove some dashes (not the kind that is between numbers) and periods at the beginning of lines
# 15-16 Remove sgml tokens and fix a some remaining errors
# 17-18) Change spaces to one between words, remove empty lines and write    
sed -re 's:\([^/(]*?\): :g' -e 's:&: og :g' \
    -e 's: \.([^\.]):. \1:g' \
    -e 's: ,+| \.+|,\.| |__+: :g' \
    -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' \
    -e 's:\b([^ ]*[^ A-ZÁÐÉÍÓÚÝÞÆÖ/-])([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2:g' \
    -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e 's: ([A-ZÁÐÉÍÓÚÝÞÆÖ])\. : \1 :g' \
    -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \L\2:g' \
    -e 's:\b([a-záðéíóúýþæö]+)\.?--([a-záðéíóúýþæö]):\1 til \2:g' -e 's:\b([0-9]+)\.?--([0-9]):\1 til \2:g' \
    -e 's:.*:\L&:g' \
    -e 's:([a-záðéíóúýþæö])-+([a-záðéíóúýþæö]):\1 \2:g' \
    -e 's:\b([0-9]+)([^0-9 ,.–/:])([0-9]):\1 \2 \3:g' -e 's:\b([a-záðéíóúýþæö]+\.?)-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([a-záðéíóúýþæö]+)\b:\1 \2:g' \
    -e 's: +([%‰–°º;!?:.,]):\1:g' -e 's:([°º]) c :\1c :g' -e 's:–([^0-9]): \1:g' \
    -e 's:—|­| |-|_: :g' -e 's:^\. *::g' \
    -e 's:\\mbox|\\vfil|,,|\\vskip.*|\\::g' -e 's: , :, :g' -e 's: /: :g' \
    -e 's:till\. til þál\.:tillaga til þingsályktunar:g' \
    -e 's/[[:space:]]+/ /g' ${datadir}/text_noRoman.tmp \
    | egrep -v "^\s*$"  > ${datadir}/text_noPunct.tmp

echo "Remove periods after abbreviations" # NOTE! I can combine this with the step below "start with expanding..." by having those abbrs in a file in col1 and the expansion in col2
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_lexicon.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u | egrep -v "\b[ck]?m[^a-záðéíóúýþæö]*\b|\b[km]?g\b" > ${datadir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/oldspeech_abbr.txt | tr " " "\n" | egrep -v "^\s*$|form|\btil\b" | sed -r 's:\.::' | sort -u >> ${datadir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/simple_abbr.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u >> ${datadir}/abbr_lex.tmp
# Make the regex pattern
sort -u ${datadir}/abbr_lex.tmp | tr "\n" "|" | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > ${datadir}/abbr_lex_pattern.tmp
sed -r "s:(\b$(cat ${datadir}/abbr_lex_pattern.tmp))\.:\1:g" ${datadir}/text_noPunct.tmp > ${datadir}/text_noAbbrPeriods.tmp

# Start with expanding some abbreviations using regex
sed -re 's:\bamk\b:að minnsta kosti:g' \
    -e 's:\bdr\b:doktor:g' \
    -e 's:\betv\b:ef til vill:g' \
    -e 's:\bfrh\b:framhald:g' \
    -e 's:\bfyrrv\b:fyrrverandi:g' \
    -e 's:\bheilbrrh\b:heilbrigðisráðherra:g' \
    -e 's:\biðnrh\b:iðnaðarráðherra:g' \
    -e 's:\binnanrrh\b:innanríkisráðherra:g' \
    -e 's:\blandbrh\b:landbúnaðarráðherra:g' \
    -e 's:\bmas\b:meira að segja:g' \
    -e 's:\bma\b:meðal annars:g' \
    -e 's:\bmenntmrh\b:mennta og menningarmálaráðherra:g' \
    -e 's:\bmkr\b:millj kr:g' \
    -e 's:\bnk\b:næstkomandi:g' \
    -e 's:\bnr\b:númer:g' \
    -e 's:\bnúv\b:núverandi:g' \
    -e 's:\bo ?s ?frv\b:og svo framvegis:g' \
    -e 's:\boþh\b:og þess háttar:g' \
    -e 's:\bpr\b:per:g' \
    -e 's:\bsamgrh\b:samgönguráðherra:g' \
    -e 's:\bsbr\b:samanber:g' \
    -e 's:\bskv\b:samkvæmt:g' \
    -e 's:\bss\b:svo sem:g' \
    -e 's:\bstk\b:stykki:g' \
    -e 's:\btam\b:til að mynda:g' \
    -e 's:\btd\b:til dæmis:g' \
    -e 's:\buþb\b:um það bil:g' \
    -e 's:\butanrrh\b:utanríkisráðherra:g' \
    -e 's:\bviðskrh\b:viðskiptaráðherra:g' \
    -e 's:\bþáv\b:þáverandi:g' \
    -e 's:\bþús\b:þúsund:g' \
    -e 's:\bþeas\b:það er að segja:g' \
    < ${datadir}/text_noAbbrPeriods.tmp > ${datadir}/text_exp1.tmp

# Add spaces into acronyms pronounced as letters
IFS=$'\n'
for var in $(cat text_norm/abbr_acro_as_letters.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
  var1=$(echo $var | sed 's/./& /g')
  sed -i "s/\b$var\b/$var1/g" ${datadir}/text_exp1.tmp
done
sed -r -i 's/[[:space:]]+/ /g' ${datadir}/text_exp1.tmp
	
echo "Capitalize words in the Althingi texts, that are capitalized in the pron dict"
comm -12 <(sed -r 's:.*:\L&:' ${prondir}/CaseSensitive_pron_dict_propernouns_plus.txt | sort) <(tr " " "\n" < ${datadir}/text_exp1.tmp | sed -re 's/[^a-záðéíóúýþæö]+//g'| egrep -v "^\s*$" | sort -u) > ${datadir}/propernouns_althingi_texts.tmp
# Make the regex pattern
tr "\n" "|" < ${datadir}/propernouns_althingi_texts.tmp | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${datadir}/propernouns_althingi_texts_pattern.tmp

# Capitalize
srun sed -r "s:(\b$(cat ${datadir}/propernouns_althingi_texts_pattern.tmp)\b):\u\1:g" ${datadir}/text_exp1.tmp > ${datadir}/Cap1.tmp

# Capitalize acronyms which are pronounced as words
# Make the regex pattern
tr "\n" "|" < text_norm/acronyms_as_words.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > text_norm/acronyms_as_words_pattern.tmp

# Capitalize 
srun sed -r 's:(\b'$(cat text_norm/acronyms_as_words_pattern.tmp)'\b):\U\1:g' ${datadir}/Cap1.tmp > ${datadir}/Cap2.tmp


# Use Anna's code to expand many instances of hv, þm og hæstv
python3 local/althingi_replace_plain_text.py ${datadir}/Cap2.tmp ${datadir}/${out}
