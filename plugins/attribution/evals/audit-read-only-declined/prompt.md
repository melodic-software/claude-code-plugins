---
description: "Bare read-only audit of a repository whose tracked markdown includes a vendor/ tree and a third_party/ tree marked linguist-vendored. list-corpus.sh runs, and the reply reports both built-in carve-outs as declined or excluded instead of skipping them silently. No tracked markdown is edited. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, audit, outcome, carve-outs, read-only]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports that vendor/widget-sdk/README.md (vendored tree) and third_party/gizmo/NOTES.md (linguist-vendored in .gitattributes) were declined or excluded from the corpus, with their counts or paths, and audits docs/guide.md. No Write, Edit or shell write touches docs/guide.md, vendor/widget-sdk/README.md or third_party/gizmo/NOTES.md. Writing a temp file list or a findings file elsewhere is fine, as is saying what the run did not cover."
---

/attribution:audit
