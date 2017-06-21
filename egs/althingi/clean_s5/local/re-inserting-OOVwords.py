# coding: utf-8

import sys
import codecs

# 2017 Inga Rún
# Mapped words not in numbertexts.txt to <word> before expanding abbreviations and numbers
# To re-insert the "OOV" words I use the expanded text and the list of words mapped to <word>
# Example:
# utils/slurm.pl ${datadir}/split${nj}/log/re-inserting-OOVwords.$JOB.log python local/re-inserting-OOVwords.py ${datadir}/split${nj}/text_expanded.$JOB.txt ${datadir}/split${nj}/MappedWords_Job${JOB}.txt ${datadir}/split${nj}/text_expanded_wOOVwords.$JOB.txt

oov_ind=0
with codecs.open(sys.argv[3], 'w', 'utf-8') as out_txt:
    with codecs.open(sys.argv[2], 'r', 'utf-8') as oov_txt:
        with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

            textlist = text.read().strip().split()
            oovlist = oov_txt.read().strip().split('\n')
            indices = [i for i, x in enumerate(textlist) if x == "<word>"]

            for index in indices:
                textlist[index] = oovlist[oov_ind]
                oov_ind+=1
    print "Last index used in the oov list: ", oov_ind-1            
    out_txt.write(' '.join(textlist) + '\n')
