# coding: utf-8

import sys
import codecs

# temp file

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
