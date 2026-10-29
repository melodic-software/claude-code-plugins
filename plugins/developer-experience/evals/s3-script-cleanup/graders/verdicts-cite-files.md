---
type: llm
focus: last_message
---

Rubric item: each verdict cites a file (and line where relevant).

User prompt: "Our scripts have gotten messy. Which of them do we still need?" (Python repo `brackenfold`). The agent's answer gives verdicts (keep / delete / merge / fix and so on) on scripts and tooling.

Judge each verdict by its main evidence, not by every supporting remark. For every verdict (keep, delete, merge, fix and so on), find the evidence the verdict mainly rests on. (1) It must cite a file other than the script the verdict is about (for example the caller `Makefile`, the duplicate `run_tests.sh`, the missing `bfk/legacy.py` or `data/legacy_seed.csv`). (2) If that main evidence is specific content inside a file (a Makefile target calling the script, an import, the input path read, the command a wrapper runs), at least one citation for it carries a line number or range (for example `Makefile:6-7`, `seed_fixtures.py:3`); absence claims ('nothing calls it', 'the file does not exist') need no line. Extra supporting remarks without line numbers (for example 'AGENTS.md also mentions it', 'it overwrites the data file') do not make a verdict fail when its main evidence is cited with a line. A verdict whose content-specific evidence never has a line number fails step 2. PASS when every verdict meets both steps; FAIL when any verdict misses either. Go through each verdict before deciding.
