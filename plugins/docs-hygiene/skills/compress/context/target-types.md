# Target types + author-time-signal heuristic

Argument-shape resolution for default + audit actions, plus the mechanical-scan heuristic that drives the audit action's SKIP / COMPRESS / UNCERTAIN classification.

## Argument shapes

Per `../SKILL.md` "Auto-detect default", argument resolution at invocation:

| Invocation | Target set | Action |
|---|---|---|
| `/docs-hygiene:compress` (empty arg) AND uncommitted `.md` exist | files from `git status --porcelain` matching `*.md` | default action over each, batch |
| `/docs-hygiene:compress` (empty arg) AND clean tree | interactive: all tracked eligible `.md` offered via the repo-wide interview fallback (`../SKILL.md` "Repo-wide interview fallback"); non-interactive: (none) | interactive: confirmation-gated audit-first interview; non-interactive: friendly no-op exit 0 ("No uncommitted .md files. Pass file/dir target.") |
| `/docs-hygiene:compress <file.md>` | single file | default action, single-file |
| `/docs-hygiene:compress <dir>` | every `.md` under `<dir>` (recursive); filenames sorted lexically for determinism | default action, batch |
| `/docs-hygiene:compress audit` (empty rest) AND uncommitted `.md` exist | files from `git status --porcelain` matching `*.md` | audit action over each |
| `/docs-hygiene:compress audit` (empty rest) AND clean tree | interactive: all tracked eligible `.md` offered via the repo-wide interview fallback steps 1–2 (report-only); non-interactive: (none) | interactive: confirmation-gated free audit corpus; non-interactive: friendly no-op exit 0 |
| `/docs-hygiene:compress audit <file.md>` | single file | audit action |
| `/docs-hygiene:compress audit <dir>` | every `.md` under `<dir>`; lexical sort | audit action, batch |

Flags `--force` and `--keep-snapshot` apply per `../SKILL.md` "Action router". Position-independent within the arg list.

### Target validation

Per-target gates before any dispatch:

