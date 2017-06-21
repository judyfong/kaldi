# coding: utf-8

from __future__ import division
from nltk.tokenize import word_tokenize

import codecs
import re
import sys

WORD = '<word>'


def process_line(line,oovlist):

    tokens = word_tokenize(line)
    output_tokens = []
    word_list = []
    
    for token in tokens:
        if token in oovlist:
            output_tokens.append(WORD)
            word_list.append(token)
        else:
            output_tokens.append(token)

    return [" ".join(output_tokens) + " ", '\n'.join(word_list)]


with codecs.open(sys.argv[4], 'w', 'utf-8') as OOVlist_out:
    with codecs.open(sys.argv[3], 'w', 'utf-8') as out_txt:
        with codecs.open(sys.argv[2], 'r', 'utf-8') as OOVlist_in:
            with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

                oovlist = OOVlist_in.read().splitlines()
                for line in text:
                    line, mapped_words = process_line(line,oovlist)

                    out_txt.write(line + '\n')
                    if len(mapped_words) > 0:
                         OOVlist_out.write(mapped_words + '\n')

