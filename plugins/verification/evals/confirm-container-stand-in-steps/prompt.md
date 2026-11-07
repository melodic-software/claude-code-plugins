---
description: 'Legacy stand-in-01. When the proof ran on a stand-in (a container instead of a fresh machine), the report lists every setup step the stand-in did that the target will not and marks each unverified (SKILL.md Three rules for the live drive, ''Stand-in caveat''). Framed like the existing narration cases. names-stand-in, lists-three-steps grade the reply; stand-in-unverified (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, live-drive, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The report says the proof ran in a container standing in for a fresh machine and lists the PDF library install, the export directory and the cron entry as steps the target will not do, each unverified.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. The change adds a nightly report export to a service that is deployed to a fresh virtual machine. proof_level resolves to live. Build, tests and lint pass. The live drive ran inside a container, where the image build installed the PDF library and created the export directory and a cron entry, and the export ran and produced the expected file. The deployment script for the virtual machine installs none of those three things. Write the report, then stop.
