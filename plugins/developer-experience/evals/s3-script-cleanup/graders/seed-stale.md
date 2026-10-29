---
type: llm
focus: last_message
---

Rubric item: `seed_fixtures.py` found stale, citing the absent import or file.

User prompt: "Our scripts have gotten messy. Which of them do we still need?" (Python repo `brackenfold`). In the fixture, `scripts/seed_fixtures.py` imports `bfk.legacy` (no such module) and reads `data/legacy_seed.csv` (no such file).

PASS when the output says `seed_fixtures.py` is stale, broken or cannot run AND gives as the reason the missing `bfk.legacy` module or the missing `data/legacy_seed.csv` file (either is enough). FAIL when it does not call the script stale/broken, or calls it stale without naming either missing import or missing file.
