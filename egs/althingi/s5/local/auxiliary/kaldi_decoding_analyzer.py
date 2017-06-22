#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Anna Bjork Nikulasdottir - 2016

"""
    Analyze the errors from Kaldi decoding, per_utt results:

    is_is-althingi1_04-2011-11-30T16:55:30.601205 ref  símaskráin  ***  komin  út
    is_is-althingi1_04-2011-11-30T16:55:30.601205 hyp  símaskráin   er  komin  út
    is_is-althingi1_04-2011-11-30T16:55:30.601205 op        C       I     C     C
    is_is-althingi1_04-2011-11-30T16:55:30.601205 #csid 3 0 1 0

    Extract three kinds of errors:
    1) urls
    2) Substitution errors with edit distance = 1
    3) Multiword expressions (no of words in original utterance >= 4) with only one error

"""

import sys
import os
import Levenshtein
from Levenshtein import distance


class DecodedUtterance:
    def __init__(self, utt_id):
        self.utt_id = utt_id
        self.ref = ""
        self.hyp = ""
        self.operations = []
        self.operations_counts = []
        self.sub = 0
        self.ins = 0
        self.delete = 0

    def set_ref(self, prompt):
        self.ref = prompt

    def set_hyp(self, hypothesis):
        self.hyp = hypothesis

    # operation_arr: e.g. [C, I, S, C, C], can be of any length > 1
    def set_operations(self, operations_arr):
        self.operations = operations_arr

    # operation_arr: e.g. [3, 0, 1, 0], fixed length = 4
    def set_operations_count(self, operations_arr):
        self.operations_counts = operations_arr
        self.sub = int(self.operations_counts[1])
        self.ins = int(self.operations_counts[2])
        self.delete = int(self.operations_counts[3])

    def sum_errors(self):
        return self.sub + self.ins + self.delete

    def sum_ins_delete(self):
        return self.ins + self.delete


utt_file = open(sys.argv[1])

utterance_dict = {}
current_id = ""

for line in utt_file.readlines():
    arr = line.split()
    utt_id = arr[0]
    info = arr[1]  # ref=original; hyp=decoding hypothesis; op=operations; #csid=counts of operations
    content = arr[2:]
    if utt_id == current_id:
        decodedUtt = utterance_dict[utt_id]
        if info == 'hyp':
            decodedUtt.set_hyp(' '.join(content))
        elif info == 'op':
            decodedUtt.set_operations(content)
        elif info == '#csid':
            decodedUtt.set_operations_count(content)
    else:
        decodedUtt = DecodedUtterance(utt_id)
        decodedUtt.set_ref(' '.join(content))
        current_id = utt_id

    utterance_dict[utt_id] = decodedUtt

# Extract urls. Urls are always one-word utterances, but the ref line starts with '***' if the hypothesis has performed
# insertions: *** *** *** femin.is
url_endings = ['.is', '.com', '.net']
urls = []
one_added_or_deleted = []
levenshtein_one = []
other_errors = []
correct = []
url_error_sum = 0
one_error_sum = 0
subst_error_sum = 0
other_errors_sum = 0
comp_count = 0
for key in utterance_dict.keys():
    utterance = utterance_dict[key]
    total_errors = utterance.sum_errors()
    ref = utterance.ref
    ref_arr = ref.split()
    last_word = ref_arr[len(ref_arr) - 1]
    hyp = utterance.hyp
    hyp_arr = hyp.split()

    if total_errors == 0:
        correct.append(key + '\t' + ref + '\t' + '0' + '\n')
        continue
    # check for compounds:
    ref_pairs = []
    hyp_pairs = []

    for ind in range(0, len(ref_arr) - 1):
        ref_pairs.append(ref_arr[ind] + ref_arr[ind + 1])

    for ind in range(0, len(hyp_arr) - 1):
        hyp_pairs.append(hyp_arr[ind] + hyp_arr[ind + 1])

    for pair in ref_pairs:
        if pair in hyp_arr:
            print("Compound? " + pair)
            print(ref + '\t' + hyp)
            comp_count += 1

    for pair in hyp_pairs:
        if pair in ref_arr:
            print("Compound? " + pair)
            print(ref + '\t' + hyp)
            comp_count += 1

    #if last_word.endswith('.is') or last_word.endswith('.com') or last_word.endswith('.net'):
    #    urls.append(last_word + '\t' + str(total_errors) + '\n')
    #    url_error_sum += total_errors
    if len(ref_arr) >= 2 and utterance.sum_ins_delete() == 1 and utterance.sub == 0:
        one_added_or_deleted.append(ref + '\t' + utterance.hyp + '\t' + str(total_errors) + '\n')
        one_error_sum += total_errors
    elif utterance.sub == 1 and utterance.sum_ins_delete() == 0:
        hyp_arr = utterance.hyp.split()
        for ind in range(0, len(hyp_arr)):
            if ref_arr[ind] != hyp_arr[ind]:
                dist = Levenshtein.distance(ref_arr[ind], hyp_arr[ind])
                if dist == 1:
                    levenshtein_one.append(
                        ref + '\t' + utterance.hyp + '\t' + ref_arr[ind] + '\t' + hyp_arr[ind] + '\t' + str(dist) + '\n')
                    subst_error_sum += 1
                else:
                    other_errors.append(
                        utterance.utt_id + '\t' +
                        utterance.ref + '\t' +
                        utterance.hyp + '\t' +
                        str(utterance.operations) + '\t' +
                        str(total_errors) + '\n')
                    other_errors_sum += 1

    elif total_errors > 0:

        other_errors.append(
            utterance.utt_id + '\t' +
            utterance.ref + '\t' +
            utterance.hyp + '\t' +
            str(utterance.operations) + '\t' +
            str(total_errors) + '\n')
        other_errors_sum += total_errors

print("found potential compounds: " + str(comp_count))
#print("urls: " + str(len(urls)) + "error count: " + str(url_error_sum))
print("one deletion or insertion error: " + str(one_error_sum))
print("Levenshtein = 1, error count: " + str(subst_error_sum))
print("Other errors: " + str(other_errors_sum))
#print("SUM ERRORS: " + str(url_error_sum + one_error_sum + subst_error_sum + other_errors_sum))
print("SUM ERRORS: " + str(one_error_sum + subst_error_sum + other_errors_sum))


out = open('ins_delete_examples.txt', 'w')
out.writelines(one_added_or_deleted)
out = open('levenshtein_one.txt', 'w')
out.writelines(levenshtein_one)
out = open('other_errors.txt', 'w')
out.writelines(other_errors)

out = open('correct_dev.txt', 'w')
out.writelines(correct)






