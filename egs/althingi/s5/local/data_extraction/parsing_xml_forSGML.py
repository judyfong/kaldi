#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import codecs
import re
from bs4 import BeautifulSoup

def Extract(soup):
    """
    Extract speaker name, mp3 and xml location online for each speech from an xml containing
    information on all speeches given in a session (created by scrape_althingi_info.php)
    """
    meta = []
    for speech in soup.find_all('ræða'):
        baseid="rad" + re.sub('[-:]','',speech.ræðahófst.string)
        if speech.slóðir.sgml != None:
            l=[baseid, speech.ræðumaður.nafn.string, speech.slóðir.sgml.string]
        #else:
        #    l=[baseid, speech.ræðumaður.nafn.string, mp3]
        meta.append('\t'.join(l))
    return meta

if __name__ == "__main__":

    #soup = BeautifulSoup(open(sys.argv[1], 'r'), 'xml')
    with codecs.open(sys.argv[2],'w',encoding='utf-8') as fout:
        with codecs.open(sys.argv[1],'r',encoding='utf-8') as fin:
            
            soup = BeautifulSoup(fin, 'lxml-xml')
            meta = Extract(soup)
            
        fout.write('\n'.join(meta)+'\n')
