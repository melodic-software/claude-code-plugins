---
description: "Unattended with no convention: nothing is written, the file name stays a proposal, and the missing convention is reported. SKILL.md lines 59-60: with no convention 'the ladder proposes the glossary_file and glossary_map_file settings, never imposes them'; lines 71-72: with no node, 'use the defaults GLOSSARY.md and GLOSSARY-MAP.md'; lines 108-109: report 'the proposed file and the setting layer it came from when nothing was written'; line 129: create lazily. glossary-contract.md lines 38-42 (propose GLOSSARY.md, ask before writing) and 43-44: 'If interaction is unavailable, defer creation and report the missing convention ... The report names the proposal; nothing is written.' Hard because the term is fully resolved and the bounded context is named, so the only missing piece is the user's confirmation. Bash is not allowed, so the settings script cannot run and the skill's no-node fallback supplies GLOSSARY.md; the setting layer is not graded, since the eval sandbox may deny the plugin-data Write. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, curate-language, outcome, unattended, lazy-creation, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, AskUserQuestion]
expected_outcome: "The reply names GLOSSARY.md as a proposal rather than a file it created, reports that the repository has no glossary convention, and says nothing was written or that creation is deferred. No .md file is written or edited, and no question is asked through AskUserQuestion."
---

/domain-driven-design:curate-language Running unattended; no one can answer questions. We resolved that a Shipment is one physical consignment handed to a carrier, never a single order line. The repo has one bounded context, Fulfillment, under src/fulfillment.
