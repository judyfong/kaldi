#!/usr/bin/python3

import sys
import re
from pyxdameraulevenshtein import damerau_levenshtein_distance

if __name__ == "__main__":


    speech_bb = sys.argv[1] # sys.argv[1] is a shell variable
    speech_bb_fixed = open(sys.argv[2],'a',encoding='utf-8')
    with open(sys.argv[3],'r',encoding='utf-8') as f3:
        vocab_bb  = f3.read().splitlines()
        with open(sys.argv[4],'r',encoding='utf-8') as f4:
            vocab_endanlegt  = f4.read().splitlines()
            
    for word in vocab_bb:
        word_dict={}
        replaced = 0
        for w_endanlegt in vocab_endanlegt:
            #dist=MinEditDist(word,w_endanlegt)
            dist = damerau_levenshtein_distance(word, w_endanlegt)
            if dist == 1:
                speech_bb = re.sub(" "+word+" "," "+w_endanlegt+" ",speech_bb)
                replaced = 1
                break
            else:
                word_dict[dist]=w_endanlegt
        # Need to find the min dist and substitute if not already substituted
        if replaced == 0:
            speech_bb = re.sub(" "+word+" "," "+word_dict[min(word_dict,key=int)]+" ",speech_bb)

    print(speech_bb, file=speech_bb_fixed)
    speech_bb_fixed.close()
    

