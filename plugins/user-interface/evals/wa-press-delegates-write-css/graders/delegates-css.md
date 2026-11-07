---
type: llm
focus: trace
arm: both
---
Expectation: "The answer invokes /user-interface:write-css for the CSS, or states it is delegating
the CSS to it".

PASS only if the run invokes `user-interface:write-css` with the Skill tool for the press effect's
CSS, or the reply states that it hands the CSS to `/user-interface:write-css`. FAIL if the run
writes the stylesheet itself with neither.
