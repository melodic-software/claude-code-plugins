# Locked decisions

Operator ratified the full recommendation set on 2026-07-25. Each row is binding on every lane that
follows. A lane that finds a locked decision wrong reports it and stops; it does not re-decide.

## Scope and posture

| # | Decision | Consequence |
|---|---|---|
| D-1 | **Incumbent-first gate is binding.** No remediation ships until it proves no existing skill already covers it | Every lane's first work item is an incumbent search with `path:line` evidence |
| D-2 | **`UNBACKED` claims are report-only and opt-in.** Never auto-applied | Roughly a third of the article's claims. They ship marked, disabled by default, with a severity ceiling |
| D-3 | **No bulk sweep of `plugins/**`.** Findings land as checks in the plugin that already owns each surface | `claude-config`, `claude-memory`, `skill-quality` are the homes. No new router |
| D-4 | **This effort ships two things**: the criteria catalog, and the cross-surface instruction-conflict detector | The conflict detector is the one finding with no incumbent and no existing ticket |
| D-5 | **Verifier-subagent pattern stays, narrowed.** Drop blanket dispatch on mechanical behavior-preserving work; keep it where the verdict is subjective or blast radius is wide | Resolves the three-way tension between Opus 5 guidance, Claude Code best practices, and 23 implementing skills |
| D-6 | **`plugins/playbooks/skills/fable-5/**` is excluded** from this pass | PR #1261 is actively rewriting it |

## Sequencing

| # | Decision | Consequence |
|---|---|---|
| D-7 | **Fold the listing-budget material into issue #1271**, and adopt its `when_to_use` lever | #1271 already measured the defect and found the field this effort's agents missed. No second ticket |
| D-8 | **Sequence behind PR #1096** for anything touching `check-skill.sh` or `docs/PLUGIN-PHILOSOPHY.md` | Check 21 is taken. New criteria pick a free number against the post-merge file |
| D-9 | **Sequence the user-scope work behind dotfiles PRs #318 and #312**, and read #312's Opus 5 re-derivation as an input before measuring | Measuring `dot_claude/CLAUDE.md` while two PRs edit it produces a diff that reverts newer rules |
| D-10 | **Drop the stale dotfiles branch** `docs/claude-md-github-conventions` (+13 lines to `CLAUDE.md`, last commit 2026-07-15, no PR) | One fewer writer on the contested file |
| D-11 | **Reconcile with issue #1225 before building anything sweep-shaped** | Two repo-wide sweeps become two routers |

## Machine health (from `/doctor`, 2026-07-24)

| # | Decision | Consequence |
|---|---|---|
| D-12 | **Fix the `guardrails` PreToolUse root cause.** p50 12–19s blocking every Bash call, ~1,464 runs in six days; a sibling guard in the same event class runs at 2ms | Not a matcher narrowing, not a disable. Root cause |
| D-13 | **Remove the zero-usage plugins** except `plugin-quality`, `context-guard` (both shipped the same day) and `visualization` (one hit under a different leaf name) | ~16 plugins, ~7.4k est. resident tokens |

## Operator-reserved calls (ratified 2026-07-25, second round)

These are the questions the section agents explicitly declined to answer, plus the scope boundary.

| # | Decision | Consequence |
|---|---|---|
| D-14 | **Execution scope is the collision set plus this effort** — the four sequencing blockers (#1096, #1261, dotfiles #318/#312), the two tickets folded into (#1271, #1225), the two machine-health fixes (D-12, D-13), and this effort's two deliverables. Roughly ten lanes | Not the 24-PR / 255-issue backlog. The 12 stale and draft PRs are **not** in scope; they need their own triage pass |
| D-15 | **Arbitration stays the repo's default posture.** Deletion is adopted only where a constraint has no current safety rationale | Overrides the article's blanket delete-constraints posture. A lane proposing a deletion must state the constraint's rationale and why it no longer holds |
| D-16 | **The fresh-docs mandate narrows in scope, not in substance** — it binds changes touching a plugin manifest, marketplace schema, hook contract, or documented harness behavior | Prose and mechanical edits are out. The mandate stays non-negotiable within its scope |
| D-17 | **Auto-memory: move `autoMemoryEnabled` from `claudeSettings.force` to `claudeSettings.seed`, seeded `false`** | Two decisions, both taken. The tier move ends the silent-revert trap; `seed` writes only when absent, so this machine keeps its current value and every fresh machine starts off. Overrides the S7 agent's `true` recommendation on tracked-drift grounds — the capability unlock is available per machine by toggle |
| D-18 | **Cut `CLAUDE.md:13-30`** (the doc-URL table) to a pointer at `docs/OFFICIAL-DOCS.md` | Verified strict subset; 29.6% of the file; line 30 already points at the superset. Accepted risk: the mandate's force must come from the rule, not from the URLs being pre-loaded |
| D-19 | **Vendored `skill-authoring` guidance governs authoring mechanics; this effort's carve-out governs what stays constrained** | Different axes. Where they genuinely collide, upstream wins and the divergence is recorded — a vendored file is never hand-edited |

## Standing constraints these decisions inherit

- **`~/.claude/settings.json` is chezmoi-managed** — verified: its source is
  `dot_claude/modify_settings.json`. D-13's plugin disables are therefore a **dotfiles change**, made
  on a feature-branch worktree of `melodic-software/dotfiles`, never an in-place edit. The same holds
  for `~/.claude/CLAUDE.md`.
- **`.work/` never leaves its checkout.** Anything a later lane must read is committed to
  `docs/topics/context-engineering-rightsizing/`.
- **The parallel branch** `docs/context-engineering-claude-5-topic` is still being worked by another
  session. This pass runs independently by operator ruling; the collision is resolved deliberately at
  merge, not by folding.
