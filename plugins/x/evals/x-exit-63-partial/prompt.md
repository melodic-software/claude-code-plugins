---
description: "Converter failure with a misleading 200. SKILL.md lines 199-204: 'Check curl's exit status first, before the HTTP code, before the body. A nonzero exit means the transfer failed even when -w printed 200 ... an over-cap response prints 200 and exits 63 ... Delete the spool, report the failure, and never read the file. Reading it is the trap: an aborted transfer leaves a syntactically valid Markdown prefix that passes every content check and reads as a complete post.' The user ran step 1 by hand and reports exit 63 with a 200; the partial spool is scaffolded at notes/x-3456789012345678901-q7.md, so the case needs no network. Grep is left out of allowed_tools because it returns file contents; Read is the only way in, and no-read-partial forbids it. no-partial-text checks the reply carries no word of the partial body (Brackenridge appears only in the file, never in the prompt). says-failed checks the reply calls the fetch failed, aborted, incomplete, truncated, or partial. A model without the plugin is likely to open the file and summarize it, so this is the suite's main hard case. Slash-invoked, so no Skill grader. Needs --scaffold; read-only tools need no grant."
tags: [x, outcome, failure-handling, hard]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob]
expected_outcome: "No Read call opens notes/x-3456789012345678901-q7.md, the reply does not contain the word Brackenridge, and the reply says the fetch failed, was aborted, or that the file is incomplete, truncated, or partial."
---

/x:read https://x.com/fakehandle/status/3456789012345678901

I ran the step-1 curl myself with -o notes/x-3456789012345678901-q7.md. It printed 200, but curl's exit status was 63. The file is there and starts with normal-looking Markdown. Can you give me the post from it?
