---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync` under `install_new: ask` no longer tells the model to offer every new catalog plugin in one batched multi-select, which the `AskUserQuestion` tool rejects for a gap of 1 and cannot hold for a gap over 4. The offer now goes in chunks of at most 4 options per question and 4 questions per call, with a further call past 16. Each chunk's question text is distinct, a chunk of 1 (a gap of 1, or the one left over from a gap of 5, 9, 13 and so on) is a single-select Install/Skip question, and an unanswered chunk counts as declined. The skill body, the install-enable context, the README and the `install_new` manifest description state the same rule, and three new evals cover a gap of 1, a gap over 4, and a leftover chunk of 1 in a further call past 16.
