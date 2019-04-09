export ASSET_ROOT=/home/staff/inga
export KALDI_ROOT=`pwd`/../../..
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD/tools/mitlm/bin:$PWD/tools/sequitur/bin:$PWD/tools/kenlm/build/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

#PYTHONPATH=$PYTHONPATH:$PWD/tools/sequitur/lib/python2.7/site-packages/:~/.local/lib/python2.7/site-packages/:punctuator/
#export PYTHONPATH
export CONDAPATH=$ASSET_ROOT/miniconda2/bin
# # For libgpuarray, used in theano back end
# export LIBRARY_PATH=$LIBRARY_PATH:~/.local/lib64/:~/.local/lib:~/kaldi/tools/openfst/lib
# export CPATH=$CPATH:~/.local/include:~/kaldi/tools/openfst/include
# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:~/.local/lib64/:~/.local/lib:~/kaldi/tools/openfst/lib:/usr/local/lib

# Activate all althingi specific paths as well as exp, data and mfcc on scratch
. ./conf/path.conf
