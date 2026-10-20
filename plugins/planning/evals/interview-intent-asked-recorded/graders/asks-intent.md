---
type: llm
---

Judge only the questions in the reply: lines that ask the user something. A statement is not a
question.

PASS only if one question asks the user whether a second variant is expected: another
address-validation provider besides Loqate, or validation that varies per client, country or
tenant. The question may use the words known, category or speculative, or ask whether to build it
specific now or generalize it, and it carries a recommended answer.

FAIL if no such question is asked, if the reply states an answer to it (for example "no other
provider is coming") without asking, or if the reply asks no question at all.
