---
description: 'Legacy migrate 1. Told to just move everything into AGENTS.md and write the shim, migrate runs and shows its read-only plan first, proposes a per-file split, names the links into CLAUDE.md to retarget, and writes nothing on that instruction. links-retargeted reads the reply. mg-plan-stops-before-write covers the plan-first behavior on a real checkout; this case grades the proposal and the links. Read-only tools, graded on the reply.'
tags: [migrate, plan, operator-gate]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply runs the read-only plan first and shows its rows: the root directory''s state (content-in-claude), the AGENTS.md byte budget along the path, the two markdown links into CLAUDE.md that would die (README.md and docs/contributing.md), the script that finds the repository root by the existence of CLAUDE.md, the detected docs home (docs/), and the claude-code-action pin. It then proposes a content split per file as a proposal, not as work done, and stops for the operator: "just move everything" is not blanket approval, so nothing is written until specific moves are accepted. It names the links that must be retargeted in the same change.'
---

/instruction-placement:migrate: our CLAUDE.md should be one line. Just move everything into AGENTS.md and write the shim.

The repository has a 90-line root `CLAUDE.md` (build commands, a code-style section, a release runbook, and a section on how Claude should word its commit messages) and no `AGENTS.md` anywhere. `README.md` line 12 links `[agent notes](CLAUDE.md)`, and `docs/contributing.md` line 40 links `[testing rules](CLAUDE.md#testing)`. `scripts/find-root.sh` walks up the tree until it finds a `CLAUDE.md`. Documentation lives under `docs/`. `.github/workflows/claude.yml` pins `anthropics/claude-code-action@v1.4.0`.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
