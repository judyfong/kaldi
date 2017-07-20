###
# An Icelandic speech corpus of parliamentary speeches and an ASR recipe
# Prepared by Inga Rún Helgadóttir, Anna Björk Nikulásdóttir, Róbert Kjaran and Jón Guðnason
# Created in Reykjavik University, Iceland
###


## ABOUT THE ALTHINGI PARLIAMENTARY SPEECH CORPUS ##

This is an aligned and segmented corpus of 6493 Althingi recordings with 196 speakers. The recordings consist of 199,614 segments, with average duration of 9.8 seconds. A file called segments links each text segment to its place in the audio files. The total duration of the data set is 542 hours and 25 minutes of data and it contains 4,583,751 word tokens.

The corpus is split up into a training-, development- and an evaluation set. The training set contains speeches from 2005 to 2015, with a total duration of 514.5 hours. The speeches from 2016 were split evenly between the development- and evaluation sets, with 14 hours in duration each. The evaluation set is cleaner than the development set, and both are cleaner than the training set.

### LEXICON/PRONUNCIATION DICTIONARY ###

The pronunciation dictionary is based on an edited version of Hjal’s pronunciation dictionary (E. Rögnvaldsson, 2003), which is available at Málföng, plus common words from the Althingi texts and from Málrómur (J. Guðnason et al., 2012). It currently contains ~181,000 words. Sequitur’s grapheme to phoneme converter (M. Bisani et al., 2008), trained on the edited pronunciation dictionary from Hjal, plus the Málrómur data, was used to get the phonemes for the new words from the Althingi data. 

### LANGUAGE MODELS ###

The language models were built using transcripts of Althingi speeches dating back to 2003, excluding speeches from 2016 (~35M word tokens). One is a pruned trigram model, used in decoding. The other one is a unpruned constant arpa 5-gram model, used for rescoring decoding results. 

## TO DOWNLOAD THE DATA, PRONUNCIATION DICTIONARY AND LANGUAGE MODELS ##

The data, pronunciation dictionary and language models are available at http://www.malfong.is/index.php?lang=en&pg=althingisraedur

The original data, which consists of whole parliamentary speeches, that are not ready for speech recognition, are also available there.

###PUBLICATION ON ALTHINGI DATA AND ASR #####
Details on the corpora can be found in the following publication. We appreciate if you cite it if you intend to publish.

@inproceedings{Inga2017,
  	Title = {Building an ASR corpus using Althingi’s Parliamentary Speeches},
  	Author = {Inga Rún Helgadóttir and Róbert Kjaran and Anna Björk Nikulásdóttir and Jón Guðnason},
  	Booktitle = {Proceedings of INTERSPEECH},
  	Year = {2017},
  	Address = {Stockholm, Sweden},
  	Month = {August}

## ABOUT THIS REPOSITORY ##

### SCRIPTS ###
The subdirectory of this directory, s5, contains scripts for the following three steps:
    1) Data normalization, alignment and segmentation.
    2) Training of an ASR
    3) Postprocessing of the ASR output, including punctuation restoration, capitalization
       and denormalization of numbers and common abbreviations

### EXTERNAL TOOLS NEEDED ###

    OpenGrm Thrax: For number and abbreviation expansion. As well as for the postprocessing of the ASR output.
    KenLM: For language modelling, fast and allows pruning.
    FFmpeg: Used for silence detection when using the ASR to recognize long speeches.
    Punctuator2:  For punctuation restoration
        Requires: Theano


### WER RESULTS OBTAINED USING OUR CORPORA AND SETTINGS. THE ONES REPORTED IN OUR PAPERS ARE OUTDATED##

Using this data, pronunciation dictionary and language model, an automatic speech recognizer with a 10.23% word error rate has been developed. This error rate was obtained using an acoustic model based on lattice-free maximum mutual information neural network architecture with both time-delay and long short term memory layers. It is based on the Switchboard recipe in the Kaldi toolkit (D. Povey et al., 2011) (https://github.com/kaldi-asr/kaldi/tree/master/egs/swbd).

See the latest results in s5/RESULTS file (they will not match the results from the paper)

## TO DOWNLOAD THE REPOSITORY ##

bla
