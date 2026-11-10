---
description: "Unattended with no convention: nothing is written, the file name stays a proposal, and the missing convention is reported. actions/curate.md step 2: with no convention the ladder proposes a name and asks before writing; unattended, report the proposal and write nothing. actions/locate.md step 4: with no node, use the defaults GLOSSARY.md and GLOSSARY-MAP.md; its output names the proposal and its setting layer. SKILL.md Boundaries: create lazily. glossary-contract.md ladder rungs 4-5: propose GLOSSARY.md, ask before writing, and with interaction unavailable defer creation and report the missing convention; nothing is written. Hard because the term is fully resolved and the bounded context is named, so the only missing piece is the user's confirmation. Bash is not allowed, so the settings script cannot run and the no-node fallback supplies GLOSSARY.md; the setting layer is not graded, since the eval sandbox may deny the plugin-data Write. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, unattended, lazy-creation, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, AskUserQuestion]
expected_outcome: "The reply names GLOSSARY.md as a proposal rather than a file it created, reports that the repository has no glossary convention, and says nothing was written or that creation is deferred. No .md file is written or edited, and no question is asked through AskUserQuestion."
---

/domain-driven-design:ubiquitous-language Running unattended; no one can answer questions. We resolved that a Shipment is one physical consignment handed to a carrier, never a single order line. The repo has one bounded context, Fulfillment, under src/fulfillment.
