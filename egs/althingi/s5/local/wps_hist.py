#!/usr/bin/python3

# Takes as input wps.txt, created with words_per_second.sh

import sys
import matplotlib.pyplot as plt
import numpy as np
# Takes in wps.txt
with open(sys.argv[1],'r',encoding='utf-8') as f:
    #wps = [float(line.strip().split()[0]) for line in f.readlines()]
    #wps = [float(line.strip().split()[4]) for line in f.readlines()] # average wps per speaker
    next(f)
    wps = [float(line.strip().split()[4]) for line in f]
        
plt.hist(wps, 45)
plt.xlabel('%WER')
#plt.xlabel('Words/second')
#plt.xlabel('Lengd [min]')
plt.ylabel('Count')
#plt.ylabel('Tíðni')
#plt.title('Words per second in Althingi segments')
plt.title('%WER distribution over speakers')
#plt.title('Average words per second per speaker')
#plt.title('Lengd hjóðskráa í heildargagnagrunni')
#plt.axis([40, 160, 0, 0.03])
#plt.grid(True)
plt.xticks(np.arange(0, 30, 2.0))
plt.show()
