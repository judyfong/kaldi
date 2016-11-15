// fstbin/fstfilterempty.cc

// Copyright 2009-2011  Microsoft Corporation
//           2015       Robert Kjaran

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fst/fstlib.h"
#include "fstext/table-matcher.h"
#include "fstext/fstext-utils.h"
#include "fstext/kaldi-fst-io.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    using kaldi::int32;

    const char *usage =
        "Filter FSTs from tables/archives of FSTs. Defaults to remove empty FSTs.\n"
        "\n"
        "Usage: fsttablefilter <fst-rspecifier> <fst-wspecifier>\n";

    ParseOptions po(usage);

    bool empty = true;
    po.Register("empty", &empty, "If true remove FSTs with zero states.");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string fst_rspecifier = po.GetArg(1),
        fst_wspecifier = po.GetArg(2);

    SequentialTableReader<VectorFstHolder> fst_reader(fst_rspecifier);
    TableWriter<VectorFstHolder> fst_writer(fst_wspecifier);
    int32 n_done = 0,
         n_empty = 0;

    for (; !fst_reader.Done(); fst_reader.Next(), n_done++) {
      if (n_done % 1000 == 0) {
        KALDI_LOG << n_empty << " FSTs removed out of " << n_done << " processed.";
      }

      VectorFst<StdArc> fst_in = fst_reader.Value();
      if (empty && fst_in.NumStates() == 0) {
        KALDI_VLOG(2) << "FST with key " << fst_reader.Key() << " is empty";
        n_empty++;
      } else {
        fst_writer.Write(fst_reader.Key(), fst_in);
      }
    }

    if (empty)
      KALDI_LOG << "Removed " << n_empty << " empty FSTs out of a total of " << n_done;
    else
      KALDI_LOG << "No filter applied. Total #FSTs = " << n_done;
    return (n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

