---
type: llm
arm: both
---
PASS only if the rewritten section (1) limits `--no-verify` to the lockfile commit of step 4 rather than to commits in general, and (2) states beside that rule the reason it applies there: the pre-commit hook times out (or cannot handle) the large generated lockfile. Saying other commits run the hooks is welcome but not required. FAIL if `--no-verify` still reads as a rule for every commit, if the scope is right but no reason is given, if the reason is generic ("it is faster", "to avoid issues"), or if the --no-verify rule is dropped.
