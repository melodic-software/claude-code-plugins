---
type: llm
arm: both
---
Expectations: "The answer gives a one-line definition for each term it names" and "The
answer suggests a rewritten request that names the terms instead of the word snappier".

PASS only if each motion term the reply names comes with a one-line definition, and the reply
suggests a rewritten request that names those terms in place of "snappier". FAIL if a term has no
definition, or there is no rewritten request.
