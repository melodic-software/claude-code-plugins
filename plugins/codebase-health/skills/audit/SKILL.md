---
name: audit
description: "Audit a codebase for drift between docs, config, code, and architecture. Verifies every factual claim against reality via parallel subagent fan-out, severity-rates findings and reports read-only; remediation is delegated to the implementation/verification lanes (`--fix` hands the findings to `/implementation:implement` then `/verification:confirm`). Use when: 'audit codebase', 'check for drift', 'verify docs', 'full audit'. Flags: `--fix` (hand findings to the remediation lanes after reporting), `--docs-only`, `--code-only`, `--config-only`, `--arch-only`."
argument-hint: "[scope] [--fix] [--docs-only|--code-only|--config-only|--arch-only]"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "(unavailable)"`
Changed files (staged+unstaged): !`git diff --name-only HEAD 2>/dev/null || echo "none"`

## Variables

Arguments: `$ARGUMENTS`

## Argument Parsing

Parse `$ARGUMENTS` for:

- **Scope** (optional): directory or file path to limit the audit (default: entire repo)
- **`--fix`**: after reporting, hand the findings off to the remediation lanes
  (`/implementation:implement` then `/verification:confirm`) rather than fixing inline — see
  [Remediation](#remediation-delegated-to-other-plugins). Per the naming doctrine's verb
  contract, bare `audit` is READ-ONLY — it reports at Phase 3 and stops; remediation intent sits
  behind this explicit override. (`--review-only` is accepted as a legacy alias for the bare
  read-only default.)
- **Dimension filters** (optional, mutually exclusive):
  - `--docs-only`: only documentation checks
  - `--code-only`: only code-quality checks
  - `--config-only`: only configuration checks
  - `--arch-only`: only architecture checks

If no filter is specified, audit every active dimension — the Phase 1 per-file fan-out makes
dimension order irrelevant (each file gets its own subagent). Enumerate `primary-sources` across all
active dimensions and dispatch per file.

## Read-only default

Bare invocation — by the user or the model — runs the audit (Phases 0–3) and stops at the Phase 3
report. Remediation is never inlined here; it is delegated to the `implementation`/`verification`
lanes and hands off only under an explicit `--fix` from the user (or an equally explicit "fix what
you find" instruction in their prose). Model auto-invocation never supplies `--fix` on its own.

---

## Adapting to your environment (graceful degrade)

The audit itself (Phases 0–3) is self-contained. Where Phase 2 names an adjacent capability —
documentation-research tools (MCP docs servers, library-docs lookers-up, web search) — treat it as
optional: use it if your setup provides one, otherwise follow the inline graceful-degrade guidance,
which confidence-tags the externally-unverifiable part `needs-review` rather than guessing.

Remediation is different: it is **delegated**, not inlined. Fixing, verifying, self-reviewing, and
retrospecting are owned end-to-end by the `implementation`/`verification` lanes (see
[Remediation](#remediation-delegated-to-other-plugins)). When those plugins are absent the
Phase 3 findings table is the handoff — remediate manually in the reported fix-priority order — NOT
a cue to re-inline a fix/verify/review loop here.

Scope boundary with adjacent audit lanes: this skill verifies **factual claims** in docs/config
against code state. Claude Code configuration files (`settings.json`, `.mcp.json`, hooks,
permissions) and automation-landscape gap analysis are different lanes — when the
`claude-config` plugin is installed, route those to `/claude-config:audit` and
`/claude-config:audit-automation-gaps`; otherwise state they are out of scope rather than
running claim-extraction over them.

---

## Audit dimensions & targets (tracked config seam)

Per-dimension audit targets — `primary-sources` (where claims live), `verification-sources` (where
to verify), and `example-claims` (illustrative `{ claim, verify-via }` rows for the claim-extraction
pass) — come from the consuming repo's tracked config, resolved additively across three layers:

1. `~/.claude/codebase-health.md` (user-global, optional)
2. `.claude/codebase-health.md` (team, tracked)
3. `.claude/codebase-health.local.md` (personal overlay, gitignored)

The four bundled dimensions are `documentation`, `configuration`, `code-quality`, and
`architecture`; the config may tune their globs, remove a dimension, or add custom ones.

**Merge semantics when the same dimension name appears in two layers:** additive by default — the
later layer's `primary-sources` and `verification-sources` globs UNION with the earlier layer's (not
replace), and `example-claims` concatenate with duplicate `claim` text collapsed. A layer removes an
inherited dimension by declaring it with empty source lists (an explicit opt-out), never by silent
omission. This keeps a personal overlay purely additive to team config unless it deliberately zeroes a
dimension out.

Settle targets by this ladder:

1. **Config present → use it.**
2. **Absent → infer from the repo** (doc dirs, build manifests, source/test roots, CI workflows),
   then **persist the inference** by offering to run `/codebase-health:setup` — so the next run is
   deterministic.
3. **Cannot infer → ask the user**, and offer to persist the answer via setup.
4. **Otherwise → safe generic defaults**: documentation = `docs/**/*.md` + `README.md` + any
   agent-instruction files; the other dimensions require inference or config — skip a dimension
   you cannot ground rather than guessing.

Never hardcode a repo layout; read a declared value, infer-and-record, or ask.

## Emit checklist

For any audit run (Phases 0–3), copy
`${CLAUDE_PLUGIN_ROOT}/skills/audit/templates/checklist.md` into wherever the consuming
repo keeps working task notes (or keep it in-response). Tick each phase as completed. Remediation is
delegated to the `implementation`/`verification` lanes and is not part of this checklist.

---

## Phase 0: Prime Context

Before auditing, load what "correct" looks like in this repo:

1. **Read the consuming repo's `CLAUDE.md` / `AGENTS.md` and `.claude/rules/` files** (where
   present) — conventions, naming rules, enforcement expectations.
2. **Resolve the audit config** per the dimension seam above; read the convention files its
   `verification-sources` name.

These define the lens through which findings are evaluated. A claim contradicting repo conventions
is a finding; one following them is a verified non-issue. You cannot make that judgment without
reading conventions first.

---

## Phase 1: Discover

The goal is exhaustive verification, not sampling. Every factual claim in every relevant file must
be checked against reality. The most common audit failure is skipping items — thoroughness beats
speed.

Discovery runs as a **parallel subagent fan-out — one agent per primary-source file**, NOT a single
sequential pass (fresh context per file ≈ 2× claim coverage and ~4× drift caught; a single context
skips claims as it fills — the #1 audit failure). Each agent applies the claim-extraction method
(read top-to-bottom → extract every factual claim → verify each independently → record), fenced per
the scope-fencing rules in [`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/discovery-method.md`](context/discovery-method.md).

**Scope first (MANDATORY — cost gate):** require a `[scope]` or dimension filter (`--docs-only`
etc.) for large targets; if the enumerated list exceeds ~20 files, confirm with the user before
dispatching. Never fan out the whole repo unprompted — an unscoped run across every doc/config/
source file costs millions of tokens.

Full method — claim-extraction steps, the verify-ALL-claims-on-a-line rule,
enumerate/scope/dispatch/collect detail, and the per-finding report format — in
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/discovery-method.md`](context/discovery-method.md).
Dimension-specific claim guidance:
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/reference/audit-checklist.md`](reference/audit-checklist.md).

---

## Phase 2: Validate & Enrich

Re-read each finding to confirm accuracy. This is the false-positive gate — every finding must
survive scrutiny before being reported.

**Validate independently, not by self-review.** When Phase 1 ran as a fan-out, dispatch the
false-positive gate as a SEPARATE subagent that re-verifies each finding against the source of
truth — do NOT let the discovering agent grade its own findings. A model re-checking its own work
rubber-stamps it; an independent agent re-reading the doc claim AND the actual code catches both
false positives and miscategorized-but-correct claims. Fence each validator to read-only (its
findings' files + verification-sources).

### External research (required when the tooling exists)

When your setup provides documentation-research tools (MCP docs servers, library-docs lookers-up, web
search), using them is REQUIRED — not optional — to validate findings involving:

- **Best-practice claims** — is the documented pattern the current recommended approach?
- **Library API claims** — does the method/class/parameter exist in the current version?
- **Configuration behavior** — does the setting do what the docs say?

Cross-reference research results against the repo's conventions (loaded in Phase 0). External
consensus matters, but repo conventions are the primary lens — a pattern unusual industry-wide may
be intentionally chosen here.

**Graceful degrade when no research tool is available:** do not skip the claim and do not guess.
Verify whatever the local repo can confirm, then confidence-tag the externally-unverifiable part as
`needs-review` (below) so it surfaces for human judgment rather than being asserted or dropped.

### False-positive prevention

**If uncertain, it is NOT a finding.** Ambiguous items go to `needs-review` and are separated from
confirmed findings in output. The cost of a false positive (eroding trust in the audit) exceeds the
cost of missing a marginal issue (catchable next run).

### Tag findings with confidence

- **verified**: confirmed by reading source files AND (where applicable) external research
- **likely**: strong evidence, one piece ambiguous — still reported as a finding
- **needs-review**: requires human judgment — separated from confirmed findings in the output

---

## Phase 3: Categorize & Present

### Group findings per [`${CLAUDE_PLUGIN_ROOT}/skills/audit/reference/category-playbook.md`](reference/category-playbook.md)

Fix order matters — see the playbook for why: Config Drift → Missing Enforcement → Code Quality →
Doc Drift.

### Output format

Use this exact table with consistent `error`/`warning`/`info` severity:

| # | Severity | Category | File:Line | Description | Verification |
|---|----------|----------|-----------|-------------|-------------|
| 1 | error | doc-drift | `<convention-file>:<line>` | Doc claims suppression includes rule X but actual list is `Y;Z` | Read `<build-config>:<line>` |

### Required sections after the findings table

1. **Verified non-issues** — every claim checked that turned out correct. This is the thoroughness
   proof. Include at least as many verified items as findings.
2. **Drift patterns** — group related findings and identify root causes (e.g., "7 findings trace to
   a registration refactor where code was updated but docs weren't")
3. **Fix priority** — recommended fix order per the category playbook
4. **Enforcement escalation** — for each finding, what automated enforcement (formatter, linter,
   analyzer, type check, test, git hook, CI gate) could catch this class automatically?
5. **Config-gap observations** — dimensions, globs, or `example-claims` this run showed are worth
   adding to the tracked `.claude/codebase-health.md` (e.g. a source tree that held drift but wasn't
   a configured `primary-source`). Offer to persist them via `/codebase-health:setup apply` so the
   next run covers them deterministically.

### Zero-findings outcome

If the audit finds no discrepancies, report a clean bill of health:

- Present the **verified non-issues** list as proof of thoroughness (this is the whole point —
  showing what was checked)
- State explicitly: "No findings. All claims verified as correct."
- Do NOT invent findings to justify the audit. A clean codebase is the goal, not a guaranteed list
  of issues.
- Nothing to remediate, so no handoff. Still include the config-gap observations (§5) — a clean run
  is the best time to note coverage gaps worth persisting via `/codebase-health:setup apply`.

### Fix gate

**Without `--fix`** (the default, including every model auto-invocation): present the full
report and **STOP** — the Phase 3 report is the deliverable.
**With `--fix`**: present the summary count, then hand off to the remediation lanes below.

---

## Remediation (delegated to other plugins)

The audit ends at the Phase 3 report: the findings table, verified-non-issues proof, drift patterns,
fix priority, enforcement escalation, and config-gap observations ARE the deliverable. Fixing,
verifying, self-reviewing, and retrospecting are separate lanes owned end-to-end by other plugins —
re-implementing them here would duplicate those skills, so this skill delegates instead.

Route remediation to the dedicated lanes (soft dependencies — use when the plugin is installed):

- **Fix** → `/implementation:implement` (when the `implementation` plugin is installed). Hand it the
  Phase 3 findings, whose "Fix priority" section already carries the Config Drift → Missing
  Enforcement → Code Quality → Doc Drift order (see
  [`reference/category-playbook.md`](reference/category-playbook.md)); that lane owns the fix cadence
  — TDD, build/test at each checkpoint, and the post-fix simplification pass.
- **Verify** → `/verification:confirm` (when the `verification` plugin is installed). Confirms the
  fixes against the repo's own build/test/lint gates with no regressions, and covers the self-review
  and retrospective that the fix lane hands it.

**With `--fix`**, present the Phase 3 findings and output an explicit user-directed suggestion to run
`/implementation:implement` with those findings, then `/verification:confirm`. Do NOT auto-invoke
either skill — the user drives both. When those plugins are not installed, say so and stop: the
Phase 3 findings table is the handoff, to be remediated manually in the reported fix-priority order.
Never re-inline a fix/verify/review/retro loop here.
