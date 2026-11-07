---
description: 'Legacy proof-level-02 (narration). The stricter layer wins: the repository''s live raises the user''s path, the report names the repository file at origin/main, and a CLI change is run as a user would run it (config.md Resolution, line 77 example). Framed like the existing narration cases. A run cannot set the user option, so the prompt states it. report-line-live grades the level and its repository source; runs-help the real --help command named; repo-live-raises-path (llm) legacy expectations 1 and 2 verbatim. Expectation 3 (runs the real CLI command) is held: the case has no CLI to run and grants no Bash.'
tags: [verification, confirm, narration, no-network, proof-level, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Reports proof_level: live from docs/conventions/verification.yaml at origin/main, notes the user option said path, and names running the CLI with --help as a user would as the check live requires.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The user option proof_level is path. origin/main's docs/conventions/verification.yaml says `proof_level: live`, read at commit 9b1d2e7. The diff changes the wording of a CLI tool's --help output in a file outside every runtime-affecting path. Write the report, including the checks you run, then stop.
