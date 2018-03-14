// fstbin/fststringcompile.cc
//
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


std::string StringFromTokenVector(std::vector<std::string> const& tokens) {
  std::stringstream ss;
  for (std::vector<std::string>::const_iterator it = tokens.begin() ; it != tokens.end(); ++it) {
    ss << *it << " ";
  }
  return ss.str();
}

void TokenVectorToUtf8Fst(std::vector<std::string> const& tokens,
                          fst::VectorFst<fst::StdArc> *transcript_fst) {
  std::string transcript = StringFromTokenVector(tokens);
  fst::StringCompiler<fst::StdArc> str_compiler(
      fst::StringTokenType::UTF8);

  bool success = str_compiler(transcript, transcript_fst);
  if (!success) {
    KALDI_ERR << "Could not compile string \"" << transcript << "\" to an FST";
  }
}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    using kaldi::int32;

    const char *usage =
        "Compile UTF8 strings into linear FSTs (using UTF8 as a symbol table)."
        "\n"
        "Usage: fststringscompile <transcripts-rspecifier> <fst-wspecifier>\n";

    ParseOptions po(usage);

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string transcript_rspecifier = po.GetArg(1),
        fst_wspecifier = po.GetArg(2);

    SequentialTableReader<TokenVectorHolder> transcript_reader(transcript_rspecifier);
    TableWriter<VectorFstHolder> fst_writer(fst_wspecifier);
    int32 n_done = 0;

    for (; !transcript_reader.Done(); transcript_reader.Next(), n_done++) {
      fst::VectorFst<fst::StdArc> transcript_fst;
      TokenVectorToUtf8Fst(transcript_reader.Value(), &transcript_fst);
      fst_writer.Write(transcript_reader.Key(), transcript_fst);
      if (n_done % 500 == 0)
        KALDI_LOG << n_done << " strings compiled to FSTs so far.";
    }

    KALDI_LOG << "Compiled " << n_done << " FSTs.";
    return (n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
