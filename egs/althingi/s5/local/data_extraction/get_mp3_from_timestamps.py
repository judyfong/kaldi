#!/usr/bin/env python
# coding: utf-8

import codecs
import sys
import re
import urllib

def getMP3(stamps):
    """Download an mp3 file from the Althingi website given 
    the date of the speech, plus the start and end times"""

    for line in stamps:
        date,start,_,end = line.split()
        mp3url = 'http://www.althingi.is/raedur/?start=' + date + 'T' + start + '&end=' + date + 'T' + end
        print 'mp3url: ' + mp3url

        date = re.sub('-', '', date)
        start = re.sub(':', '', start)
        end = re.sub(':', '', end)

        rad = 'rad' + date + 'T' + start
        audio_file_name = '/home/staff/inga/kaldi/egs/althingi/s5/recognize/chain/notendaprof2/audio/' + rad + '.mp3'
        urllib.urlretrieve(mp3url, audio_file_name)


if __name__ == "__main__":
    with codecs.open(sys.argv[1],'r',encoding='utf-8') as fstamps:
        stamps = fstamps.read().splitlines()

        getMP3(stamps)
