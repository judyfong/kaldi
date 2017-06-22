#!/usr/bin/python3

# Takes as input per_spk_err_sorted, which is obtained in the following way:
# perl -ne 'BEGIN{print "ID #segm #words %correct %err\n"} print;' <(grep "sys" per_spk | sed -e "s/[[:space:]]\+/ /g" | cut -d" " -f1,3-5,9 | sort -n -k5) > per_spk_err_sorted

import sys
import matplotlib.pyplot as plt
import numpy as np
with open(sys.argv[1],'r',encoding='utf-8') as f:
    next(f)
    wps = [float(line.strip().split()[4]) for line in f]
        
plt.hist(wps, 20)
plt.xlabel('%WER per speaker')
plt.ylabel('#Speakers')
plt.title('%WER distribution over speakers')
#plt.axis([0, 20, 0, 10])
#plt.xticks(np.arange(0, 20, 2.0))
plt.grid(True)
plt.show()
