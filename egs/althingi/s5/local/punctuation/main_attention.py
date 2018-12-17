# coding: utf-8

# NOTE! The code below is not-ready! It is based on https://github.com/ottokart/punctuator2

import sys,os
#import pdb

os.environ['LD_LIBRARY_PATH'] = '/usr/local/cuda-9.0/lib64/'
os.environ["CUDA_VISIBLE_DEVICES"]="4" # NOTE! But what if I want to use any available one?
    
import numpy as np
from tensorflow.python.framework.errors_impl import InternalError
import keras
from keras.layers import Input, Masking, Embedding, GRU, Dense, Activation, Permute, RepeatVector, Bidirectional, Add, Multiply, TimeDistributed, Lambda, Reshape, Dropout
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
DROP_RATE = 0.15
TIME_STEPS = data.MAX_SEQUENCE_LEN
LABEL_DIM = len(data.PUNCTUATION_VOCABULARY)
PADDING_VALUE = len(data.read_vocabulary(data.WORD_VOCAB_FILE)) +10
EPOCHS = 10
num_gpus=6
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

def attention(inputs):
    '''From https://github.com/philipperemy/keras-attention-mechanism/blob/master/attention_lstm.py'''
    # inputs.shape = (batch_size, time_steps, input_dim)
    input_dim = int(inputs.shape[2]) # number of features
    a = Permute((2, 1))(inputs)
    a = Reshape((input_dim, TIME_STEPS))(a) # this line is not useful. It's just to know which dimension is what.
    a = Dense(TIME_STEPS, activation='softmax')(a)
    a = Lambda(lambda x: K.mean(x, axis=1), name='dim_reduction')(a)
    a = RepeatVector(input_dim)(a)
    a_probs = Permute((2, 1), name='attention_vec')(a)
    output_attention_mul = Multiply()([inputs, a_probs])
    return output_attention_mul

def attention2(inputs,context,projected_context):
    '''From https://github.com/philipperemy/keras-attention-mechanism/blob/master/attention_lstm.py'''
    # inputs.shape = (batch_size, time_steps, input_dim)
    #attention = Dense(num_hidden * 2, use_bias=False)(inputs)
    attention = TimeDistributed(Dense(num_hidden * 2, use_bias=False))(inputs)
    attention = Add()([projected_context, attention])
    attention = Activation('tanh')(attention)
    attention = Permute((2, 1))(attention)
    attention = Dense(TIME_STEPS, activation='softmax')(attention)
    #attention = TimeDistributed(Dense(num_hidden*2))(attention)
    #attention = Activation('softmax')(attention)
    attention = Lambda(lambda x: K.mean(x, axis=1), name='dim_reduction')(attention)
    attention = RepeatVector(num_hidden*2)(attention)
    attention = Permute((2, 1), name='attention_vec')(attention)
    weighted_context = Multiply()([context, attention])
    return weighted_context

def attention3(inputs,context,projected_context):
    '''From https://github.com/philipperemy/keras-attention-mechanism/blob/master/attention_lstm.py'''
    # inputs.shape = (batch_size, time_steps, input_dim)
    #attention = Dense(num_hidden * 2, use_bias=False)(inputs)
    attention = TimeDistributed(Dense(num_hidden * 2, use_bias=False))(inputs)
    attention = Add()([projected_context, attention])
    attention = Activation('tanh')(attention)
    #attention = Permute((2, 1))(attention)
    attention = Dense(num_hidden*2, activation='softmax')(attention)
    #attention = TimeDistributed(Dense(num_hidden*2))(attention)
    #attention = Activation('softmax')(attention)
    attention = Lambda(lambda x: K.mean(x, axis=1), name='dim_reduction')(attention)
    attention = RepeatVector(TIME_STEPS)(attention)
    #attention = Permute((2, 1), name='attention_vec')(attention)
    weighted_context = Multiply()([context, attention])
    return weighted_context

