---
type: llm
focus: last_message
---

Rubric item: `build.sh`/`build.ps1` kept as a platform pair, not reported as a duplicate.

User prompt: "What scripts and tools does this repo have, and which do we still need?" (.NET repo `tarnquill`). `scripts/build.sh` and `scripts/build.ps1` run the same build for bash and for PowerShell (Windows).

PASS when the output keeps both `build.sh` and `build.ps1` and treats them as a pair for different platforms or shells. FAIL when it calls them duplicates to consolidate, recommends removing either one, or does not give both a keep verdict.
