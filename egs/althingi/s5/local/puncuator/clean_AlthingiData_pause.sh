#!/bin/bash -eu

set -o pipefail

# 2016 Inga Rún
# Clean the 2005-2015 althingi texts for use in a punctuation restoration model

if [ $# -ne 2 ]; then
    echo "Usage: $0 <texts-to-use-in-LM> <output-clean-texts>" >&2
    echo "Eg. $0 data/all_sept2017/text_orig_bb.txt ~/data/althingi/postprocessing/texts_pause_clean_for_punct_restoring.txt" >&2
    exit 1;
fi

corpus=$1
out=$2
dir=$(dirname $out)
prondir=~/data/althingi/pronDict_LM

# tmp=$(mktemp -d)
# cleanup () {
#     rm -rf "$tmp"
# }
# trap cleanup EXIT

echo "Remove xml-tags and comments"

# In the following I separate the numbers on "|":
# 1) removes comments on the form "<mgr>//....//</mgr>"
# 2) removes comments on the form "<!--...-->"
# 3) removes links that were not written like 2)
# 4) removes f.ex. <mgr>::afritun af þ. 287::</mgr>
# 5) removes comments on the form "<mgr>....//</mgr>"
# 6-7) removes comments before the beginning of speeches
# 8-11) removes comments like "<truflun>Kliður í salnum.</truflun>"
# 12) removes comments in parentheses
# 13) (in a new line) Rewrite fractions
# 14-16) Rewrite law numbers
# 17-19) Remove comments in a) parentheses, b) left: "(", right "/" or "//", c) left: "/", right one or more ")" and maybe a "/", d) left and right one or more "/"
# 20) Remove comments on the form "xxxx", used when they don't hear what the speaker said
# 21-22) Remove the remaining tags and reduce the spacing to one between words
sed -re 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
    -e 's:\(+[^/()<>]*?\)+: :g' \
    -e 's:\(+[^/()<>]*?\)+: :g' -e 's:\([^/<>)]*?/+: :g' -e 's:/[^/<>)]*?\)+/?: :g' -e 's:/+[^/<>)]*?/+: :g' \
    -e 's:xx+::g' \
    -e 's:\(+[^/()<>]*?\)+: :g' -e 's:<[^<>]*?>: :g' -e 's:[[:space:]]+: :g' < ${corpus} > ${dir}/noXML.tmp

# echo "Remove some punctuations and rewrite roman numerals to numbers"
sed -re 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–²³¼¾½ _)(-]+//g' -e 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' <${dir}/noXML.tmp > ${dir}/roman.tmp
python3 -c "
import re
import sys
roman_path='/home/staff/inga/kaldi/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${dir}/roman.tmp', 'r')
text_out = open('${dir}/noRoman.tmp', 'w')
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
# 6-7) Remove abbreviation periods
# 8) Remove periods after abbreviated middle names
# 9) In an itemized list, lowercase what comes after the numbering
# 10) Lowercase text
# 11) Switch hyphen out for space
# 12) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
# 13) Fix spacing around % and degrees celsius
# 14) Remove some dashes (not the kind that is between numbers) and periods at the beginning of lines
# 15-16) Change spaces to one between words, remove empty lines and write    
sed -re 's:\([^/(]*?\): :g' -e 's:&: og :g' \
    -e 's: \.([^\.]):. \1:g' \
    -e 's: ,+| \.+|,\.| |__+: :g' \
    -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' \
    -e 's: ([^ ]*[^ A-ZÁÐÉÍÓÚÝÞÆÖ/-])([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2:g' \
    -e 's:(\.[a-záðéíóúýþæö]+)\. :\1 :g' -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e 's:\b(hv|hæstv|þm|dr|frh|nk|nr|sbr|skv|[^ ]+?rh|þús)\.:\1:g' \
    -e 's: ([A-ZÁÐÉÍÓÚÝÞÆÖ])\. : \1 :g' \
    -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \L\2:g' \
    -e 's: .*: \L&:g' \
    -e 's:([^ 0-9])–([^ 0-9]):\1 \2:g' -e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9]\.?)tilstr[^ 0-9]*?\.?([0-9]):\1 til \2:g' -e 's:([0-9\.%])-+([0-9]):\1 til \2:g' \
    -e 's:([a-záðéíóúýþæö])-+([a-záðéíóúýþæö]):\1 \2:g' \
    -e 's: ([0-9]+)([^0-9 ,.–/:])([0-9]): \1 \2 \3:g' -e 's: ([a-záðéíóúýþæö]+\.?)-?([0-9]+)\b: \1 \2:g' -e 's: ([0-9,]+%?\.?)-?([a-záðéíóúýþæö]+)\b: \1 \2:g' \
    -e 's: *%:% :g' -e 's:([°º]) c :\1c :g' \
    -e 's:—|­| |-: :g' -e 's:^\. *::g' \
    -e 's/[[:space:]]+/ /g' ${dir}/noRoman.tmp \
    | egrep -v "\(|\)" | egrep -v "^\s*$"  > ${dir}/noPunct.tmp

