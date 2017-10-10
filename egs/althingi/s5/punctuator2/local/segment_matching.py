#!/usr/bin/env python
# encoding: utf-8

import sys
import codecs
import re
from fuzzywuzzy import fuzz
from fuzzywuzzy import process # Fuzzy matching

# NOTE! Add try statements and skip segment if doesnt work!

def match(segments,speech):
    """Match short segments, clean of punctuations but containing pause information, to punctuation training texts, which contain punctuation tokens, but are otherwise similar (whole speeches). The short segments have no abbreviations, while the whole speeches are partially unexpanded.
    """
    # Punctuation token pattern
    p=re.compile("[^ a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ0-9<][A-Z]+")

    match_dict=match_dictionary()
    approx_match_dict=approx_match_dictionary()
    j=0 # loop through the speech
    speechlist=speech.split()
    newsegments=[]
    for segment in segments:
        #print("segment: ",segment)
        segmlist=segment.split()
        # Next 3 lines: Select a part of the speech that is the same length as the segment
        # (can also be longer if contains punctuations) and calculate the match
        l=len(segmlist[1::2])
        npunct=len(re.findall(p,' '.join(speechlist[j:j+l]), flags=0))
        # Implement what happens when find "<NUM>" (num can be followed by %, what to do about that?)

        speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
        indices = [i for i,x in enumerate(speechtrans) if x == "<NUM>"]
        #print("speechlist[j:j+l+npunct]: ",speechlist[j:j+l+npunct])
        #print("indices: ",indices)
        # Try to match the words that come before and after the "<NUM>" token with words in the segment.
        # NOTE! In collapse_num shouldn't I be using speechtrans instead of speechlist?
        if indices !=[]:
            segmlist=collapse_num(speechtrans,segmlist,indices,match_dict)

        if segmlist==[]:
                print("Returned segment is empty: ", segment.split()[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)
        #print("segmlist returned:",segmlist)
        trans=segmlist[1::2]
        #print("trans: ",trans)
        l=len(trans)
        npunct=len(re.findall(p,' '.join(speechlist[j:j+l+npunct]), flags=0))
        # Collapse the words in between these two in the segment. Keep the percentages.
        speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
        score=fuzz.ratio(' '.join(trans),' '.join(speechtrans))
        #print("text: ",' '.join(speechlist[j:j+l+npunct]))
        #print("score: ",score)
        
        # Fix if last word is a punctuation or if first/last is an abbreviation
        first=speechlist[j]
        last=speechlist[j+l+npunct-1]
        if first in approx_match_dict.keys():
            first=approx_match_dict[first]

        if p.match(last):
            last=speechlist[j+l+npunct-2]
        if last in approx_match_dict.keys():
            last=approx_match_dict[last]

        #print("first, last: ",first, last)
        k=j

        # Slide the window one word to the right and see if the Levenshtein distance decreases
        # I have these weird limits such that "háttvirt" can be matched to "háttvirtrar"
        while fuzz.ratio(trans[0],first) < 80 or fuzz.ratio(trans[-1],last) < 80 or score < 85:
            #print("k,j,trans[0],first,trans[-1],last],score: ",k,j,trans[0],first,trans[-1],last,score)
            j+=1
            #score=score1
            npunct=len(re.findall(p,' '.join(speechlist[j:j+l+npunct]), flags=0))
            if p.match(speechlist[j+l+npunct]):
                npunct+=1
            #npunct=len(re.findall(p,' '.join(speechlist[j:j+l]), flags=0))
            speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
            indices = [i for i,x in enumerate(speechtrans) if x == "<NUM>"]
            #print("indices: ",indices)
            # Try to match the words that come before and after the "<NUM>" token with words in the segment.
            if indices !=[]:
                segmlist=collapse_num(speechtrans,segmlist,indices,match_dict)

            if segmlist==[]:
                print("Returned segment is empty: ", segment.split()[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)
            #print("segmlist returned:",segmlist)
            trans=segmlist[1::2]
            #print("trans: ",trans)
            l=len(trans)
        
            speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
            #print("speechtrans: ", speechtrans)
            score=fuzz.ratio(' '.join(trans),' '.join(speechtrans))
            #print("j, score: ",j,score)
            #print("j, text: ",j,' '.join(speechlist[j:j+l+npunct]))
            first=speechlist[j]
            last=speechlist[j+l+npunct-1]
            if first in approx_match_dict.keys():
                first=approx_match_dict[first]
            if p.match(last):
                last=speechlist[j+l+npunct-2]
            if last in approx_match_dict.keys():
                last=approx_match_dict[last]
                
            if j>k+70:
                print("Match not found for segment: ", segmlist[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)
        #print("after while loop")
        #print("k,j,trans[0],first,trans[-1],last,score: ",k,j,trans[0],first,trans[-1],last,score)
        newsegm=[segmlist[0]] # Start with the uttID
        #print("j: ",j)
        #print("speechlist[j+l+npunct]: ",speechlist[j+l+npunct])
        textit=0
        pauseit=2 # Skip words. Use the ones from the punct. transcript
        #print("length of speechsegm: ", len(speechlist[j:j+l+npunct]))
        if p.match(speechlist[j+l+npunct]):
            npunct+=1
        #print("npunct: ",npunct)
        # Weave together the two segments since a best match is found
        #print(speechlist[j:j+l+npunct])
        while textit < len(speechlist[j:j+l+npunct]):
            #print(textit,pauseit)
            if p.match(speechlist[j+textit]):
                newsegm.append(speechlist[j+textit])
                textit+=1
            else:
                newsegm.append(speechlist[j+textit])
                newsegm.append(segmlist[pauseit])
                textit+=1
                pauseit+=2
        #print("newsegm: ",newsegm)
        #print(" ")
        newsegments.append(' '.join(newsegm))
        j=j+l+npunct # Start matching the next segment where the current match ended
    return '\n'.join(newsegments)+'\n'


def collapse_num(speechpart,slist,indices,match_dict):
    #print("in collapse_num")
    for idx in indices:
        #print("idx: ",idx)
        if idx == 0:
            idx_segm_before = [-1]
            if speechpart[idx+1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[idx+1]],' '.join(slist))
                idx_segm_after = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_after = [i for i,x in enumerate(slist) if x == speechpart[idx+1]]
        elif idx == len(slist[1::2])-1:
            if speechpart[idx-1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[idx-1]],' '.join(slist))
                idx_segm_before = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_before = [i for i,x in enumerate(slist) if x == speechpart[idx-1]]
            idx_segm_after = [len(slist)]
            #print("idx=length-1, slist: ",slist)
        elif idx >= len(slist[1::2]):
            print("idx is out of bounds")
            continue
        else:
            pidx=idx
            if speechpart[pidx-1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[pidx-1]],' '.join(slist))
                idx_segm_before = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_before = [i for i,x in enumerate(slist) if x == speechpart[pidx-1]]
            nidx=idx
            if speechpart[nidx+1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[nidx+1]],' '.join(slist))
                idx_segm_after = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_after = [i for i,x in enumerate(slist) if x == speechpart[nidx+1]]
            if idx_segm_after == []:
                idx_segm_after = [len(slist)]       
            #print("idx_segm_before: ",idx_segm_before)
            #print("idx_segm_after: ",idx_segm_after)
            #print("else: slist: ",slist)
        slist=best_num_match(speechpart,slist,idx_segm_before,idx_segm_after)
    return slist

