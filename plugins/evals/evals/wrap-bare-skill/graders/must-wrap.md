---
type: llm
arm: both
---

PASS if the answer says the command cannot take the bare folder, because the runner loads a plugin, and says to wrap the skill in a minimal plugin (a `.claude-plugin/plugin.json` manifest, or scaffolded with `claude plugin init review-notes`) and point the command at that. Saying to wrap the skill in a plugin before pointing the command at it meets the first part.

FAIL if the answer says the command works on the folder as is, invents a flag such as `--skill`, says the command wraps or detects the skill automatically, says to use the skill-creator `evals.json` instead (it has no no-skill arm), or later contradicts or retracts this.
