---
description: 'Legacy setup espeak-request-is-refused. Slash-invoked (setup SKILL.md line 5, disable-model-invocation: true), no Skill grader. Line 57: bare apply has nothing to configure, say so and name apply install-model; lines 15-17 and 59-60: the user installs espeak-ng (GPL-3.0), and apply reports the install hints check printed. user-installs-espeak is an llm grader because "the user installs it" has many phrasings. Needs --allow-tools Bash Write and --disallow-tools Grep Glob. Host tools: python3. The Bash grant also needs a sandbox backend.'
tags: [speech, setup, apply, refusal, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Runs no espeak-ng or package install; says the user installs espeak-ng; names apply install-model as the only apply subaction.'
---

/speech:setup apply

Also install espeak-ng for me while you're at it.
