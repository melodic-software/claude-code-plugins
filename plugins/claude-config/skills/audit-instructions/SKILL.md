---
name: audit-instructions
description: "Audit locally-owned Claude Code instruction surfaces — user + project CLAUDE.md, .claude/rules, skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo directives, stale examples — plus instructions that misstate Claude Code's own behavior, cite a file in a form that never loads, or re-read a surface already in context. Also detects cross-surface conflicts: two surfaces that both claim authority over one behavior and contradict each other. Report-only: emits a findings report with proposed diffs, gated to the human, never auto-applied. Use when: 'after a model upgrade', 'are my instructions holding the model back', 'instructions the model no longer needs', 'too prescriptive', 'audit instructions', 'instruction audit', 'stale Claude Code behavior', 'outdated harness claim', 'my @path import is not loading', 'instruction re-reads CLAUDE.md', 'conflicting instructions', 'contradictory instructions', 'which instruction wins'. Not a brevity pass and not memory-layer hygiene."
argument-hint: "[scope] — scope: claude-md|rules|skills|agents|hooks|output-styles|conflicts|all (default: all)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Audit whether the instructions you have written for Claude Code are still earning their context cost
against **current** model capability. As models improve, prior-model-era scar tissue accretes:
workarounds for mistakes the model no longer makes, prescriptive step lists that now constrain more
than they help, bare prohibitions, and show-your-thinking directives. This skill sweeps the
locally-owned instruction surfaces, cites each finding to current official prompting doctrine, tiers
it by how confident the evidence can be, and packages proposed removals or rewrites as a human-gated
diff — so instruction surfaces shrink as models get better instead of only ever growing.

The check catalog — the fifteen checks I1–I15, their evidence tier, authority tag, severity and
per-surface applicability — lives in [reference/criteria.md](reference/criteria.md); the
deterministic pre-scan is `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh`.
One check has a different unit of judgment — do two surfaces contradict each other? — and Phase B2
answers it against [reference/conflict-criteria.md](reference/conflict-criteria.md).

## Read-only contract

This skill is report-only. There is no `--fix`: instruction files are the operator's voice —
every change is applied by the human (or explicitly delegated afterward), never by this skill.
Diffs are proposed artifacts. A clean audit is a valid outcome.

## Scope boundary (route out)

This skill owns instruction **content vs current model capability**. It does not own the adjacent
concerns its siblings already cover — route rather than re-answer:

- Structural skill lint (frontmatter, line caps, broken refs) is `skill-quality:check`.
- Token brevity for its own sake is `docs-hygiene:compress`.
- Config-file mechanics (settings.json, .mcp.json, hooks wiring) is `claude-config:audit`; grant
  portability is `claude-config:audit-permission-grants`.

