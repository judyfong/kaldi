#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Filters a word list by patterns: words containing digits, words not containing any vowels,
tokens containing punctuation. Writes one file for each pattern.
The input word list can be a simple word list or a frequency list with
tab separated word and count.

ToDo: check output cons_patterns, not all vowels yet included
Created on Tue Jul  5 15:18:23 2016

@author: anna
"""
import sys, re


def write_freq_list(wordlist, filename):
    writer = open(filename, 'w')
    for pair in wordlist:
        writer.write(pair)
    writer.close()


def write_simple_list(wordlist, filename):
    writer = open(filename, 'w')
    for word in wordlist:
        writer.write(word)
    writer.close()


def write_list(wordlist, filename):
    writer = open(filename, 'w')
    for word in wordlist:
        writer.write(word)
    writer.close()


infilename = sys.argv[1]

infile = open(infilename)
lines = infile.readlines()

digit_pattern = re.compile('\d')
punct_pattern = re.compile('[^\d\wáéíóúýæöþð]')
vowel_pattern = re.compile('[aeiouáéíóúyýöæ]')

digits = []
punct_list = []
cons_list = []
rest_list = []

for line in lines:
    if ('\t' in line):
        pair = line.split('\t')
        word = pair[0]
    else:
        word = line.strip()

    if (digit_pattern.search(word)):
        digits.append(line)
    elif (punct_pattern.search(word.lower())):
        punct_list.append(line)
    elif (not vowel_pattern.search(word.lower())):
        cons_list.append(line)
    else:
        rest_list.append(line)


write_list(digits, 'digit_patterns.txt')
write_list(punct_list, 'punct_patterns.txt')
write_list(cons_list, 'cons_patterns.txt')
write_list(rest_list, 'no_pattern_match.txt')

