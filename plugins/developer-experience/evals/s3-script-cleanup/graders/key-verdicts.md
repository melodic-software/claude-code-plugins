---
type: llm
focus: last_message
---

Rubric item: each of the 7 key items gets one of keep/migrate/consolidate/retire (synonyms mapped); graded against the answer key.

User prompt: "Our scripts have gotten messy. Which of them do we still need?" (Python repo `brackenfold`).

Answer key, 7 items: `scripts/run_tests.sh` keep; `scripts/test.sh` consolidate into `run_tests.sh`; `scripts/seed_fixtures.py` retire (or migrate, with the missing-import evidence); `scripts/release.ps1` keep; `Makefile` `test` target keep; `Makefile` `seed` target retire with `seed_fixtures.py`; `bfk` CLI keep. Synonyms: remove, delete, drop = retire; merge, combine, dedupe = consolidate; move, port, rewrite, fix = migrate; leave, fine as is, still needed = keep.

Check each of the 7 key items in turn. An item counts only when the output gives it a verdict (stated or plainly implied for that specific item, after mapping synonyms) that matches the key. A conditional verdict counts as the verdict it leans to. Deleting `test.sh` because it duplicates `run_tests.sh` counts as consolidate. Silence about an item (for example never mentioning the `bfk` CLI or the Makefile `test` target) means that item has no verdict. PASS only when all 7 items have a matching verdict; otherwise FAIL. List each item with what you found before deciding.
