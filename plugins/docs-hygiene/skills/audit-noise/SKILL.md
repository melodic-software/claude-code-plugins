---
name: audit-noise
description: "Classify tracked markdown for five noise shapes — historical citations, ghost refs to ephemeral working-directory paths, \"Why this file exists\" preambles, hard-coupled enumerated consumer lists, and scope/loading meta-commentary — emitting Tier 1 (remove/relocate), Tier 2 (review needed), and Tier 3 (likely legitimate) findings with per-shape treatment guidance; read-only, no edits applied. Use when: 'audit markdown noise', 'declutter', 'check for stale citations', 'find ghost refs', 'classify preamble', 'sweep a rule/skill/convention doc for noise', or before editing any tracked .md — not for prose flavor/compression (use /compress) or structural markdown lint (your repo's markdown linter)."
argument-hint: "[audit] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash(bash *audit-noise/scripts/detect.sh*)
shell: bash
metadata:
  workflow-stage: anytime
  summary: Classify markdown for stale citations, ghost refs, and meta-commentary
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files: !`git status --porcelain 2>/dev/null | grep '\.md$' | head -10 || echo "none"`
Noise findings (sample): !`bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh" 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Tracked markdown — rules, skill bodies, instruction files (`CLAUDE.md`, `AGENTS.md`), `docs/`, READMEs — accumulates five NOISE shapes distinct from FLAVOR (owned by the sibling `/compress`). Each shape carries a maintenance tax plus a reader-facing tax that compounds across the corpus. This skill is a read-only classifier: it surfaces candidates with treatment guidance; the author hand-applies every edit.

## Existence pre-check (before in-page noise)

Before classifying in-page noise, ask the whole-page admission question first:
**could a reader with repository search derive this page's content from the
code itself?** A page failing admission is a deletion candidate — its finding
recommends relocate-then-delete (salvage anything admissible first), never a
line-level noise treatment, and never auto-delete (this skill stays
read-only).

Four categories always pass admission regardless of derivability: decisions,
domain language, thin navigation, and policy/wiring. For the four-factor
scoring behind a contested call, reuse `/docs-hygiene:audit-derivability`'s
rubric by reference — namespaced skill invocation, optional: invoke it when
available; otherwise apply the admission question above standalone.

**Org override.** This pre-check is a portable-baseline default. When the
consuming repository declares its own documentation-existence convention,
resolve and defer to it via `/discipline:follow-our-standards`'s resolution
ladder (repo-declared source → repo's own conventions → this portable
baseline) instead of the default above.

Only a page that passes admission proceeds to the five in-page NOISE shapes below.

## Noise shapes and treatments

| Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|
| `citation` — historical citations | Dated incident citations, inline provenance attribution, migration/rename narration ("Empirically observed 2026-…", "was renamed to", "we pivoted from") when the current form suffices | 1 | Relocate to a per-file `## Sources` / `## History` footer; strip when non-load-bearing (version control preserves history). Keep inline only when the date is load-bearing (methodology or freshness stamp) |
| `ghost-ref` — ephemeral working-directory refs | Concrete paths into the topic-docs convention's ephemeral tiers — memory slices (`.work/<slug>/`), branch-pruned contract slices (`docs/topics/<slug>/`), and concrete children of the concern-scoped roots — cited from durable surfaces, plus any citation of the retired `.claude/notes/` location | 2 | 3-way classify: promote the content to a durable home, replace with a commit-SHA permalink, or strip. Exemptions apply per matched path, never per line: slot-variable forms (`<slug>` as a schema placeholder, not a literal name) and the bare concern-scoped roots (`.work/handoffs/`, `.work/reviews/` with nothing concrete after) are NOT ghost refs — a concrete child under a concern root flags |
| `preamble` — "Why this file exists" openers | Opening section explaining motivation/history/rationale | 2 | Diataxis classify: KEEP on Explanation-quadrant files (rule bodies, ADRs, convention rationale); STRIP on Reference-quadrant files (data tables, registries, cheat-sheets), replacing with a 1-sentence orientation |
| `enum-list` — hard-coupled consumer lists | Tables/lists hardcoding N specific consumers that drift on every add/remove ("the following five skills…", bulleted `/skill — role` rosters) | 1 | Replace with a runtime derivation (a grep/list command cited inline) or a category citation; hardcode only when both fail |
| `scope-meta` — scope/loading meta-commentary | Body prose restating loading mechanics that config/frontmatter already owns ("Path-scoped to X", "Loads on Read of Y", "Auto-loads when…") | 1 | Strip the clause — the frontmatter/config is the single source of truth; keep a genuine cross-ref riding the same sentence. Files with no scoping frontmatter MAY state scope in one sentence |

