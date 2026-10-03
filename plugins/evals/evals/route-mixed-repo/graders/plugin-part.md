---
type: llm
arm: both
---

PASS if, for the plugin part (the `.claude-plugin/plugin.json` with three skills), the answer routes it to `claude plugin eval` (Claude Code's built-in `plugin eval` command, measured against a no-plugin baseline). Naming `/evals:design`, `/evals:plugin-eval`, or `claude plugin eval init` as the way to scaffold or run it also meets this, as long as the command underneath is `claude plugin eval`.

FAIL if the answer sends `claude plugin eval` (or `/evals:*`) to the summarizer service instead of the plugin; proposes one harness (pytest, promptfoo, a single runner) for the whole repository, skills included; routes the plugin's skills to `/claude-api build-eval` or `/claude-api hillclimb`; gives the plugin no specific route (for example only "write cases for each skill"); or later contradicts or retracts this.
