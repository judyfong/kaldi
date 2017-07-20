#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2017  Reykjavik University (Author: Anna Björk Nikulásdóttir)
# Apache 2.0

"""
Creates a letter n-gram set from a word list, tests the second word list for matching starts

4-gram 'akra' finds 'akrafjall' 'akrafjalls', 'akraborg' etc.

"""

import sys

valid_file = open(sys.argv[1])
file_to_test = open(sys.argv[2])

ngram_size = 4

ngrams = set()

for word in valid_file.readlines():
    if len(word.strip()) >= ngram_size + 3:
        ngrams.add(word[:ngram_size].lower())

matched_words = []
not_matched = []

for word in file_to_test.readlines():
    if len(word.strip()) >= ngram_size + 3:
        if word[:ngram_size].lower() in ngrams:
            matched_words.append(word)
        else:
            not_matched.append(word)
    else:
        not_matched.append(word)

out = open('potential_valid_leipzig_malromur.txt', 'w')

for word in matched_words:
    out.write(word)

out.close()

out = open('potential_not_valid_leipzig_malromur.txt', 'w')

for word in not_matched:
    out.write(word)

out.close()



