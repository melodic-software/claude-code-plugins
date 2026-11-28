# AskUserQuestion per-call limits, from
# https://code.claude.com/docs/en/agent-sdk/user-input#limitations
# As of 2026-11-27; recheck when that section changes either number.
def ask_options_per_question: 4;
def ask_questions_per_call: 4;

def chunks($n): [range(0; length; $n) as $i | .[$i:$i + $n]];

def question_calls: chunks(ask_questions_per_call);

def install_offer: chunks(ask_options_per_question) | question_calls;
