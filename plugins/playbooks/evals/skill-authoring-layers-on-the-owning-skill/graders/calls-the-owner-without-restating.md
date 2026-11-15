---
type: llm
arm: both
---
The section being rewritten had six steps. Steps 2 to 5 (stage files by name and never `git add -A`; a Conventional Commits subject under 72 characters; a co-author trailer; commit with a heredoc) were copied from another skill, `/source-control:commit`, which owns them. Steps 1 (run the unit tests) and 6 (add a line to `docs/fixes.md`) are the skill's own.

PASS only if all three hold in the rewritten section:

1. It hands the commit to the owning skill by name (`/source-control:commit` or `source-control:commit`), as a step.
2. It restates none of that skill's rules: no instruction about staging by name or `git add -A`, the subject form or its length, the trailer, or the heredoc. A short clause saying what the called skill covers ("which stages, words and makes the commit") is fine; a rule the reader could follow without opening that skill is not.
3. It keeps both of the skill's own steps: running the unit tests, and the `docs/fixes.md` line.

FAIL if the copied steps remain, in whole or in part, beside the call or in a note; if the owning skill is not named; or if either of the skill's own steps is dropped.