def match_dictionary():
    k=["%","bls","gr","hv","hæstv","kl","klst","km","kr","málsl",\
       "málsgr","mgr","millj","nr","tölul","umr","þm","þskj","þús"]
    v=[r'prósent[a-záðéíóúýþæö]*',r'blaðsíð[a-záðéíóúýþæö]*\b',\
       r'\bgrein(?:ar)?\b',r'háttvirt[a-záðéíóúýþæö]*\b',\
       r'hæstvirt[a-záðéíóúýþæö]*\b',r'\bklukkan\b',\
       r'\bklukkustund[a-záðéíóúýþæö]*\b',r'\bkílómetr[a-záðéíóúýþæö]*\b',\
       r'\bkrón(?:a|u|ur|um)?\b',r'\bmálslið[a-záðéíóúýþæö]*\b',\
       r'málsgrein[a-záðéíóúýþæö]*',r'málsgrein[a-záðéíóúýþæö]*',\
       r'milljón[a-záðéíóúýþæö]*',r'\bnúmer\b',r'\btölulið[a-záðéíóúýþæö]*\b',\
       r'\bumræð[a-záðéíóúýþæö]+\b',r'\bþingm[a-záðéíóúýþæö]+',\
       r'þingskj[a-záðéíóúýþæö]*',r'\bþúsund[a-záðéíóúýþæö]*\b']
    d={}
    for i in range(len(k)):
        d[k[i]] = v[i]
    return d

def approx_match_dictionary():
    k=["%","bls","gr","hv","hæstv","kl","klst","km","kr","málsl",\
       "málsgr","mgr","millj","nr","tölul","umr","þm","þskj","þús"]
    v=['prósent','blaðsíð',\
       'grein','háttvirt',\
       'hæstvirt','klukkan',\
       'klukkustund','kílómetr',\
       'krón','málslið',\
       'málsgrein','málsgrein',\
       'milljón','númer','tölulið',\
       'umræð','þingm',\
       'þingskj','þúsund']
    d={}
    for i in range(len(k)):
        d[k[i]] = v[i]
    return d

def best_num_match(speechpart,slist,idx_segm_before,idx_segm_after):
    strans_best=0
    slist_best=[]
    for ia in idx_segm_after:
        for ib in idx_segm_before:
            if ib < ia:
                #print("ib: ",ib)
                #print("ia: ",ia)
                slist2=slist[:ib+2]
                slist2.append("<NUM>")
                slist2.extend(slist[ia-1:])
                #print("slist2: ",slist2)
                trans=slist2[1::2]
                ltrans=len(trans)
                strans=fuzz.ratio(' '.join(trans),' '.join(speechpart[:ltrans]))
                #print("ltrans, strans, trans: ",ltrans, strans, trans)
                if strans > strans_best:
                    strans_best=strans
                    slist_best=slist2
                #print("strans_best: ",strans_best)
                #print("slist_best: ",slist_best)
    return slist_best

    
if __name__ == '__main__' :

    # I need to load the text files, all segments for the speech and the speech itself, containing punctuation tokens.

    speech = sys.argv[1]
    with codecs.open(sys.argv[2],'r',encoding='utf-8') as fpause:
        with codecs.open(sys.argv[3],'a',encoding='utf-8') as fout:
            segments = fpause.read().strip().splitlines()

            newsegments = match(segments,speech)
            fout.write(newsegments)

