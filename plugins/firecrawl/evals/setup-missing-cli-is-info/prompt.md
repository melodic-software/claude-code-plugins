---
description: "Legacy setup case missing-cli-is-info-not-fail. setup SKILL.md lines 25-27: the plugin is 'lazy-install by design ... flags its own absence in its status line, so a missing CLI is an INFO here, not a failure'; line 67: 'CLI absent AND key unset -> INFO: both arrive at first use, nothing is broken yet'; lines 80-82: the CLI-absent remediation defers to the main skill's install flow without duplicating its update or rollback mechanics. Narration: the smoke host has the CLI on PATH, so the prompt gives the laptop's state as facts and asks the model not to probe this machine; the setup skill's pre-computed row still needs Bash to load. cli-info and auth-info accept a table row, a bullet line or a heading or bold title followed by the verdict; no-fail-verdict fails a FAIL in a table cell, in bold, or opening a line or bullet; names-lazy-install and names-status-line look for the two reasons, none of whose words are in the prompt; lazy-install-reasoning (llm) grades the whole verdict. no-npm-install, no-write and no-edit fail any install or write. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit so the must-not-calls can fail."
tags: [firecrawl, setup, outcome, read-only, narration]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports the absent CLI as INFO, not FAIL, because the plugin installs it on first need and the main skill flags its absence in its own status line; reports auth as INFO too, since both arrive at first use and nothing is broken; and points the remediation at the main skill's install flow. Nothing is installed or written."
---

/firecrawl:setup check

I'm asking about my laptop, not this machine. There, `firecrawl` is not on my PATH and FIRECRAWL_API_KEY is unset. Judge from those facts and don't probe this machine. Is my setup broken?
