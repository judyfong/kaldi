#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Filters words containing non-Icelandic characters, like François, Vesterålen, Voices

"""

import sys, re

wordlist = open(sys.argv[1])

#non_ice_pattern = re.compile('[^\wáéíóúýæöþð]', re.IGNORECASE)
non_ice_pattern = re.compile('[^\wáéíóúýæöþðÁÉÍÓÚÝÆÖÞÐ]', re.ASCII)
ignore_ascii = re.compile('[cw]', re.IGNORECASE)

foreign = []
valid = []
for word in wordlist.readlines():
    if non_ice_pattern.search(word.strip()):
        foreign.append(word)
    elif ignore_ascii.search(word):
        foreign.append(word)
    else:
        valid.append(word)

out = open('foreign_words.txt', 'w')
out.writelines(foreign)

out = open('ice_words.txt', 'w')
out.writelines(valid)