Consumers with their own ephemeral-path or noise conventions can refine these defaults in their repo's `CLAUDE.md` / rules; the classifier's shapes and tiers above are the skill's built-in baseline.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files from git; file path → single-file; dir path → batch | run `bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh"` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |

Single action v1; `relocate` and `generalize` actions are deferred until real demand surfaces — author hand-edits driven by audit output cover the sweep workflow.

## Auto-detect default

1. Empty arg AND clean tree → friendly no-op exit 0 ("No uncommitted .md files. Pass file/dir target.")
2. Empty arg AND uncommitted `.md` files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash` ops. The author owns every treatment edit.
- **Tier semantics.** Tier 1 = definite noise; Tier 2 = review needed; Tier 3 = likely legitimate (surfaced for awareness).
- **Section EXEMPTIONS never flagged:** `## Recheck triggers`, `## Cross-references`, `## Sources` / `## History` / `## External authority` footers, ADR amendment blocks, `CHANGELOG.md` entries and release notes, frontmatter.
- **Opt-out markers respected.** `<!-- markdown-discipline-ignore -->` (covers the next paragraph) and `<!-- markdown-discipline-ignore-line -->` (next line) skip the wrapped content.
- **Convention-path exemptions apply per matched path, never per line.** An angle-bracket slot variable (`.work/<slug>/…`, `docs/topics/<slug>/…`) is a schema placeholder, not a literal path; the reserved concern-scoped roots (`.work/handoffs/`, `.work/reviews/`) are citable only bare or with a placeholder child — a concrete child under them flags. A convention token on a line never exempts a concrete ghost ref sharing that line; the tracked concern file (`.claude/topic-docs.yaml`) matches no ghost-ref pattern and needs no exemption. Exception: the retired `.claude/notes/` location flags even in placeholder form.
- **Output deterministic.** Filenames sort lexically; per-file tier rows sort by line number; no timestamps in output.
- **Default action is the audit action** — `/audit-noise <file>` is identical to `/audit-noise audit <file>`.

## Output schema

Per target file, the existence pre-check verdict precedes the in-page findings:

```text
<file>: admission PASS
<file>: admission FAIL — deletion candidate (relocate-then-delete recommended)
```

A FAIL skips the in-page tier table below; a PASS proceeds to it:

```text
<file>: N finding(s) — T1=<n>, T2=<n>, T3=<n>

| Tier | Shape | Line | Excerpt | Treatment |
|------|-------|------|---------|-----------|
| 1    | citation | 42 | "Empirically observed 2026-..." | Relocate to a ## Sources / ## History footer |
| 2    | ghost-ref | 87 | ".work/foo-slice/PLAN.md cites..." | 3-way classify (promote / SHA-permalink / strip) |
| 2    | preamble | 7  | "## Why this file exists" | Diataxis classify (KEEP if Explanation; STRIP if Reference) |
| 3    | preamble | 1  | (top-of-file orientation paragraph) | Likely legitimate; surfaced for awareness |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2, <T3> Tier 3 findings.
```

`shape` values: `citation`, `ghost-ref`, `preamble`, `enum-list`, `scope-meta`.

## What this skill is NOT

- **Not `/compress`.** The sibling `/compress` owns FLAVOR (filler, hedging, articles, redundant restatement); `/audit-noise` owns NOISE (the five shapes above). Different concerns; both may apply to the same target iteratively.
- **Not a markdown linter.** Structural GFM conventions belong to the repo's markdown linter (e.g. markdownlint-cli2); `/audit-noise` is semantic noise classification.
- **Not an Edit operation.** Read-only: it surfaces findings; the author applies treatments.
- **Not a content deduplicator.** When the noise is the same concept repeated across 3+ files, that is the sibling `/extract-ssot`'s territory.

## Sources

- [Diataxis Explanation](https://diataxis.fr/explanation/) — the Diataxis classifier behind the preamble treatment
- [markdownlint configuration](https://github.com/DavidAnson/markdownlint?tab=readme-ov-file#configuration) — opt-out marker HTML-comment form precedent
