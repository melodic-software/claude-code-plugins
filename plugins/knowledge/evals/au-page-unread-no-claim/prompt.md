---
description: "New from base; no evals.json case covers it. Written from MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:74-76 (a page is pinned by URL and as-of date and read through /discovery:read-docs when installed; a page that arrives truncated supports no absence claim). Covers lost sentence 14. The page's host is under the reserved .example top-level domain, so it never resolves, with or without network, and the page stays unread. Shared by base and head: the reply says the page was not read, claims nothing about its content, and writes no record. fetches-public-only is a head-side expectation (head reads the page with fetch-docs.sh --public-only and treats an unread page as supporting no claim, head SKILL.md:127-132); a base failure is the old contract. Base's /discovery:read-docs route is not graded: the discovery plugin is not installed in the run. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local; a page needs no source check."
tags: [knowledge, absorb-upstream, outcome, scaffold, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply says the page could not be read and makes no claim about its content. No Write call and no shell write targets docs/upstream. On head a Bash call runs fetch-docs.sh with --public-only."
---

/knowledge:absorb-upstream https://agent-notes.example/posts/retry-loops
