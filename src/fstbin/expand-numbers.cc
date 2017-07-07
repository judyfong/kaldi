// fstbin/expand-numbers.cc
//
// Copyright 2009-2011  Microsoft Corporation
//           2015       Reykjavik University (Robert Kjaran)
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
#include "lm/kaldi-lm.h"

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
      fst::StringCompiler<fst::StdArc>::UTF8);

  bool success = str_compiler(transcript, transcript_fst);
  if (!success) {
    KALDI_ERR << "Could not compile string \"" << transcript << "\" to an FST";
  }
}

int main(int argc, char *argv[])
{
  try {
    using kaldi::int32;
    typedef fst::VectorFst<fst::StdArc> Fst;

    const char *usage =
        "Usage: expand-numbers [options] <input-transcripts-rspecifier> "
        "<expand-to-words-fst> <language-model> <output-transcripts-wspecifier>"
        "For example:"
        "utils/slurm.pl JOB=1:$nj ${datadir}/log/expand-numbers.JOB.log expand-numbers --word-symbol-table=text_norm/words30.txt ark,t:${datadir}/split${nj}/text.JOB.txt text_norm/expand_to_words30.fst text_norm/numbertexts_3g.fst ark,t:${datadir}/split${nj}/text_expanded.JOB.txt"
        "\n"
        "<language-model> has to be in FST format\n";

    kaldi::ParseOptions po{usage};

    std::string
      word_symbol_table_filename,
      lm_input_type = "fst";

    po.Register("word-symbol-table", &word_symbol_table_filename,
                "If <language-model> is an FST and does not have embedded symbol"
                "tables, one can be provided");
    
    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }
    
    std::string
        input_rspecifier = po.GetArg(1),
        expand_fst_rxfilename = po.GetArg(2),
        language_model_rxfilename = po.GetArg(3),
        output_wspecifier = po.GetArg(4);

    DEFINE_string(fst_field_separator, "\t ",
              "Set of characters used as a separator between printed fields");

    fst::SymbolTable* word_symbol_table = NULL;
    if (!word_symbol_table_filename.empty())
      word_symbol_table = fst::SymbolTable::ReadText(
	  word_symbol_table_filename);
  
    kaldi::GrammarType grammar_type;
    grammar_type = kaldi::GrammarType::kFst;

    kaldi::LangModelFst lm_fst;
    lm_fst.Read(language_model_rxfilename, grammar_type, word_symbol_table, true);
    lm_fst.GetFst()->SetOutputSymbols(word_symbol_table);
    lm_fst.GetFst()->SetInputSymbols(word_symbol_table);

    // The FST used to generate all possible expansions
    Fst* expand_fst = fst::ReadFstKaldi(expand_fst_rxfilename);

    // The input is a table of word sequences
    kaldi::SequentialTableReader<kaldi::TokenVectorHolder> transcript_reader{
      input_rspecifier};

    // The output is also a table of word sequences
    kaldi::TableWriter<kaldi::TokenVectorHolder> transcript_writer{
      output_wspecifier};

    int32 n_done = 0;
    int32 n_empty = 0;
    for (; !transcript_reader.Done(); transcript_reader.Next(), n_done++) {
      std::string key = transcript_reader.Key();
     
      // A linear acceptor FST with utf8 labels
      Fst transcript_fst;
      TokenVectorToUtf8Fst(transcript_reader.Value(), &transcript_fst);
      
      // All possible expansions
      Fst all_expansions_fst;
      fst::Compose(transcript_fst, *expand_fst, &all_expansions_fst);
      
      if (word_symbol_table) {
        all_expansions_fst.SetOutputSymbols(lm_fst.GetFst()->OutputSymbols());
      }
      fst::Project(&all_expansions_fst, fst::ProjectType::PROJECT_OUTPUT);
      
      
      // Use language model to find best expansion
      Fst best_expansion_fst;
      fst::Intersect(all_expansions_fst, *(lm_fst.GetFst()), &best_expansion_fst);
      // fst::WriteFstKaldi(best_expansion_fst, "text_norm/text/best_expansion.fst");
            
      Fst shortest_fst;
      fst::ShortestPath(best_expansion_fst, &shortest_fst);

      if (shortest_fst.NumStates() == 0) {
        n_empty++;
	if ( n_empty < 11){
          KALDI_WARN << "FST empty after shortest path for key " << key;
	}
      }

      std::vector<int32> out_transcript_int;
      fst::GetLinearSymbolSequence<fst::StdArc, int32>(shortest_fst,
                                                       NULL, &out_transcript_int, NULL);
    
      std::vector<std::string> out_transcript;
      for (const int32 &i : out_transcript_int) {
        std::string token = word_symbol_table->Find(i);
        out_transcript.push_back(token);
      }

      transcript_writer.Write(key, out_transcript);

    }
    
    if ( n_empty > 0 ){
      KALDI_WARN << n_empty << " FSTs were empty after shortest path\n";
    }
    
    delete word_symbol_table;
    delete expand_fst;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
  
}