def createModel(num_hidden, learning_rate):
    '''Almost entirely from https://github.com/vackosar/keras-punctuator/blob/master/punctuator.py'''
    sys.stderr.write('Creating model.' + "\n")

    inputs = Input(shape=(data.MAX_SEQUENCE_LEN,))
    masked_inputs = Masking(mask_value=PADDING_VALUE)(inputs) # Masks a sequence by using a mask value to skip timesteps. Needed to predict variable length sequences
    #inputs = Input(shape=(data.MAX_SEQUENCE_LEN,1))
    e = Embedding(1 + data.MAX_WORD_VOCABULARY_SIZE, EMBEDDING_DIM, input_length=data.MAX_SEQUENCE_LEN)(masked_inputs)
    
    #context = GRU(num_hidden, activation='tanh', recurrent_activation='hard_sigmoid', use_bias=True, kernel_initializer='glorot_uniform', return_sequences=True)(e)
    context = Bidirectional(GRU(num_hidden, activation='tanh', recurrent_activation='hard_sigmoid', use_bias=True, kernel_initializer='glorot_uniform', return_sequences=True))(e)
    context = Dropout(DROP_RATE)(context)
    #context = GRU(num_hidden, return_sequences=True)(context)
    
    projected_context = TimeDistributed(Dense(num_hidden * 2))(context)

    #attention_mul = attention(context)
    #output = TimeDistributed(Dense(LABEL_DIM, activation='softmax'))(attention_mul)
    
    grulayer_uni = GRU(num_hidden, activation='tanh', recurrent_activation='hard_sigmoid', use_bias=True, kernel_initializer='glorot_uniform', return_sequences=True)(projected_context)
    
    # Attention model
    # compute importance for each step
    weighted_context = attention2(grulayer_uni,context,projected_context)

    # Late fusion - from punctuator
    fusion_context = TimeDistributed(Dense(num_hidden, use_bias=False))(weighted_context)
    weighted_fusion_context = TimeDistributed(Dense(num_hidden, use_bias=False))(fusion_context)
    grudense = TimeDistributed(Dense(num_hidden))(grulayer_uni)
    fusion_weights = Add()([weighted_fusion_context, grudense])
    fusion_weights = Activation('sigmoid')(fusion_weights)
    h = Add()([Multiply()([fusion_context,fusion_weights]), grulayer_uni])
    y = TimeDistributed(Dense(LABEL_DIM, activation='softmax'))(h)

    model = Model(inputs=inputs, outputs=y)

    adam = optimizers.Adam(lr=learning_rate, clipnorm=1.5)
    model.compile(optimizer=adam, loss='categorical_crossentropy', metrics=['categorical_accuracy',perplexity]) # , 'f1score', 'precision', 'recall'
    # optimizer='rmsprop', loss='sdg'
    print(model.summary())
    return model


def trainModel(model, xTrain, yTrain, xVal, yVal, num_gpus, model_file, logdir, callbacks=None, verbose=False):
    sys.stderr.write("Training" + "\n")

    #From https://github.com/flomlo/ntm_keras/blob/master/testing_utils.py
    tensorboard = TensorBoard(log_dir=logdir, batch_size=MINIBATCH_SIZE, histogram_freq=1, write_grads=True, write_images=True) #, embeddings_freq=1, embeddings_layer_names='embedding', embeddings_metadata=model_path + '/logs' + 'metadata.tsv', embeddings_data=xTrain)
    checkpoint = ModelCheckpoint(logdir + "/model.ckpt.{epoch:04d}.hdf5", monitor='val_loss', verbose=1, save_best_only=True, period=1)
    early_stopping = EarlyStopping(monitor='val_loss', min_delta=0, patience=0, verbose=1)
    cbs = [tensorboard, early_stopping, checkpoint] # TerminateOnNaN,
    if verbose:
        for i in range(0, EPOCHS):
            model.fit(xTrain, yTrain, validation_data=(xVal, yVal), epochs=i+1, batch_size=MINIBATCH_SIZE, callbacks=cbs, initial_epoch=i)
            print("currently at epoch {0}".format(i+1))
            # Some test function
            model.save(model_file + '{epoch:02d}.hdf5')
    else:
        for i in range(num_gpus):
        try:
            os.environ["CUDA_VISIBLE_DEVICES"]=str(i)            
            model.fit(xTrain, yTrain, validation_data=(xVal, yVal), epochs=EPOCHS, batch_size=MINIBATCH_SIZE, callbacks=cbs)
            break
        except InternalError:
            print("GPU {0} is not available".format(str(i)))
            
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
        lr = float(sys.argv[4])
    else:
        sys.exit("'Learning rate' argument missing!")    

    model_file_name = "Model_%s_h%d_lr%s" % (model_name, num_hidden, lr)
    model_file = model_path + "/" + model_file_name
    logdir = model_path + "/logs/" + model_file_name
    print(num_hidden, lr, model_file)

    word_vocabulary = data.read_vocabulary(data.WORD_VOCAB_FILE)
    punctuation_vocabulary = data.iterable_to_dict(data.PUNCTUATION_VOCABULARY)
    #print(punctuation_vocabulary)
    
    continue_with_previous = False
    if os.path.isfile(model_file):

        print("Found an existing model with the name %s" % model_file)
        sys.exit()

    import subprocess, re
    gpu_info = subprocess.check_output(('lspci'))
    num_gpus = len(re.findall('VGA compatible controller: NVIDIA Corporation', str(gpu_info), flags=0))

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
    
    model = createModel(num_hidden, lr)
    trainModel(model, xTrain, yTrain, xVal, yVal, num_gpus, model_file, logdir)
