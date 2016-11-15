#!/usr/bin/python3

# Takes as input wps.txt, created with words_per_second.sh

import sys
import matplotlib.pyplot as plt

# Takes in wps.txt
with open(sys.argv[1],'r',encoding='utf-8') as f:
    wps = [float(line.strip().split()[0]) for line in f.readlines()]

plt.hist(wps, 50)
plt.xlabel('Words/second')
plt.ylabel('Count')
plt.title('Words per second in Althingi segments')
#plt.axis([40, 160, 0, 0.03])
plt.grid(True)

plt.show()