On **memory-layer surfaces** (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`),
this skill runs the model-era checks I6–I12 and the pair check I15, never the hygiene checks I1–I5 —
that layer belongs to `claude-memory`. When that plugin is installed, route memory-layer hygiene to
its `audit` skill; when it is not, emit a one-line pointer to the official include/exclude guidance
(recorded with I1–I5 in [reference/criteria.md](reference/criteria.md)). Either way no I1–I5 finding
is produced here. On **non-memory surfaces** the catalog applies — no incumbent auditor covers
instruction content there — **bounded by each row's own surface declaration**, which is narrower for
some checks. I13 and I14 name their own surface sets; this partition never widens a row.

**Upstream-owned surfaces are excluded from the editable set.** Installed plugin-cache content is
owned by the publishing repository, and a managed materialization by whatever upstream the consuming
repo's distribution seam names (a `managed` versus `locally-owned` split in the sync manifest that
repo documents, when it does). Findings on these become routing recommendations to the owning
repository's tracker, never in-place edits; absent such a declaration, no exclusion applies.

## Arguments

Parse `$ARGUMENTS` for an optional scope filter that narrows which surfaces the inventory collects:

- `claude-md` — user + project CLAUDE.md and CLAUDE.local.md only
- `rules` — `.claude/rules/` and `~/.claude/rules/` only
- `skills` — skill bodies and their context/reference files only
- `agents` — agent definition markdown only
- `hooks` — prompt-type hook text only
- `output-styles` — output-style markdown only
- `conflicts` — Phase A plus Phase B2 only, so a scheduled routine can compose it on its own budget
- `all` — every locally-owned surface, and the conflict pass (default)

## Phase A — Inventory

Enumerate the locally-owned instruction surfaces in scope. All paths below are current per the
official memory and `.claude`-directory docs (cited in the report's Sources line):

- User — resolve the root as `${CLAUDE_CONFIG_DIR:-~/.claude}` (setting `CLAUDE_CONFIG_DIR`
  relocates the whole `~/.claude` tree, so never hardcode `~/.claude`), then: `CLAUDE.md`,
  `rules/`, `skills/`, `agents/`, `output-styles/` under that root.
- Project: `./CLAUDE.md` or `./.claude/CLAUDE.md`, `./CLAUDE.local.md`, and every nested
  `CLAUDE.md` / `CLAUDE.local.md` in subdirectories of the project tree (Claude loads these on
  demand when it reads files in those directories, so walk the tree — do not stop at the root);
  `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.claude/output-styles/`.
- Prompt-type hook text configured in the project or user `settings.json`.

Exclude, and hold for the routing subsection instead of the editable set: auto-memory
(`~/.claude/projects/<project>/memory/`, owned by `claude-memory`), org-managed policy CLAUDE.md,
installed plugin-cache content, and any managed materialization per the Scope boundary. Record
each surface found and each surface skipped, so the report's tier-transparency line can name both.

## Phase B — Per-surface lanes

Run one **fresh read-only subagent per surface**, each sharing
[reference/criteria.md](reference/criteria.md) and applying the per-surface check partition from
the Scope boundary. Seed each lane's mechanical tier with the deterministic pre-scan over that
surface's files:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh" <file>...
```

It emits `file:line:check-id` candidate rows for I6 (bare prohibitions lacking a rationale marker)
and I10 (reasoning-echo directives); `--count` prints the row count. Advisory — a grep cannot judge
whether a rationale is genuinely present, so the lane refines every candidate.

Bound concurrency to 3–5 lanes at a time; the skills surface fans out one lane per skill. Before the
total dispatch count (lanes plus Phase C verifiers) would exceed ~20, confirm with the user.

## Phase B2 — Cross-surface conflict pass

Phase B judges each surface alone, so a contradiction spanning two surfaces is invisible to it. This
pass supplies the missing unit: a **pair** of surfaces that both claim authority over one behavior and
disagree. Every criterion, table and worked example lives in
[reference/conflict-criteria.md](reference/conflict-criteria.md). **A scope filters findings, never
reads** — B2 enumerates every surface `all` would collect and reports a pair when at least one anchor
is in scope; the criteria file states why.

Seed it with the deterministic pre-scan over the inventoried files:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/conflict-scan.sh" <file>...
```

It emits `fileA:lineA|fileB:lineB|entity|flags` candidate pairs; `--count` prints the row count.
Advisory and always exit 0, so every row is refined against the criteria file's must-not-flag set.

**The scan is a priority ordering, not the work list.** It only reaches directives naming a
tool-shaped entity, so an ordinary pair — "Always run tests before committing" against "Never run
tests" — emits nothing. Work the rows first, then read the surfaces for pairs it cannot shape-match.
**A pass that reports only what the scanner emitted has not run this check.**

**Detect the disagreement; do not adjudicate it:** name a winner only where the criteria file's
precedence table cites a documented order, otherwise report `unresolved`. Its routing table governs
what belongs to `claude-memory:audit`'s C6 instead.

## Phase C — Verify pass

Every removal or rewrite proposal is re-judged before it reaches the report. Dispatch **fresh-context,
non-fork** subagents — this is a self-grade of the audit's own proposals, so a fork that inherits the
producing context would not be independent — prompted to refute: "would removing this instruction
cause Claude to make mistakes? Argue that it is still load-bearing." Where the removal call is
high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is
installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this
artifact, invoked per its own docs — with
the fresh-context same-vendor subagent as the fallback, never a route to a command that may not
resolve. Batch one verifier per surface
(not one per finding), counted under the same ~20-dispatch gate. A proposal the verifier defends is
demoted to `info` or dropped, never surfaced as a confident removal.

**A conflict pair takes a different refutation**, because the removal prompt cannot falsify it: both
sides are usually load-bearing, so "argue it is still needed" defends both and demotes the finding
untested. Refute a pair on its own gates — *same observable, or two sharing a keyword? does any
resident text already arbitrate? is there a prompt that fires both?* A defended pair is one where a
gate fails, dropped for that named reason.

## Phase D — Report

Persist the report to `${CLAUDE_PLUGIN_DATA}/audit-instructions/last-audit.md` and summarize it in
chat. Present findings as a table:

| # | Check | Surface:Line | Severity | Tier | Authority | Finding | Proposed change |
|---|-------|--------------|----------|------|-----------|---------|-----------------|

Phase B2's findings carry two anchors, so they get their own **Cross-surface conflicts** subsection.

For each finding, give the proposed removal or rewrite as a fenced diff block. Tier is `mechanical`
(pattern-detectable) or `behavioral` (its ground truth is observed behavior); authority is the
check's tag from the catalog. End with a **Routing** subsection listing every excluded upstream-owned
or memory-layer surface and where its findings should go, and a **Recommended follow-through**
subsection: apply an accepted change, then observe whether Claude's behavior actually shifts;
re-add on the next mistake as the compounding safety net; for example blocks, A/B against the
no-example default. That loop is prose guidance — this skill ships no eval tooling.

Open the Sources line with the two official pages the paths and doctrine derive from
(code.claude.com memory + `.claude`-directory docs; the prompting pages cited per check in the
catalog).

## Gotchas

- **Examples are not scaffolding.** Keep the 3–5 format/tone/structure-steering examples the docs
  recommend; flag an example block only when it pins the model's *approach* to a task (behavioral
  scaffolding), never when it steers output format.
- **Bare-prohibition rewrites go positive first.** The primary remediation is "say what to do
  instead of what not to do"; adding a rationale is the fallback where a genuine hard "never"
  survives. Do not mechanically delete every prohibition the pre-scan flags.
- **Behavioral findings ship as proposals, not confident cuts.** A narrow eval can miss a small
  regression from an over-aggressive trim — that is why the verify pass and the delete-and-watch
  loop exist. Never present a behavioral removal as certain.
- **Windows shell.** The pre-scans are bash; on native Windows run them through Git Bash.
- **A conflict pair needs two files.** Feeding `conflict-scan.sh` one surface at a time reproduces
  Phase B's blind spot and always reports clean.

## What this skill does NOT do

- Never edits an instruction file and never auto-files a tracker item — output is a report plus
  proposed diffs the human applies.
- Not a token-brevity pass (`docs-hygiene:compress`) and not structural skill lint
  (`skill-quality:check`).
- Not memory-layer hygiene — checks I1–I5 on CLAUDE.md/rules route to `claude-memory`'s `audit`
  skill when installed, and upstream-owned plugin-cache or managed materializations route to the
  owning repository rather than being edited here.
- Does not grade a contradiction whose two halves both sit in project-scope `CLAUDE.md` /
  `CLAUDE.local.md` / `.claude/rules/**` — that is `claude-memory:audit`'s C6.
