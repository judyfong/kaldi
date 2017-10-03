#!/usr/bin/env python
# coding: utf-8

# Match short segments, clean for ASR training, to punctuation training texts, which contain punctuation tokens, but are otherwise similar (whole speeches).

import sys
import os
import codecs

# I need to load the text files, all segments for the speech and the speech itself, containing punctuation tokens.
#speech = sys.argv[1].split()
with codecs.open(sys.argv[1],'r',encoding='utf-8') as f1:
    speech = f1.read().strip()
with codecs.open(sys.argv[2],'r',encoding='utf-8') as f2:
    segments = f2.read().strip().splitlines()
        
# Split the speech and split the first speech segment
j=0 # loop through speech
mo_space_iter=re.finditer(" ",speech)
space_ind = [m.start() for m in mo_space_iter]
space_ind.append(len(speech))
# Punctuation token pattern
p=re.compile("[^ a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ][A-Z]+")
new_segments=[]
for segment in segments:
    first_space = segment.find(" ")
    seqid, transcript = segment[:first_space], segment[first_space+1:]
    translist=transcript.split()
    # loop through segment
    i=0
    # Match the first word in the segment
    mo = re.search(translist[i],speech)
    new_trans_start=mo.start()
    j = space_ind.index(mo.end())
    while i < len(translist):
        if speech[space_ind[j]+1:space_ind[j+1]] == translist[i+1]:
            i+=1
            j+=1
        elif p.match(speech[space_ind[j]+1:space_ind[j+1]]):
            j+=1
        else:
            i=0
            mo = re.search(translist[i],speech[mo.end():])
            j = space_ind.index(mo.end())
            new_trans_start=mo.start()
    new_segments.append(seqid+" "+speech[new_trans_start:space_ind[j]])
        
# Select the first word in the speech segment and start looping through the speech till I find a match, then append it to a new list. Check if the second word matches, if so, then I add it to the list. If it is a punctuation token I also add it to the list. If it does not match at all. Then I empty the list, and start looking again for a match for the first word in the segment.
