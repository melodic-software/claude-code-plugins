# Collision register — what else is in flight against this subject matter

Scanned 2026-07-25 against `melodic-software/claude-code-plugins`. Verdicts: **direct** (edits files
this effort would edit), **adjacent** (same subject, different files), **clear**.

## The register

| Item | What it is | Verdict | Overlap |
|---|---|---|---|
| **Issue #1271** (37 min old) | Skill metadata: trigger phrases crammed into `description`; `when_to_use` unused; shared listing budget silently drops them | **direct** | This effort's single highest-confidence finding — measured independently by four blind agents and by `/doctor` — is already filed, measured, and scoped here. It states "Direction (no open decision)" |
| **PR #1261** (open, moving) | `feat(playbooks): adopt the fable field guide audit remediations into fable-5` | **direct** | Rewrites `plugins/playbooks/skills/fable-5/SKILL.md` and six `context/` chapters. Already excluded from this pass by operator ruling — that ruling is now load-bearing, not precautionary |
| **PR #1096** (open, 1 day) | `feat(skill-quality): fresh-eyes delegation doctrine + conformance gate (check 21)` | **direct** | Claims the **check 21 slot** in `plugins/skill-quality/scripts/check-skill.sh`, which section S4 independently proposed for its interface-expressiveness criterion. Also edits `docs/PLUGIN-PHILOSOPHY.md`, which section S2 proposes to edit for the question-rendering convention |
| **Issue #1227** (9 h) | Skill-selection cheat sheet + progressive-disclosure README split | **adjacent** | Same progressive-disclosure subject as S5, applied to repo docs IA rather than skill bodies |
| **Issue #304** | Program: fresh-eyes checkpoint audit — tag skill actions for same-context bias | **adjacent** | Parent program of #1096; the verifier-subagent tension S3 raises is this program's subject |
| **PR #1266** (43 min) | `docs: answer the loop-engineering questions from the corpus and land the sweep's corrections` | **adjacent** | Another corpus-absorption effort landing conventions + `autonomy` reference material. No file overlap found |
| **PR #1252**, **Issue #1251** | context-guard / rate-limit-guard durable statusline wiring | **clear** | Different surface |
| **Issue #406** | implementation: TDD-by-default fires when consumer CLAUDE.md is silent | **adjacent** | An instance of the S3 over-constraint class, already ticketed with its own seam decision |
| **Issue #496** | Orchestrator context economy — subagent return-payload contracts | **adjacent** | Context economy, different layer (inter-agent payloads, not instruction surfaces) |
| 20 other open PRs | Assorted fixes across `toolchain`, `source-control`, `disk-hygiene`, `session-flow`, `discovery` | **clear** | No subject-matter or file overlap |

## What this changes

1. **The headline finding is already owned.** Issue #1271 measured the same defect independently
   (80,026 chars of `description` across 135 model-invocable skills; this effort measured 111,784
   across 195 including non-invocable ones — consistent once scoped) and adds a mechanism no section
   agent found: **`when_to_use` is the dedicated trigger-phrase field and is used in 2 of 187 files.**
   This effort's S2/S5/S11/S13 material belongs as corroborating evidence on #1271, not as a new
   work item.

2. **Section S4's proposed home is taken.** Check 21 in `check-skill.sh` is claimed by PR #1096.
   Any interface-expressiveness check needs a different number and must be written against #1096's
   post-merge `check-skill.sh`, not today's.

3. **Two sections propose editing `docs/PLUGIN-PHILOSOPHY.md`, and so does PR #1096.** Sequence
   behind it or take the conflict at merge.

4. **The fable-5 exclusion held.** PR #1261 is actively rewriting that subtree right now. Had this
   pass included it, two independent edit plans would have collided in-flight.

## Method note

The dispatched reconnaissance agent completed its scan but never delivered its report — it returned
idle twice without content and did not write the file when asked. The register above was rebuilt
directly from `gh` and is first-hand, not relayed.
