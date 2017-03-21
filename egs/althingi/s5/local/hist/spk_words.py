#!/usr/bin/python3

# Takes as input wps.txt, created with words_per_second.sh

import sys
import matplotlib.pyplot as plt
import numpy as np
# Takes in wps.txt
with open(sys.argv[1],'r',encoding='utf-8') as f:
    nwords = [float(line.strip().split()[2]) for line in f]
        
plt.hist(nwords, 20)
plt.xlabel('Number of words per speaker')
#plt.xlabel('Words/second')
#plt.xlabel('Lengd [min]')
plt.ylabel('#Speakers')
#plt.ylabel('Tíðni')
#plt.title('Words per second in Althingi segments')
#plt.title('%WER distribution over speakers')
#plt.title('Average words per second per speaker')
#plt.title('Lengd hjóðskráa í heildargagnagrunni')
#plt.axis([0, 32, 0, 12])
plt.grid(True)
#plt.xticks(np.arange(0, 32, 2.0))
plt.show()
