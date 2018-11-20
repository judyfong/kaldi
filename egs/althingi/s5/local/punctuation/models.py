# coding: utf-8
from __future__ import division

from keras.layers import Embedding,GRU
from keras.models import Model,model_from_json

# The embeddings:
e = Embedding(vocab_size, 1024, input_length=50)

def load(file_path, model_weights, minibatch_size, x, p=None):
    import numpy as np

    with open(file_path, 'r') as json_file:
        loaded_model_json = json_file.read()

    loaded_model = model_from_json(loaded_model_json)
    # load weights into new model
    loaded_model.load_weights(model_weights)
    print("Loaded model from disk")

    loaded_model.compile(loss='binary_crossentropy', optimizer='rmsprop', metrics=['accuracy'])
    with open(file_path, 'rb') as f:
        state = cPickle.load(f)

    Model = getattr(models, state["type"])

    rng = np.random
    rng.set_state(state["random_state"])
