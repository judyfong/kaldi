# coding: utf-8

# NOTE! The code below is not-ready! It is based on https://github.com/ottokart/punctuator2

import sys,os
#import pdb

os.environ['LD_LIBRARY_PATH'] = '/usr/local/cuda-9.0/lib64/'
os.environ["CUDA_VISIBLE_DEVICES"]="0" # NOTE! But what if I want to use any available one?

#print('LD_LIBRARY_PATH: ', os.environ['LD_LIBRARY_PATH'])
import numpy as np
import math
import keras
from keras.layers import Input, Masking, Embedding, GRU, Dense, Activation, Permute, RepeatVector, Bidirectional, Add, Multiply, TimeDistributed, merge, Lambda, Reshape, Dropout
from keras.models import Model
from keras.utils.np_utils import to_categorical
from keras.preprocessing.sequence import pad_sequences
from keras.callbacks import TensorBoard, EarlyStopping, ModelCheckpoint, TerminateOnNaN
from keras import backend as K
from keras import optimizers
sys.path.insert(0, 'local/punctuation')
import data

EMBEDDING_DIM = 256 # OK? For English vocabulary it is often lower. For my rnnlm it is 1024
MINIBATCH_SIZE = 128
DROP_RATE = 0.25
TIME_STEPS = data.MAX_SEQUENCE_LEN
LABEL_DIM = len(data.PUNCTUATION_VOCABULARY)
PADDING_VALUE = len(data.read_vocabulary(data.WORD_VOCAB_FILE)) +10
EPOCHS = 10
#pdb.set_trace

def get_data(file_name,shuffle):
    '''Get training and evaluation data'''
    dataset = data.load(file_name)
    if shuffle:
        np.random.shuffle(dataset)
    x=[seq[0] for seq in dataset]
    y=[seq[1] for seq in dataset]
    #tokenizedLabels = to_categorical(np.asarray(y),num_classes=LABEL_DIM)
    #return np.asarray(x).reshape((len(x),data.MAX_SEQUENCE_LEN,1)), to_categorical(np.asarray(y),num_classes=LABEL_DIM) #np.asarray(y)
    return np.asarray(x), to_categorical(np.asarray(y),num_classes=LABEL_DIM) #np.asarray(y)

def perplexity(y_true, y_pred):
    """
    The perplexity metric. From: https://github.com/keras-team/keras/issues/8267
    """
    cross_entropy = K.categorical_crossentropy(y_true, y_pred)
    perplexity = K.exp(cross_entropy)
    return perplexity

def createModel(num_hidden):
    '''Almost entirely from https://github.com/vackosar/keras-punctuator/blob/master/punctuator.py'''
    sys.stderr.write('Creating model.' + "\n")

    inputs = Input(shape=(data.MAX_SEQUENCE_LEN,))
    masked_inputs = Masking(mask_value=PADDING_VALUE)(inputs) # Masks a sequence by using a mask value to skip timesteps. Needed to predict variable length sequences
    #inputs = Input(shape=(data.MAX_SEQUENCE_LEN,1))
    e = Embedding(1 + data.MAX_WORD_VOCABULARY_SIZE, EMBEDDING_DIM, input_length=data.MAX_SEQUENCE_LEN)(masked_inputs)
    
    #context = GRU(num_hidden, activation='tanh', recurrent_activation='hard_sigmoid', use_bias=True, kernel_initializer='glorot_uniform', return_sequences=True)(e)
    context = Bidirectional(GRU(num_hidden, activation='tanh', recurrent_activation='hard_sigmoid', use_bias=True, kernel_initializer='glorot_uniform', return_sequences=True))(e)
    context = Dropout(DROP_RATE)(context)
    context = GRU(num_hidden, return_sequences=True)(context)
    context = Dropout(DROP_RATE)(context)
    y = TimeDistributed(Dense(LABEL_DIM, activation='softmax'))(context)

    model = Model(inputs=inputs, outputs=y)

    rmsprop = optimizers.RMSprop(lr=0.02,clipnorm=2.)
    model.compile(optimizer=rmsprop, loss='categorical_crossentropy', metrics=['categorical_accuracy',perplexity]) # , 'f1score', 'precision', 'recall'
    norm = math.sqrt(sum(numpy.sum(K.get_value(w)) for w in model.optimizer.weights))
    print("The gradient norm: ", norm)
    print(model.summary())
    return model


