---
type: llm
arm: both
---
Expectations: "The response routes the request to the animation-authoring concern or to
/user-interface:write-animation" and "The response says which route it took".

PASS only if the reply routes the entrance animation to the animation-authoring concern or to
`/user-interface:write-animation` (invoking it, or handing the user that skill) and says which
route it took. A run that invoked `/user-interface:write-animation` directly took that route, and
naming that skill is enough. FAIL if it writes the animation with no route named, or routes it
elsewhere.
