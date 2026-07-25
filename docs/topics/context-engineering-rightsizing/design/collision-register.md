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

## User-scope collisions — `melodic-software/dotfiles`

The user-scope half of this effort edits `dot_claude/CLAUDE.md`. Three items already touch it:

| Item | State | Overlap | Recommendation |
|---|---|---|---|
| **dotfiles PR #318** `docs/claude-md-multi-agent-restate` | updated minutes ago | `dot_claude/CLAUDE.md` | **Sequence behind.** Landing imminently; a trim measured before it merges would revert a rule added after the measurement |
| **dotfiles PR #312** `chore/opus-5-config` | ~2 h old | `dot_claude/CLAUDE.md`, `.chezmoidata/claude.json`, `dot_claude/statusline/**` | **Sequence behind.** Its Opus 5 re-derivation against build 2.1.219 is an *input* to this pass, not competition |
| dotfiles branch `docs/claude-md-github-conventions` | last commit 2026-07-15, no PR | +13 lines to `CLAUDE.md` | **Needs a keep-or-drop call** before this pass edits the file. Nine days stale |
| dotfiles PR #315 `chore/automode-security` | open | `.chezmoidata/claude.json` only | Low — permission plane, no instruction text |

### Correction — the table above under-counts, and the register is not exhaustive

The rows above are left exactly as scanned; they are the record of what was known, not a claim that
survived. **There were four writers on `dot_claude/CLAUDE.md`, not three.** dotfiles PR #319
*"docs(claude): track two on-demand Claude Code reference docs"* was open and editing that file
(+4 lines) while this pass ran, and does not appear in the table. It merged at
2026-07-25T01:24:12Z before it collided with anything, so the omission cost nothing — this time.
Verified from the remote, by changed files rather than by title, after the user-scope lane hit it.

**The generalizable point matters more than the missing row: this register is a point-in-time
snapshot that was demonstrably incomplete while being presented as complete, and lanes were
dispatched trusting it.** Re-derive from `gh pr list` at the moment of acting. Treat every verdict
here as a pointer to what to re-check, never as the answer.

## Further claims on this subject matter

| Issue | Claims | Disposition |
|---|---|---|
| **#1225** | Sub-agent conventions codified from official docs, then an all-plugin audit | Structurally a second repo-wide sweep. Reconcile before this effort builds another router |
| **#1245** | `code-tidying:self-document` — moves comment criteria *out of* the user-global CLAUDE.md into a `melodic-software/standards` doc | Removes content the CLAUDE.md-trim half also targets |
| **#253** | `docs-hygiene` proactive repo-scan: copied blocks, capability enumerations, internal-name coupling | Owns proactive docs-hygiene detection |
| **#1258** | Defect: `sweep-all-disciplines` fork subagents silently do not inherit the conversation | Dependency, not a scope claim — a defective precedent's shape gets inherited by anything copying it |
| **#496**, **#551** | Orchestrator context economy; `/loop` does not reset context | Context engineering at *runtime*, not the *instruction surface*. Same vocabulary, different plane — state the boundary rather than conflating them |
| **#289** | Wave-2 standards grounding rollout | Adds instruction surface to more plugins — opposing pressure to the trim. Flag, do not block |

No issue claims this effort as a whole. A tracking ticket would have to be filed.

## The parallel branch is still moving

`docs/context-engineering-claude-5-topic` (local only, no upstream, no PR) reached **14 commits /
3,082 lines** with a commit today at 18:49 — it is being worked *now*, on the same article, by
another session. One of its commits reads *"re-sequence Phase 3 so implementation stays off the docs
branch"*, meaning it expects a sibling implementation branch.

**The operator ruled this pass runs independently of that branch, and that ruling stands.** It is
recorded here as a merge-time collision to resolve deliberately, not as a reason to fold. Both
branches are local-only, so there is no remote coordination cost to whatever reconciliation is
chosen.

## Method note

Two independent scans produced this register. The first was run first-hand from `gh` against
`claude-code-plugins` after the dispatched agent went idle twice without delivering. The agent's
report then landed late at
`.work/context-engineering-rightsizing/collision-report.md` (gitignored, checkout-local) with wider
coverage — local worktrees across every checkout, secondary repos, and no-PR remote branches. The
dotfiles and further-claims sections above come from it. The two scans agree on every item both
covered.
