---
name: audit-model-fit
description: "Audit local Claude Code instruction surfaces (user + project CLAUDE.md, skill SKILL.md bodies + context files, agent definitions, .claude/rules, prompt-type hooks and output styles) for deterministic constraints that hobble newer, more capable models — bare prohibitions with no rationale, over-prescriptive step lists, over-constraining example blocks, and stale model-era workarounds — and propose removals/rewrites against the bar 'would removing this cause Claude to make mistakes?'. Use when: 'audit model fit', 'unhobble my instructions', 'after a model upgrade', 'are my CLAUDE.md constraints still needed', 'prune stale prompt instructions', 'my skills are too prescriptive'. Report-only: proposes diffs, never auto-applies."
argument-hint: "[scope] — scope: claude-md|skills|agents|rules|hooks|all (default: all)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Instruction-surface inventory: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-model-fit/scripts/instruction-surface-scan.sh" 2>/dev/null || echo "scan unavailable"`

## Purpose

Upgrade-triggered (or on-demand) audit that sweeps the local Claude Code instruction surfaces and
proposes removals/rewrites of deterministic constraints that hobble newer models. Instructions written
to make a prior, weaker model behave — bare prohibitions, mechanical step lists, defensive
over-specification — become carrying cost and can *degrade* a capable model's output. This audit finds
them and proposes changes; a human applies them.

The governing bar: **"Would removing this instruction cause Claude to make mistakes?"** If no, it is a
removal or loosening candidate. The full check catalog, treatments, sources, and output format live in
[reference/criteria.md](reference/criteria.md) — read it when running this audit.

## Scope boundary (compose with — route out, do not restate their logic)

This audit owns instruction **content fit** to the current model. Four adjacent skills own neighboring
questions; route findings that belong to them rather than handling them here:

- `claude-memory:audit` — instruction-layer **health** against a codified checklist (is `CLAUDE.md`
  well-formed, within length, are rules valid). It reads the same surfaces and shares the pruning bar,
  but asks "is the instruction layer healthy?"; this audit asks "do its constraints still fit a newer
  model?". Route structure/health/length findings there; keep model-fit loosening here.
- `skill-quality:check` — **structural** SKILL.md lint (frontmatter, line caps, broken refs).
- `docs-hygiene:compress` — **token brevity** (shorten prose without dropping meaning). This audit
  removes now-unnecessary *constraints*, not just words.
- `claude-config:audit` — **config-file** hygiene (settings.json / .mcp.json / hooks / permissions).

## Cross-repo routing (standards-managed materializations)

A finding inside a file **synced from `melodic-software/standards`** (owned upstream per that repo's
`distribution/sync-manifest.yml`) is **never edited in place** — the next sync overwrites it. Route the
change upstream to the owning repo and say so in the report; propose no in-place diff for that file. If
the manifest is not reachable from the consuming repo, still apply the rule: flag any vendored/synced
file for upstream routing. Locally-owned surfaces get the normal human-gated proposed diff.

## Arguments

Parse `$ARGUMENTS` for an optional scope filter:

- `claude-md` — user + project `CLAUDE.md` only
- `skills` — skill `SKILL.md` bodies + `context/`/`reference/` files only
- `agents` — agent definitions only
- `rules` — `.claude/rules/**/*.md` only
- `hooks` — prompt-type hook scripts + output styles only
- `all` — everything (default)

This skill is **report-only**. There is no `--fix`: every change is human-gated. It proposes diffs; a
human (or a skill the human explicitly invokes) applies them.

## Phase 1: Enumerate surfaces

Run the deterministic scan (also injected above at load):

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-model-fit/scripts/instruction-surface-scan.sh"
```

It reports the surface inventory and flags the two grep-able smells as **candidates** — bare
prohibitions (C1) and example-dense files (C3). `--candidates` lists each `file:line`; `--count` prints
the bare-prohibition count. Candidates are starting points, not verdicts.

If a scope filter was given, read only the matching surfaces in Phase 2.

## Phase 2: Classify against the check catalog

Read [reference/criteria.md](reference/criteria.md) and read the in-scope surfaces. For each candidate,
and each instruction in the surfaces you read, apply the checks:

- **C1 bare prohibition** → propose a **prohibition + rationale** rewrite, not deletion (the constraint
  may still be needed; only the missing *why* is the defect).
- **C2 over-prescriptive step list** → cull to intent + hard constraints; keep steps that encode a real
  ordering/safety/contract.
- **C3 example-dense** → trim toward 3–5 format-steering examples; **not** a blanket ban — a file at or
  below the range is not a finding.
- **C4 stale model-era workaround** → verbose over-specification compensating for a prior model's
  weakness; propose removal/loosening.

Measure every candidate against the pruning bar. **No** (removal changes nothing) → removal/loosening
candidate. **Yes** → keep it (for a C1, still propose the rationale rewrite). A clean sweep is a valid
outcome — do not manufacture findings.

## Phase 3: Report + proposed diffs (human-gated)

Present findings as the table and proposed-diffs format in
[reference/criteria.md](reference/criteria.md) "Output format": one row per finding with its check,
surface, pruning-bar verdict, proposed change, and routing. For each locally-owned finding, give the
exact before/after rewrite. For a standards-managed finding, the routing reads
"upstream: melodic-software/standards" and **no** in-place diff is proposed.

Then stop. Do **not** edit any `CLAUDE.md`, `SKILL.md`, agent definition, rule, hook, or output style.
Applying the diffs is a human action (or a separate skill the human explicitly invokes):

> "Here are the proposed changes. Which would you like applied? I will not change any file without your go-ahead."

## Consumer conventions

A consuming repo may declare, in its own `CLAUDE.md` / `.claude/rules/`, prohibitions it deliberately
keeps bare, example sets it intends to hold above the 3–5 range, or surfaces exempt from this sweep.
Read those when present; this skill does not assume them.