1. Path exists and is readable → otherwise skip target with `reason=missing`
2. Path ends in `.md` (case-insensitive) → otherwise skip with `reason=non-markdown`
3. Path NOT a symlink escaping repo root → otherwise skip with `reason=symlink-escape`
4. Path NOT inside `.git/` → otherwise skip with `reason=git-internal`
5. Default (mutating) action with an ENUMERATED target set only — any target set the user did not name file-by-file: the empty-arg uncommitted-`.md` batch (argument-shape row 1, enumerated from `git status`), directory expansion, or the repo-wide interview sweep: path NOT under a fixture convention directory (`evals/fixtures/`, and also `testdata/`, `__fixtures__/`, `test/fixtures/` when those appear — the skill's own layout uses `evals/fixtures/`; other conventions are acknowledged so consumers are not surprised, match case-insensitive on path segments) → otherwise skip with `reason=fixture` (fixture verbosity is deliberate test input — compressing it corrupts the eval, and the two most-verbose files in the authoring repo's 2026-08-15 run were this skill's own verbose fixtures). An explicitly-named single-file target bypasses this gate — naming a fixture is an intentional act, same philosophy as `--force`; the audit action is read-only and never applies it.

Binary files and non-markdown files are out of scope per `../SKILL.md` "When NOT to use".

## Author-time-signal heuristic (audit action only)

Audit is a pure mechanical scan — no subagent dispatch, no edits. Per target, compute an expected-yield estimate from six signals via `scripts/audit-scan.sh` (preferred; deterministic) or the table below; emit SKIP / COMPRESS / UNCERTAIN per the classification table.

### Six signals

| # | Signal | Method | Effect on expected-yield |
|---|---|---|---|
| 1 | Author-time-disciplined path (instruction-file glob) | path matches `.claude/rules/**` OR `AGENTS.md` OR `CLAUDE.md` OR `**/SKILL.md` (any depth) | force expected ≤ 3%; emit empirical-baseline citation (3/3 attempts reverted) |
| 2 | Inline-code-token density | `awk` count of backtick pairs (`` ` ``) per kilo-word (1000 words = 1 unit); density > 10 = high | high density → narrower compressible flavor → lower expected yield |
| 3 | Cross-reference density | regex count per kilo-word of `@`-paths, `.md` cites, file-system path tokens (`[a-z][a-z0-9._/-]+\.(md\|cs\|sh\|json\|yaml)`); density > 8 = high | high density → load-bearing references → lower expected yield |
| 4 | Explicit compression-discipline cite | `grep -F` for the fixed string `Prose compression discipline` — a file citing the consuming repo's author-time compression-discipline convention marks itself as already disciplined | match → author-time-disciplined → expected ≤ 3% |
| 5 | Default fallback (no other signal fires) | none of 1-4 match AND signal 6 does not fire | verbose-prose baseline → expected 5-15% |
| 6 | Flavor-token density (gates signal 5; computed when no signal 1-4 fires) | `grep -oiwE` count per kilo-word of a **curated flavor-token list** owned by `scripts/audit-scan.sh` (superset/subset of Phase A LATITUDE — deliberately not identical: adds very/quite/"it is important to"/"note that"/"keep in mind"; keeps might; omits bare articles). Density < 5 = already disciplined | force expected ≤ 3%; a repo authored under standing prose discipline is lean without citing any convention (empirical: 2026-08-15 authoring-repo run, 9/9 signal-5-classified files at ≤7/kw yielded 0.02-0.4% and all reverted, while this skill's deliberately-verbose fixtures measured 50-60/kw) |

### Classification table

| Expected yield | classify | reason text |
|---|---|---|
| ≤ 3% (signals 1 OR 4 fire) | `SKIP` | "author-time-disciplined; empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff" |
| ≤ 3% (signal 6 fires) | `SKIP` | "flavor-token density N/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4%" — N inlined |
| 3-7% (signals 2 OR 3 fire, no signal 1/4/6) | `UNCERTAIN` | "inline-code density H AND/OR cross-ref density H; flavor band narrow" — H values inlined |
| 5-7% band under signal 5 alone | `COMPRESS` | "verbose-prose baseline (lower band); expected flavor cuts on filler/hedging/articles" — signal 5's 5-15% effect maps here and to ≥8% |
| ≥ 8% (signal 5 fallback) | `COMPRESS` | "verbose-prose baseline; expected flavor cuts on filler/hedging/articles" |

### Output table (audit action)

Per target, one row:

| `target` | `expected_yield_pct` | `classify` | `reason` |
|---|---|---|---|
| `<relative-path>` | `N-M%` (range) | `SKIP\|COMPRESS\|UNCERTAIN` | `<reason text from classification table>` |

Aggregate at end: `Total: K skips, M compress-recommended, P uncertain`.

## Why mechanical not subagent

`audit` is a READ-ONLY pre-flight check. Dispatching a subagent per target would burn request budget against the default rule (`<3% AND 0SL → REVERT`) which audits predict cheaply. Mechanical scan ~50ms per file; subagent dispatch ~5-15s + request cost.

Empirically (authoring-repo baseline): instruction-file paths produce <3% yield 3/3 attempts. Heuristic encodes that signal as a path glob — no subagent needed to predict the same verdict.

## Recheck triggers

| Condition | Action |
|---|---|
| Audit classifies an instruction-file path COMPRESS (signal 1 misfires) | Tighten path glob OR add a signal 1 exception; note the exception in this file |
| Default-fallback files (signal 5) consistently yield <5% | Fired 2026-08-15 (authoring repo, 9/9 reverted) → signal 6 added. If it fires again, revisit signal 6's `< 5/kw` threshold (files at 5-9/kw whose flavor tokens sit inside protected quoted text also reverted) |
| Empirical yield baseline shifts beyond 3% | Update SKIP reason text + bump signal 1 expected band; rev the variant table in `context/flavor-vs-content-matrix.md` |
| New always-loaded instruction path lands outside `.claude/rules/**` | Extend signal 1 glob; verify SKIP fires on the new path |

## Cross-references

- `../SKILL.md` "Auto-detect default" + "Action router" — consumes argument-shape table
- `../SKILL.md` "Hard rules" — revert + soft-block enforcement that audit predicts
- `context/flavor-vs-content-matrix.md` — per-content-type expected-yield bands feeding the classification table
- `context/semantic-diff-prompt.md` — dispatch template (audit does NOT dispatch; default action does)
