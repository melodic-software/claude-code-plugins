# bug-finding-skill — PLAN

## Brief

### TLDR

- New skill `/bug-report:scan` in the existing `bug-report` plugin: proactive, general-purpose bug finding — on demand, targeted ("find a bug in X"), or as a daily routine's single bounded pass.
- Read-only find → verify → report; two-stage precision (recall-biased hunter subagents, then a separate fresh-context default-refute verification gate); never fixes code in-run.
- Targeted scoping (path/feature/diff argument) plus whole-repo lane rotation with a per-run budget (stop at 3 verified findings or lane exhausted); lane cursor derived statelessly from tracker/git history.
- Optional filing behind an explicit argument only: every self-filed finding lands as raw intake (`status:needs-triage` via the consumer's `role_labels` map) — never born-briefed, never on bare invocation.
- Extend the plugin's `setup` skill to write a tracked, config-cascade-governed project file for lane globs + filing posture; ship evals; pass `skill-quality:check`; register nothing new in marketplace.json (plugin exists).

### Goal

The marketplace covers the bug lifecycle everywhere except its start: every existing finding-producer is gated on a diff, an observed failure, a factual claim, a test file, or a comment marker. `/bug-report:scan` fills that gap — a proactive hunter that reads resting code, surfaces defects nobody has observed yet, verifies them adversarially before reporting, and hands them to the existing report/filing/triage machinery. One invocation is one bounded scan, equally usable interactively ("find a bug in this feature"), from `/loop`, from a claude-ops lane prompt, or from a cloud Routine.

### Constraints

- Read-only on bare invocation (verb-table contract for `scan`); mutation (filing) only behind an explicit argument.
- No sibling-plugin imports; composition with `work-items`, `debugging`, `review` is presence-gated with graceful degradation.
- The two-stage precision shape is mandatory: the discovering agent never grades its own findings (fresh-eyes rule); default-refute; "if uncertain, it is NOT a finding."
- Filing conforms to the dogfood-filing contract: raw intake only, labels resolved through the consumer's `.work-item-tracker.json` `role_labels` map; no label creation.
- Durable cross-run state must not live in `.work/` (checkout-local); lane cursor derives from filed-finding/tracker history; `.work/` is a per-checkout cache only.
- Lane globs and filing posture are team config in a tracked project file (config-cascade-governed, written by setup) — not `userConfig`.
- No scheduler in the skill; loop-friendly single-pass semantics with `cadence: daily` metadata.
- Skill fences (skip-when) must name: `review:*` (diff review), `review:security-review` (security-focused auditing), `debugging:debug` (observed failures), `codebase-health:audit` (doc/config/code-quality/arch claim drift — all its dimensions), `code-tidying:tidy` (structure), `work-items:scan-todos` (comment markers), `testing:audit` / `mutation-testing:audit` (coverage gaps).
- Repo gates: `skill-quality:check` (22-check static gate), evals present, CI check scripts, markdownlint, skill-reference-verify.

### Acceptance criteria

- `/bug-report:scan <path|feature|diff>` runs a targeted hunt and emits verified findings in the 5-field bug-report shape, each labeled `reproduced` or `verified-by-reading`; bare `/bug-report:scan` self-selects a lane via the stateless cursor and stays within the per-run budget (default: stop at 3 verified findings or lane exhausted).
- Every reported finding passed a separate fresh-context default-refute verification subagent; unverified candidates never appear in the report.
- V1 hunting lenses shipped: in-code contract-vs-body mismatch (same-unit signature/types/docstring/named invariants only), boundary/edge-case, cross-file consistency drift, state/concurrency hazards, git-hotspot-guided reads.
- Filing happens only with the explicit filing argument, produces raw-intake work items through the tracker seam with `role_labels`-resolved labels, and runs a tracker duplicate-search first.
- Execution contract (per-unit close-out): each hunted lane/target is processed one unit at a time — hunt, verify, report (optionally file), advance cursor; a unit is closed when its verified findings are reported and deduped.
- Setup skill writes/updates the tracked project config file (lane globs, filing posture) and degrades gracefully when absent (bundled generic lane fallback).
- New skill passes `skill-quality:check`, ships `evals/evals.json`, all repo CI gates pass, and `plugin.json` is version-bumped per convention.
- Skip-when fences for all eight named neighbors present in the skill description.

### Captured assumptions

- Operator's actual daily-routine vehicle unknown — V1 supports both lane-prompt and standalone/Routine invocation equally; revisit if a concrete lane deployment surfaces new needs.
- `scan` remains an approved read-only verb in the verb table — revisit if PLUGIN-PHILOSOPHY's verb contract changes.
- The bug-report plugin's existing persisted-report path (`${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`) is reusable for scan findings — revisit if the impl-surface exploration shows a conflicting convention.

### Out-of-scope

- Fixing bugs in the same run (routes to `debugging:debug` / remediation lanes).
- Cross-repo scanning (post-V1; compose repo-fleet infrastructure when it comes).
- Formal loop-lane convention adoption — telemetry comments, role-label escalation, autonomy matrix (explicit post-V1 follow-up through the owner doc).
- Born-briefed / verified+briefed self-filing (deferred pending a dogfood-filing owner-contract amendment).
- Detector-findings-format persistence (deferred unless deterministic sub-rules emerge that pass the admission test).
- A new standalone `bug-finding` plugin (superseded by extending `bug-report`).

### Deferred questions

*(none — all 18 register rows resolved; the deferrals above are scope decisions, not open questions)*

## Plan

<!-- populated by /planning:plan -->
