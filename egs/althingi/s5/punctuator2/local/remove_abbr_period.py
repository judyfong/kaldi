#!/usr/bin/env python3

# Replaces some abbreviations.
import sys,re

if (len(sys.argv) < 4):
	print("Need 3 arguments: input file, list over abbreviations in the text norm lexicon and output file!")
	sys.exit()

with open(sys.argv[1],'r',encoding='utf-8') as in_file:
    text = in_file.read().strip()
out_file = open(sys.argv[3], 'w',encoding='utf-8')

abbr = ["amk","dr","etv","frh","mas","ma","nk","nr","osfrv","sbr","skv","td","uþb","utanrrh","þús"]

with open(sys.argv[2],'r',encoding='utf-8') as abbr_lex:
    tags = abbr_lex.read().strip().split()

tags.extend(abbr)
for tag in tags:
    text = re.sub(r'\b' + tag + '\.', tag, text, flags=re.I)

print(text, file=out_file)
out_file.close()
