# coding: utf-8

import sys, os
import codecs
import numpy as np
import subprocess, re
gpu_info = subprocess.check_output(('lspci'))
num_gpus = len(re.findall('VGA compatible controller: NVIDIA Corporation', str(gpu_info), flags=0))

from tensorflow.python.framework.errors_impl import InternalError

os.environ['LD_LIBRARY_PATH'] = '/usr/local/cuda-9.0/lib64/'
#os.environ["CUDA_DEVICE_ORDER"] = "PCI_BUS_ID"

sys.path.insert(0, 'local/punctuation')
import data
from main_attention_batchnorm import PADDING_VALUE, perplexity

# import tensorflow as tf
# import keras
# config = tf.ConfigProto()
# config.gpu_options.allow_growth=True
# sess = tf.Session(config=config)
# keras.backend.set_session(sess)

# def _get_available_devices():
#     from tensorflow.python.client import device_lib
#     for i in range(6):
#     local_device_protos = device_lib.list_local_devices()
#     return [x.name for x in local_device_protos]

# print _get_available_devices()

from keras.models import load_model
from keras.preprocessing.sequence import pad_sequences

MAX_SUBSEQUENCE_LEN = data.MAX_SEQUENCE_LEN #200

def to_array(arr, dtype=np.int32):
    # minibatch of 1 sequence as column
    return np.array([arr], dtype=dtype).T

def convert_punctuation_to_readable(punct_token):
    if punct_token == data.SPACE:
        return " "
    else:
        return punct_token[0]

def restore(output_file, text, word_vocabulary, reverse_punctuation_vocabulary, model):
    i = 0
    with codecs.open(output_file, 'w', 'utf-8') as f_out:
        while True:

            subsequence = text[i:i+MAX_SUBSEQUENCE_LEN]
                
            if len(subsequence) == 0:
                break

            converted_subsequence = [word_vocabulary.get(w, word_vocabulary[data.UNK]) for w in subsequence]

            if len(converted_subsequence) < MAX_SUBSEQUENCE_LEN:
                converted_subsequence = pad_sequences([converted_subsequence], maxlen=MAX_SUBSEQUENCE_LEN, value=PADDING_VALUE)
                y = model.predict(converted_subsequence)
            else:
                y = model.predict(np.asarray([converted_subsequence]))
            f_out.write(subsequence[0])

            last_eos_idx = 0
            punctuations = []
            for y_t in y[0]:

                p_i = np.argmax(y_t) #.flatten()
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

    if len(sys.argv) > 2:
        input_file = sys.argv[2]
    else:
        sys.exit("Input file path argument missing")
        
    if len(sys.argv) > 3:
        output_file = sys.argv[3]
    else:
        sys.exit("Output file path argument missing")
    
    print("Loading model parameters...")
    # for i in range(num_gpus):
    #     try:
    #         os.environ["CUDA_VISIBLE_DEVICES"]=str(i)
    #         model = load_model(model_file, custom_objects={'perplexity': perplexity})
    #         break
    #     except InternalError:
    #         print("GPU {0} is not available".format(str(i)))
    os.environ["CUDA_VISIBLE_DEVICES"]="4"
    model = load_model(model_file, custom_objects={'perplexity': perplexity})
    
    word_vocabulary = data.read_vocabulary(data.WORD_VOCAB_FILE)
    punctuation_vocabulary = data.iterable_to_dict(data.PUNCTUATION_VOCABULARY)

    reverse_word_vocabulary = {v:k for k,v in word_vocabulary.items()}
    reverse_punctuation_vocabulary = {v:k for k,v in punctuation_vocabulary.items()}

    input_text = codecs.open(input_file,'r','utf-8').read()

    if len(input_text) == 0:
        sys.exit("Input text missing.")

    text = [w for w in input_text.split() if w not in punctuation_vocabulary and w not in data.PUNCTUATION_MAPPING and not w.startswith(data.PAUSE_PREFIX)] + [data.END]

    restore(output_file, text, word_vocabulary, reverse_punctuation_vocabulary, model)

