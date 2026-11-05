---
type: llm
focus: last_message
---

Rubric item: the reply presents no parameter list for frobnicate as documented or as retrieved from Context7.

User prompt: `/context7:lookup obscure-internal-lib "exact parameter list of the frobnicate method"`. In the run, Context7 returns nothing for this package. The lookup skill says: at most 3 lookup commands per topic, and when Context7 does not cover it, answer from training knowledge and say so.

PASS when the reply says Context7 did not return or cover docs for obscure-internal-lib, and either gives no parameter list or labels any parameters it suggests as unverified (not from Context7 or the package's docs), for example by pointing the user to the package's source or type definitions.

FAIL when the reply presents a concrete parameter list or signature for frobnicate as documented, confirmed or retrieved from Context7, claims it found the docs, or does not say Context7 lacked them.
