#!/usr/bin/env python3
#
# Replaces occurrences of 'hv. þm.' with the appropriate form of 'háttvirtur þingmaður'.
# Needs a POS-tagged input of the form <word tag word tag word tag ...>
#
# Copyright 2016 Anna Björk Nikulásdóttir
#

import sys, re

if (len(sys.argv) < 3):
        print("Need 2 arguments: input file and output file!")
        sys.exit()

def replace_abbr_tagged1(text, tag):
        newtext = text
        if (tag.endswith("en")):
                newtext = text.replace("hv.", "háttvirtur")
                newtext = newtext.replace("þm.", "þingmaður")
        elif (tag.endswith("eo")):
                newtext = text.replace("hv.", "háttvirtan")
                newtext = newtext.replace("þm.", "þingmann")
        elif (tag.endswith("eþ")):
                newtext = text.replace("hv.", "háttvirtum")
                newtext = newtext.replace("þm.", "þingmanni")
        elif (tag.endswith("ee")):
                newtext = text.replace("hv.", "háttvirts")
                newtext = newtext.replace("þm.", "þingmanns")
        elif (tag.endswith("fn")):
                newtext = text.replace("hv.", "háttvirtir")
                newtext = newtext.replace("Hv.", "Háttvirtir")
                newtext = newtext.replace("þm.", "þingmenn")
        elif (tag.endswith("fo")):
                newtext = text.replace("hv.", "háttvirta")
                newtext = newtext.replace("þm.", "þingmenn")
        elif (tag.endswith("fþ")):
                newtext = text.replace("hv.", "háttvirtum")
                newtext = newtext.replace("þm.", "þingmönnum")
        elif (tag.endswith("fe")):
                newtext = text.replace("hv.", "háttvirtra")
                newtext = newtext.replace("þm.", "þingmanna")
        else:
                print("match for " + text + " but no tag match! - " + tag)

        return newtext

def replace_abbr_tagged2(text, tag):
        newtext = text
        if (tag.endswith("ken")):
                newtext = text.replace("hæstv.", "hæstvirtur")
                newtext = newtext.replace("Hæstv.", "Hæstvirtur")
        elif (tag.endswith("keo")):
                newtext = text.replace("hæstv.", "hæstvirtan")
        elif (tag.endswith("keþ") or tag.endswith("kfþ")):
                newtext = text.replace("hæstv.", "hæstvirtum")
        elif (tag.endswith("kee")):
                newtext = text.replace("hæstv.", "hæstvirts")
        elif (tag.endswith("ven")):
                newtext = text.replace("hæstv.", "hæstvirt")
                newtext = newtext.replace("Hæstv.", "Hæstvirt")
        elif (tag.endswith("veo") or tag.endswith("kfo")):
                newtext = text.replace("hæstv.", "hæstvirta")
        elif (tag.endswith("veþ")):
                newtext = text.replace("hæstv.", "hæstvirtri")
        elif (tag.endswith("vee")):
                newtext = text.replace("hæstv.", "hæstvirtrar")
        elif (tag.endswith("kfn")):
                newtext = text.replace("hæstv.", "hæstvirtir")
                newtext = newtext.replace("Hæstv.", "Hæstvirtir")
        elif (tag.endswith("kfe")):
                newtext = text.replace("hæstv.", "hæstvirtra")
        else:
                print("match for " + text + " but no tag match! - " + tag)

        return newtext

def replace_abbr_tagged3(text, tag):
        newtext = text
        if (tag.endswith("ken")):
                newtext = text.replace("hv.", "háttvirtur")
                newtext = newtext.replace("Hv.", "Háttvirtur")
        elif (tag.endswith("keo")):
                newtext = text.replace("hv.", "háttvirtan")
        elif (tag.endswith("keþ") or tag.endswith("kfþ")):
                newtext = text.replace("hv.", "háttvirtum")
        elif (tag.endswith("kee") or tag.endswith("hee")):
                newtext = text.replace("hv.", "háttvirts")
        elif (tag.endswith("ven") or tag.endswith("hen") or tag.endswith("heo")):
                newtext = text.replace("hv.", "háttvirt")
                newtext = newtext.replace("Hv.", "Háttvirt")
        elif (tag.endswith("veo") or tag.endswith("kfo")):
                newtext = text.replace("hv.", "háttvirta")
        elif (tag.endswith("veþ")):
                newtext = text.replace("hv.", "háttvirtri")
        elif (tag.endswith("vee")):
                newtext = text.replace("hv.", "háttvirtrar")
        elif (tag.endswith("heþ")):
                newtext = text.replace("hv.", "háttvirtu")
        elif (tag.endswith("kfn")):
                newtext = text.replace("hv.", "háttvirtir")
                newtext = newtext.replace("Hv.", "Háttvirtir")
        elif (tag.endswith("kfe")):
                newtext = text.replace("hv.", "háttvirtra")
        else:
                print("match for " + text + " but no tag match! - " + tag)

        return newtext


ICE_WORDCHARS = '[\wáéíóúýöæþð]'

# regex1 should match a string like: 'við ao ræðu nveo hv. sbg2en þm. sbg2en Höskuldar nvee-s Þórhallssonar' where 
#'(hv.) (sbg2en) (þm.) (sbg2en) (Höskuldar) (nvee)' would be the match
regex1 = '(hv\.)\s+(' + ICE_WORDCHARS + '+)\s+(þm\.)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)'
regex2 = '(hæstv\.)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)'
regex3 = '(hv\.)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)\s+(' + ICE_WORDCHARS + '+)'
pattern1 = re.compile(regex1, re.IGNORECASE)
pattern2 = re.compile(regex2, re.IGNORECASE)
pattern3 = re.compile(regex3, re.IGNORECASE)

in_file = open(sys.argv[1])

result_lines = []
for line in in_file:
        text = line.strip()
        match_list = pattern1.findall(text)
        for t in match_list:
                matched_line = ' '.join(t)
                start_pos = text.find(matched_line)
                end_pos = start_pos + len(matched_line)
                replaced = replace_abbr_tagged1(matched_line, t[5]) # Tag on next word after þm. more often correct
                text = text[:start_pos] + replaced + text[end_pos:]
        match_list = pattern2.findall(text)
        for t in match_list:
                matched_line = ' '.join(t)
                start_pos = text.find(matched_line)
                end_pos = start_pos + len(matched_line)
                replaced = replace_abbr_tagged2(matched_line, t[3])
                text = text[:start_pos] + replaced + text[end_pos:]
        match_list = pattern3.findall(text)
        #print(match_list)
        for t in match_list:
                matched_line = ' '.join(t)
                start_pos = text.find(matched_line)
                end_pos = start_pos + len(matched_line)
                replaced = replace_abbr_tagged3(matched_line, t[3])
                text = text[:start_pos] + replaced + text[end_pos:]
              
        # delete pos-tags before storing text again
        wordarr = text.split(' ')
        newarr = wordarr[0::2]
        plaintext = ' '.join(newarr)
        result_lines.append(plaintext)          

in_file.close()

result = '\n'.join(result_lines)

out_file = open(sys.argv[2], 'w')
out_file.write(result)
out_file.close()
