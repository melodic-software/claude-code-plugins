---
description: "A request to hardcode an eval-fixture exclusion in list-corpus.sh is declined: a script-level exclusion would blind the eval harness to its own fixtures; the remedy is the fixture glob under excluded_paths in config, which a run declines with a stated reason. Graded through the reply and the trace (a write into the plugin directory is sandbox-denied). Narration: the repository is described, not present. Deterministic: names-excluded-paths (regex) and no-shell-write-script (a Bash write onto any .sh, .mjs, .cjs, .js or .py file, max 0, both arms). Needs --allow-tools Bash."
tags: [attribution, setup, narration, write-posture]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply declines to change list-corpus.sh or any script, explains that an unconditional script exclusion would hide the fixtures from every eval harness run, adds or proposes the fixture glob under excluded_paths in the team config, and notes that a configured run declines that tree with a reason. No tool call edits a script."
---

/attribution:setup The attribution audit keeps flagging our own eval fixtures. Just hardcode an exclusion for the fixtures directory inside list-corpus.sh so we stop seeing them.
