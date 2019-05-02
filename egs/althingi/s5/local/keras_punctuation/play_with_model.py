# coding: utf-8

import sys, os
import codecs
import numpy as np
sys.path.insert(0, 'local/punctuation')
import data
import main_attention

os.environ['LD_LIBRARY_PATH'] = '/usr/local/cuda-9.0/lib64/'
#os.environ["CUDA_DEVICE_ORDER"] = "PCI_BUS_ID"
#os.environ["CUDA_VISIBLE_DEVICES"]="" 

import tensorflow as tf
from keras import backend as K

num_cores = 4

# if GPU:
#     num_GPU = 1
#     num_CPU = 1
# if CPU:
num_CPU = 1
num_GPU = 0

config = tf.ConfigProto(intra_op_parallelism_threads=num_cores,\
        inter_op_parallelism_threads=num_cores, allow_soft_placement=True,\
        device_count = {'CPU' : num_CPU, 'GPU' : num_GPU})
session = tf.Session(config=config)
K.set_session(session)

from keras.models import load_model
from keras.preprocessing.sequence import pad_sequences

def to_array(arr, dtype=np.int32):
    # minibatch of 1 sequence as column
    return np.array([arr], dtype=dtype).T

def convert_punctuation_to_readable(punct_token):
    if punct_token == data.SPACE:
        return " "
    else:
        return punct_token[0]

def punctuate(model, word_vocabulary, punctuation_vocabulary, reverse_punctuation_vocabulary, reverse_word_vocabulary, text, f_out, show_unk):

    if len(text) == 0:
        sys.exit("Input text from stdin missing.")

    text = [w for w in text.split() if w not in punctuation_vocabulary] + [data.END]

    i = 0

    while True:

        subsequence = text[i:i+data.MAX_SEQUENCE_LEN]

        if len(subsequence) == 0:
            break

        converted_subsequence = [word_vocabulary.get(w, word_vocabulary[data.UNK]) for w in subsequence]
        if show_unk:
            subsequence = [reverse_word_vocabulary[w] for w in converted_subsequence]

        if len(converted_subsequence) < data.MAX_SEQUENCE_LEN:
            converted_subsequence = pad_sequences([converted_subsequence], maxlen=data.MAX_SEQUENCE_LEN, value=main_attention.PADDING_VALUE)
            y = model.predict(converted_subsequence)
        else:
            y = model.predict(np.asarray([converted_subsequence]))
        f_out.write(subsequence[0])

        last_eos_idx = 0
        punctuations = []
        for y_t in y[0]:

            p_i = np.argmax(y_t)
            punctuation = reverse_punctuation_vocabulary[p_i]

            punctuations.append(punctuation)

            if punctuation in data.EOS_TOKENS:
                last_eos_idx = len(punctuations) # we intentionally want the index of next element

        if subsequence[-1] == data.END:
            step = len(subsequence) - 1
        elif last_eos_idx != 0:
            step = last_eos_idx
        else:
            step = len(subsequence) - 1

        for j in range(step):
            f_out.write(" " + punctuations[j] + " " if punctuations[j] != data.SPACE else " ")
            if j < step - 1:
                f_out.write(subsequence[1+j])

        if subsequence[-1] == data.END:
            break

        i += step


if __name__ == "__main__":

    if len(sys.argv) > 1:
        model_file = sys.argv[1]
    else:
        sys.exit("Model file path argument missing")

    show_unk = False
    if len(sys.argv) > 2:
        show_unk = bool(int(sys.argv[2]))

    print("Loading model parameters...")
    model = load_model(model_file)

    word_vocabulary = data.read_vocabulary(data.WORD_VOCAB_FILE)
    punctuation_vocabulary = data.iterable_to_dict(data.PUNCTUATION_VOCABULARY)

    reverse_word_vocabulary = {v:k for k,v in word_vocabulary.items()}
    reverse_punctuation_vocabulary = {v:k for k,v in punctuation_vocabulary.items()}

    with codecs.getwriter('utf-8')(sys.stdout) as f_out:
        while True:
            text = input("\nTEXT: ")
            punctuate(model, word_vocabulary, punctuation_vocabulary, reverse_punctuation_vocabulary, reverse_word_vocabulary, text, f_out, show_unk)
