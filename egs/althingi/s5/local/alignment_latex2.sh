#!/bin/bash -eu

set -o pipefail

dir_dev=exp/nnet5d_gpu/decode_tg_bd_dev/scoring_kaldi/wer_details
dir_eval=exp/nnet5d_gpu/decode_tg_bd_eval/scoring_kaldi/wer_details

ID="BP-rad20160530T205605"
grep "hyp" ${dir_dev}/per_utt | grep $ID > tmp
grep "hyp" ${dir_eval}/per_utt | grep $ID >> tmp
#sort tmp | tr "\n" " " tmp | perl -pe 's/^[^ ]+|\bhyp\b//g' |  sed -e "s/[[:space:]]\+/ /g" > hyp.tmp
sort tmp |  sed -e "s/[[:space:]]\+/ /g" > hyp.tmp

grep "ref" ${dir_dev}/per_utt | grep $ID > tmp
grep "ref" ${dir_eval}/per_utt | grep $ID >> tmp
#tr "\n" " " tmp | perl -pe 's/^[^ ]+|\bref\b//g' |  sed -e "s/[[:space:]]\+/ /g" > ref.tmp
sort tmp |  sed -e "s/[[:space:]]\+/ /g" > ref.tmp

align-text ark,t:ref.tmp ark,t:hyp.tmp ark,t:${ID}_alignment.txt

python3 -c "
alignment_latex = open('${ID}_alignment_latex.txt','w',encoding='utf-8')
with open('${ID}_alignment.txt','r',encoding='utf-8') as alignment:
    mylist = alignment.read().splitlines()
    for line in mylist:
        line = line.split()
        newlist=[line[0],line[1],line[2],';']
        for i in range(4,len(line)-1,3):    
            if line[i]=='***':
                newlist.extend(['\colorbox{Thistle}{'+line[i]+'}','\colorbox{Thistle}{'+line[i+1]+'}'])
            elif line[i+1]=='***':
                newlist.extend(['\colorbox{SkyBlue}{'+line[i]+'}','\colorbox{SkyBlue}{'+line[i+1]+'}'])
            elif line[i]!=line[i+1]:
                newlist.extend(['\colorbox{YellowOrange}{'+line[i]+'}','\colorbox{YellowOrange}{'+line[i+1]+'}'])
            else:
                newlist.extend([line[i],line[i+1]])
            newlist.append(';')
        newlist.append('\\')
        print(' '.join(newlist[:-1]),file=alignment_latex)
alignment_latex.close()"

# Print the hypothesis
cut -d" " -f3- hyp.tmp | tr "\n" " " | sed 's/\*\*\*//g' | sed -e "s/[[:space:]]\+/ /g" | sed -e 's/^[ \t]*//' > ${ID}-hyp.txt

#fold -s -w82
#sed -i 's,\\\\,\\,' ${ID}_alignment_latex.txt
