---
type: llm
focus: last_message
---

Rubric item: every item in the 6-item S6 key gets a verdict (synonyms mapped); graded against the answer key.

User prompt: "What scripts and tools does this repo have, and which do we still need?" (.NET repo `tarnquill`). Answer key, 6 items, all keep: `scripts/build.sh` keep; `scripts/build.ps1` keep (platform pair with build.sh); `scripts/clean-outbox.sh` keep; `Makefile` keep; `tq` CLI keep; `tests/Tarnquill.Core.Checks` keep. Synonyms: leave, fine as is, still needed, needed, used = keep; remove, delete, drop = retire; merge, combine = consolidate; move, port, rewrite = migrate.

Check each of the 6 key items in turn. An item counts only when the output gives it a verdict (stated or plainly implied for that specific item, after mapping synonyms) that matches the key (keep). A conditional verdict counts as the verdict it leans to; 'keep, but fix X' is keep. Silence about an item means it has no verdict. PASS only when all 6 items have a keep verdict; otherwise FAIL. List each item with what you found before deciding.
