#!/bin/bash -eu

set -o pipefail

dir=exp100/tri3_0.2/decode_tg/scoring_kaldi/wer_details

ID=$(head -n1 ${dir}/per_utt | cut -d" " -f1 | cut -d"_" -f1)
grep "hyp" ${dir}/per_utt | head -n8 | tr "\n" " " | perl -pe 's/^[^ ]+|\bhyp\b//g' |  sed -e "s/[[:space:]]\+/ /g" > hyp.tmp
grep "ref" ${dir}/per_utt | head -n8 | tr "\n" " " | perl -pe 's/^[^ ]+|\bref\b//g' |  sed -e "s/[[:space:]]\+/ /g" > ref.tmp 
align-text ark,t:ref.tmp ark,t:hyp.tmp ark,t:${ID}_alignment.txt

python3 -c "
alignment_latex = open('${ID}_alignment_latex.txt','w',encoding='utf-8')
with open('${ID}_alignment.txt','r',encoding='utf-8') as alignment:
    list = alignment.read().strip().split()
    newlist=[]
    for i in range(1,len(list)-2,3):    
        if list[i]=='***':
            newlist.extend(['\colorbox{Thistle}{'+list[i]+'}','\colorbox{Thistle}{'+list[i+1]+'}'])
        elif list[i+1]=='***':
            newlist.extend(['\colorbox{SkyBlue}{'+list[i]+'}','\colorbox{SkyBlue}{'+list[i+1]+'}'])
        elif list[i]!=list[i+1]:
            newlist.extend(['\colorbox{YellowOrange}{'+list[i]+'}','\colorbox{YellowOrange}{'+list[i+1]+'}'])
        else:
            newlist.extend([list[i],list[i+1]])
        newlist.append(';')
    print(' '.join(newlist[:-1]),file=alignment_latex)
alignment_latex.close()"

#fold -s -w82
#sed -i 's,\\\\,\\,' ${ID}_alignment_latex.txt