def trainModel(model, xTrain, yTrain, xVal, yVal, model_file, callbacks=None, verbose=False):
    sys.stderr.write("Training" + "\n")

    #From https://github.com/flomlo/ntm_keras/blob/master/testing_utils.py
    tensorboard = TensorBoard(log_dir=model_path + '/logs', batch_size=MINIBATCH_SIZE, histogram_freq=1, write_grads=True, write_images=True) #, embeddings_freq=1, embeddings_layer_names='embedding', embeddings_metadata=model_path + '/logs' + 'metadata.tsv', embeddings_data=xTrain)
    checkpoint = ModelCheckpoint(model_path + "/logs/model.ckpt.{epoch:04d}.hdf5", monitor='val_loss', verbose=1, save_best_only=True, period=1)
    early_stopping = EarlyStopping(monitor='val_loss', min_delta=0, patience=0, verbose=1)
    cbs = [tensorboard, early_stopping, checkpoint] # TerminateOnNaN,
    if verbose:
        for i in range(0, EPOCHS):
            model.fit(xTrain, yTrain, validation_data=(xVal, yVal), epochs=i+1, batch_size=MINIBATCH_SIZE, callbacks=cbs, initial_epoch=i)
            print("currently at epoch {0}".format(i+1))
            # Some test function
            model.save(model_file + '{epoch:02d}.hdf5')
    else:
        model.fit(xTrain, yTrain, validation_data=(xVal, yVal), epochs=EPOCHS, batch_size=MINIBATCH_SIZE, callbacks=cbs)
        model.save(model_file + '.hdf5')
    return model

    

if __name__ == "__main__":

    if len(sys.argv) > 1:
        model_path = os.path.abspath(sys.argv[1])
    else:
        sys.exit("'Model path' argument missing!")
        
    if len(sys.argv) > 2:
        model_name = sys.argv[2]
    else:
        sys.exit("'Model name' argument missing!")

    if len(sys.argv) > 3:
        num_hidden = int(sys.argv[3])
    else:
        sys.exit("'Hidden layer size' argument missing!")

    if len(sys.argv) > 4:
        initial_learning_rate = float(sys.argv[4])
    else:
        sys.exit("'Learning rate' argument missing!")    

    model_file_name = "Model_%s_h%d_lr%s" % (model_name, num_hidden, initial_learning_rate)
    model_file = model_path + "/" + model_file_name
    
    print(num_hidden, initial_learning_rate, model_file)

    word_vocabulary = data.read_vocabulary(data.WORD_VOCAB_FILE)
    punctuation_vocabulary = data.iterable_to_dict(data.PUNCTUATION_VOCABULARY)
    #print(punctuation_vocabulary)
    
    continue_with_previous = False
    if os.path.isfile(model_file):

        print("Found an existing model with the name %s" % model_file)
        sys.exit()

    #print("train file: ",data.TRAIN_FILE)
    xTrain, yTrain = get_data(data.TRAIN_FILE,True)
    xVal, yVal = get_data(data.DEV_FILE,False)

    #print('Shape of data tensor:', xTrain.shape)
    #print('Shape of label tensor:', yTrain.shape)
    #print('xTrain.shape[0]: ', xTrain.shape[0])
    # with open('xTrain.tmp','w',encoding='utf-8') as fout:
    #     print(xTrain, file=fout)
    # with open('yTrain.tmp','w',encoding='utf-8') as fout2:
    #     print(yTrain, file=fout2)
    # print('xTrain: ', xTrain[:5])
    # print('yTrain: ', yTrain[:5])
    # print('xVal: ', xVal[:5])
    # print('yVal: ', yVal[:5])
    
    model = createModel(num_hidden)
    trainModel(model, xTrain, yTrain, xVal, yVal, model_file)
