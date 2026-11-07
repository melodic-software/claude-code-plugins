---
description: 'Legacy onboard-adapter 4. Generation for redmine lands in the consuming repository under tools/work-item-tracker/ (the adapter and its conformance binding), never in the plugin directory, and keeps an existing hand-written adapter README instead of overwriting it. A headless run cannot answer the interview, so the workspace holds the finished spec (adapter-spec.json) and the prompt says so. adapter-written and binding-written check the created paths, readme-kept the README''s original text, no-force that --force is never passed. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [onboard-adapter, consumer-local, must-not]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The run writes tools/work-item-tracker/adapters/redmine/ and tools/work-item-tracker/conformance/bindings/redmine.sh in the consuming repository, keeps the existing README.md without --force, and explains that adapters resolve consumer-local-first so no plugin fork or vendored seam is needed.'
---

/work-items:onboard-adapter redmine

The interview is already done: its answers are in adapter-spec.json at the repository root. Generate the adapter.
