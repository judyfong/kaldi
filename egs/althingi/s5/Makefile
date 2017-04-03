local/abbreviate.far: local/abbreviate.grm local/common.far local/numbers.far local/ordinals.far text_norm/lex/abbreviate_words.txt text_norm/lex/abbreviate_if_preceded_wNumber.txt text_norm/lex/abbreviate_if_followed_byNumber.txt text_norm/lex/kjordaemi_abbr.txt text_norm/lex/abbr_periods.txt
	thraxcompiler --input_grammar=$< --output_far=$@

local/common.far: local/common.grm 
	thraxcompiler --input_grammar=$< --output_far=$@

local/numbers.far: local/numbers.grm local/common.far text_norm/lex/units_notNeutral.txt text_norm/lex/neutral_units2to9.txt
	thraxcompiler --input_grammar=$< --output_far=$@

local/ordinals.far: local/ordinals.grm local/common.far local/numbers.far text_norm/lex/ordinals_units_lexicon.txt text_norm/lex/ordinals_teens_lexicon.txt text_norm/lex/ordinals_decades_lexicon.txt text_norm/lex/ordinals_units_3-9.txt
	thraxcompiler --input_grammar=$< --output_far=$@

clean:
	rm -f local/common.far local/numbers.far local/ordinals.far
