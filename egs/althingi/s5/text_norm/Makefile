expand.far: expand.grm common.far numbers.far ordinals.far lex/stuff_to_remove.txt lex/abbr_lexicon.txt
	thraxcompiler --input_grammar=$< --output_far=$@

common.far: common.grm 
	thraxcompiler --input_grammar=$< --output_far=$@

numbers.far: numbers.grm common.far lex/units_lexicon.txt
	thraxcompiler --input_grammar=$< --output_far=$@

ordinals.far: ordinals.grm common.far numbers.far lex/ordinals_units_lexicon.txt lex/ordinals_teens_lexicon.txt lex/ordinals_decades_lexicon.txt
	thraxcompiler --input_grammar=$< --output_far=$@

clean:
	rm -f common.far numbers.far ordinals.far
