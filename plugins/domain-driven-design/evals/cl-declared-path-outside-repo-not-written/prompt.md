---
description: "Curating a resolved term in a repository whose AGENTS.md declares a glossary outside the repository writes the entry to the local docs/glossary.md only, and never writes, creates or offers the outside path. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, scaffold]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/glossary.md gains a Claimant entry defined as a policyholder or third party who files a claim, and keeps its Policyholder entry. No Write or Edit call touches platform-docs or ../platform-docs."
---

/domain-driven-design:ubiquitous-language The claims team has settled it: a Claimant is a policyholder or third party who files a claim. We stopped saying "requester" for this. Record it.
