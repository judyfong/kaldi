About the Althingi corpus

    The corpus consists of 6600 recordings of parliament speeches, dating from 2005 to 2016.
    Each recording contains one speech, and comes with the two sets of text files, a lightly
    edited transcript and the one the parliament used for publication.

    The text was normalized and the corpus was aligned and segmented into up to 15 second long
    segments.
    The aligned data set contains of 6493 recordings with 196 speakers, of which 105 are
    male and 91 female. The recordings consist of 199,614 segments, with average duration of 9.8s.
    The total duration of the data set is 542 hours and 25 minutes of data and it contains
    4,583,751 word tokens. 


Language modeling training data

    The language model training material consists of speech transcripts, from the years 2003 to
    2011, scraped from the Althingi website, approx. 30 million word tokens, as well as the
    parliament training data, up to and including 2015.


Tools needed

    OpenGrm Thrax: For number and abbreviation expansion. As well as for the postprocessing of the ASR output.
    KenLM: For language modelling, fast and allows pruning.
    FFmpeg: Used for silence detection when using the ASR to recognize long speeches.
    Punctuator2:  For punctuation restoration
        Requires: Theano

The subdirectory of this directory, s5, contains scripts for the following three steps:
    1) Data normalization, alignment and segmentation.
    2) Training of an ASR
    3) Postprocessing of the ASR output, including punctuation restoration, capitalization
       and denormalization of numbers and common abbreviations

Repo owner: Inga Rún Helgadóttir, ingarunh@gmail.com