echo "Remove periods after abbreviations"
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_lexicon.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u | egrep -v "\b[ck]?m[^a-záðéíóúýþæö]*\b|\b[km]?g\b" > ${dir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/oldspeech_abbr.txt | tr " " "\n" | egrep -v "^\s*$|form|\btil\b" | sed -r 's:\.::' | sort -u >> ${dir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/simple_abbr.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u >> ${dir}/abbr_lex.tmp
# Make the regex pattern
sort -u ${dir}/abbr_lex.tmp | tr "\n" "|" | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > ${dir}/abbr_lex_pattern.tmp

sed -r "s:(\b$(cat ${dir}/abbr_lex_pattern.tmp))\.:\1:g" ${dir}/noPunct.tmp > ${dir}/noAbbrPeriods.tmp

echo "Expand abbreviations that expand to more than one word (to match the pause annotated segments better)"
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
    -e 's:\bsbr\b:samanber:g' \
    -e 's:\bskv\b:samkvæmt:g' \
    -e 's:\bss\b:svo sem:g' \
    -e 's:\bstk\b:stykki:g' \
    -e 's:\btd\b:til dæmis:g' \
    -e 's:\btam\b:til að mynda:g' \
    -e 's:\buþb\b:um það bil:g' \
    -e 's:\butanrrh\b:utanríkisráðherra:g' \
    -e 's:\bviðskrh\b:viðskiptaráðherra:g' \
    -e 's:\bþáv\b:þáverandi:g' \
    -e 's:\bþús\b:þúsund:g' \
    -e 's:\bþeas\b:það er að segja:g' \
    < ${dir}/noAbbrPeriods.tmp > ${dir}/pause_text_exp1.tmp

IFS=$'\n'
for var in $(cat text_norm/abbr_acro_as_letters.txt | awk '{ print length, $0 }' | sort -nrs | cut -d" " -f2)
do
    var1=$(echo $var | sed 's/./& /g')
    sed -i "s/\b$var\b/$var1/g" ${dir}/pause_text_exp1.tmp
done
sed -r -i 's/[[:space:]]+/ /g' ${dir}/pause_text_exp1.tmp

# Make the regex pattern
tr "\n" "|" < text_norm/acronyms_as_words.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > text_norm/acronyms_as_words_pattern.tmp

# Capitalize 
srun sed -r 's:(\b'$(cat text_norm/acronyms_as_words_pattern.tmp)'\b):\U\1:g' ${dir}/pause_text_exp1.tmp > ${dir}/pause_text_exp1_acroCS.tmp

python3 local/althingi_replace_plain_text.py ${dir}/pause_text_exp1_acroCS.tmp ${dir}/pause_text_exp2.tmp
sed -re "s:\bofl\b:og fleira:g" -e "s:\bþe\b:það er:g" -e "s:\bþmt\b:þar með talið:g" \
    -e "s:\bdkr\b:danskar krónur:g" -e "s:\bnkr\b:norskar krónur:g" -e "s:\bskr\b:sænskar krónur:g" \
    < ${dir}/pause_text_exp2.tmp > ${dir}/pause_text_exp3.tmp

# echo "Capitalize words in the texts, that are capitalized in the pron dict"
comm -12 <(sed -r 's:.*:\L&:' ${prondir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(tr " " "\n" < ${dir}/pause_text_exp3.tmp | sed -re 's/[^a-záðéíóúýþæö]+//g'| egrep -v "^\s*$" | sort -u) > ${dir}/propernouns_althingi_texts.txt
# Make the regex pattern
tr "\n" "|" < ${dir}/propernouns_althingi_texts.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${dir}/propernouns_althingi_texts_pattern.tmp

# Capitalize
srun sed -r "s:(\b$(cat ${dir}/propernouns_althingi_texts_pattern.tmp)\b):\u\1:g" ${dir}/pause_text_exp3.tmp > $out

exit 0

