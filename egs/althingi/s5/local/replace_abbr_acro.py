#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Replaces some abbreviations.
import sys,re

if (len(sys.argv) < 3):
	print("Need 2 arguments: input file and output file!")
	sys.exit()

with open(sys.argv[1],'r',encoding='utf-8') as in_file:
    text = in_file.read().strip()
out_file = open(sys.argv[2], 'w',encoding='utf-8')

text = re.sub(" amk "," að minnsta kosti ",text)
text = re.sub(" dr "," doktor ",text)
text = re.sub(" etv "," ef til vill ",text)
text = re.sub(" frh "," framhald ",text)
text = re.sub(" fyrrv "," fyrrverandi ",text)
text = re.sub(" mas "," meira að segja ",text)
text = re.sub(" ma "," meðal annars ",text)
text = re.sub(" nk "," næstkomandi ",text)
text = re.sub(" nr "," númer ",text)
text = re.sub("osfrv"," og svo framvegis ",text)
text = re.sub(" sbr "," samanber ",text)
text = re.sub(" skv "," samkvæmt ",text)
text = re.sub(" td"," til dæmis ",text)
text = re.sub("uþb"," um það bil ",text)
text = re.sub(" utanrrh "," utanríkisráðherra ",text)
text = re.sub(" þús "," þúsund ",text)
text = re.sub(" ags "," a g s ",text)
text = re.sub(" ehf "," e h f ",text)
text = re.sub(" hf "," h f ",text)
text = re.sub(" mbl"," m b l ",text)
text = re.sub(" ees "," e e s ",text)
text = re.sub(" esb "," e s b ",text)
text = re.sub(" eb "," e b ",text)
text = re.sub(" ebe "," e b e ",text)
text = re.sub(" ísí "," í s í ",text)
text = re.sub(" oecd "," o e c d ",text)
text = re.sub(" ohf "," o h f ",text)
text = re.sub(" sáá "," s á á ",text)
text = re.sub(" dv "," d v ",text)
text = re.sub(" fme "," f m e ",text)
text = re.sub(" hs "," h s ",text)
text = re.sub(" lsr "," l s r ",text)
text = re.sub(" bhm "," b h m ",text)
text = re.sub(" bsrb "," b s r b ",text)
text = re.sub(" kí "," k í ",text)
text = re.sub(" mnd "," m n d ",text)
text = re.sub(" psa "," p s a ",text)
text = re.sub(" vg "," v g ",text)
text = re.sub(" þssí "," þ s s í ",text)

print(text, file=out_file)
out_file.close()
