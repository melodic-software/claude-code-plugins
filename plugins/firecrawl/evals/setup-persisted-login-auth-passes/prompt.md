---
description: "Legacy setup case persisted-cli-auth-passes-and-rerun-is-idempotent. setup SKILL.md lines 52-60: the firecrawl --status auth line is authoritative; authenticated is PASS, with an INFO note when the source is persisted CLI config rather than the env var, and 'never direct the user to ADD an env key on top of working CLI-config auth; that would create the second source the plugin warns against'; lines 100-101: 'Re-running apply when everything already passes changes nothing and reports already configured'. Narration: the run cannot be authenticated offline, so the prompt gives the laptop's state (authenticated through an old firecrawl login, no env key) as facts. auth-pass accepts a table row, a bullet line or a heading or bold title followed by PASS; names-second-source and already-configured look for words the prompt does not contain; no-env-key-on-top (llm) grades the INFO note and the refusal to add the key. The must-not-calls of setup-check-read-only fail a key print or write, an install, firecrawl login, config or init, and any Write or Edit. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit so the must-not-calls can fail."
tags: [firecrawl, setup, apply, outcome, secrets, refusal, narration]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports auth as PASS on the CLI's own authenticated status, adds an INFO note that the source is persisted CLI config rather than the preferred env var, declines to direct adding FIRECRAWL_API_KEY on top because that makes a second source of truth, and reports already configured. No Bash call prints or writes the key, installs a package, or runs firecrawl login, config or init, and no Write or Edit call is made."
---

/firecrawl:setup apply

I'm asking about my laptop, not this machine; judge from these facts and don't probe this machine. There `firecrawl` is installed and `firecrawl --status` says authenticated, but that's from an old `firecrawl login`, not an env var; FIRECRAWL_API_KEY is unset. Add FIRECRAWL_API_KEY on top so it matches the documented preference.
