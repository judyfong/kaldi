#!/usr/bin/python3

import sys
import re

def MinEditDist(v,w):
    """Find the minimum edit distance between two words and
    return it. Stop the search when it exceeds two edits."""
    s = [[float("inf")]*(len(w)+1) for i in range(len(v)+1)]
    s[0][:] = range(len(w)+1)
    for i in range(len(v)+1):
        s[i][0] = i
    for i in range(1,len(v)+1):
        for j in range(1,len(w)+1):
            if v[i-1] == w[j-1]:
                s[i][j] = min(s[i-1][j]+1, s[i][j-1]+1,s[i-1][j-1])
            else:
                s[i][j] = min(s[i-1][j]+1, s[i][j-1]+1,s[i-1][j-1]+1)
        if min(s[i][:]) > 2:
            return 9
    return s[-1][-1] 

    
if __name__ == "__main__":

    #with open(sys.argv[1],'r',encoding='utf-8') as f1:
       #speech_bb  = f1.read().strip()
    speech_bb = sys.argv[1] # sys.argv[1] is a shell variable
    speech_bb_fixed = open(sys.argv[2],'a',encoding='utf-8')
    with open(sys.argv[3],'r',encoding='utf-8') as f3:
       vocab_bb  = f3.read().splitlines()
    with open(sys.argv[4],'r',encoding='utf-8') as f4:
       vocab_endanlegt  = f4.read().splitlines()
    
    # Now I assume there is only one word that approx. matches
    for word in vocab_bb:
        for w_endanlegt in vocab_endanlegt:
            dist=MinEditDist(word,w_endanlegt)
            if dist < 3:
                # Substitute if a match was found
                speech_bb = re.sub(" "+word+" "," "+w_endanlegt+" ",speech_bb)
                break

    print(speech_bb, file=speech_bb_fixed)
    speech_bb_fixed.close()
    

