# coding: utf-8

import sys
import codecs

# 2017 Inga Rún
# Punctuator maps all numbers to the token <NUM>.
# To re-insert the numbers I use the text coming from punctuator2, the list
# of numbers mapped to <NUM>, the index for where in the list to start (0 for dev files, for eval files it is the last index used for the dev files plus one) and an output file, which will contain the text with numbers.
# If run from ~/punctuator2/example:
# srun python local/capitalize_names.py punctuator_out_wNumbers.tmpname.tmp text_wCap.tmp
# NOTE! In the future I'll have num_ind=0. Now dev and test files are not preprocessed together anymore. Keep this like it is for now. Remember to change!

with codecs.open(sys.argv[3], 'w', 'utf-8') as out_txt:
    with codecs.open(sys.argv[2], 'r', 'utf-8') as name_txt:
        with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

            textlist = text.read().strip().split()
            namelist = name_txt.read().strip().split('\n')
            new_text = []
            for word in textlist:
                if word.title() in namelist:
                    new_text.append(word.title())
                else:
                    new_text.append(word)

    out_txt.write(' '.join(new_text) + '\n')
