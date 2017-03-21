#!/usr/bin/python3

# Takes as input wps.txt, created with words_per_second.sh

import sys
import matplotlib.pyplot as plt
import numpy as np
# Takes in wps.txt
with open(sys.argv[1],'r',encoding='utf-8') as f:
    wps = []
    wer = []
    for line in f:
        line2 = line.split()
        wps.append(float(line2[1]))
        wer.append(float(line2[2]))

plt.plot(wps, wer, 'o')
plt.plot(wps, np.poly1d(np.polyfit(wps, wer, 1))(wps))
plt.xlabel('Words/sec per speaker')
plt.ylabel('%WER per speaker')

#plt.axis([0, 32, 0, 12])
plt.grid(True)
#plt.xticks(np.arange(0, 32, 2.0))
plt.show()
