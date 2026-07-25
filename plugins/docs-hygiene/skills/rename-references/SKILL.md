---
name: rename-references
description: "Sweep stale references after renames — the syntactic forms token-only grep misses (slash-tokens, paths, chain prose, numbered table rows, frontmatter chains and globs). Use when: 'rename X to Y', 'I renamed X', 'audit rename', 'find stale refs', 'check for stragglers', 'after git mv', 'sweep references', 'rename impact preview', 'find half-renamed state', 'broken refs after rename', 'pre-PR rename check' — actions: audit, audit blast, audit half-rename, audit orphans, apply, preview, blocklist; not for framework migrations or repo-wide dead-reference audits."
argument-hint: "[action] [<old> [to <new>]] [--include-historical|--include-memory|--include-plan-docs|--include-bare-token|--container|--identifier] (e.g., /rename-references audit, /rename-references audit blast /verify to /verify-changes, /rename-references audit half-rename /a to /b, /rename-references audit orphans /a to /b, /rename-references blocklist)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Rename pairs (git): !`{ git diff --name-status -M HEAD 2>/dev/null; git diff --cached --name-status -M 2>/dev/null; } | grep '^R' | head -15 || echo "none"`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Renames are deceptively hard. After renaming a skill, file, or identifier, references survive in 7+ syntactic forms beyond the obvious token. Token-only grep (`/old`) catches 50–70%; the rest hide in chain prose (`→ old →`), comma-lists (`Test, Old, Retro`), numbered table rows (`| 7. Old |`), frontmatter chain strings (`description: "...→ old → retro process."`), frontmatter globs (`{a,b,old,c}`), cross-skill mode references, and content-file paths (context/old.md style).

This skill makes "find every reference" one invocation instead of 4 manual sweep passes. Runs the full pattern library, triages matches into 3 buckets, surfaces ambiguity (English-verb collisions like `confirm`/`test`/`review`) for user confirmation rather than auto-applying blindly.

## Adapting to your environment

This skill is self-contained — the pattern library, triage classifier, and audit modes below need only git and the Grep tool. Where prose names an adjacent capability (a verification workflow, an issue tracker, a codebase-audit routine), treat it as optional: if your environment provides it, invoke it; otherwise proceed without. Consumer-specific conventions (work-notes locations, commit policy, naming rules) come from the consuming repository's own CLAUDE.md and rules — read them; this skill does not assume them.

## Action router

Parse `$ARGUMENTS` first token to determine action. Subsequent tokens are the rename pair (with `to`/`→`/`->`/`into` separator) or single token for reverse-mode.

| Argument shape | Action | Read |
|---|---|---|
| *(empty)* | **Smart default** | inline below — detect rename pair from conversation/git/staged |
| `audit` | **Audit** (read-only sweep — alias for `audit blast`) | [context/audit.md](context/audit.md) + [audit-modes.md](context/audit-modes.md) |
| `audit <old>` or `audit <old> to <new>` | **Audit** with explicit pair | [context/audit.md](context/audit.md) |
| `audit blast [<old> [to <new>]]` | **Audit Blast** — pre-rename impact (counts + per-file + bucket distribution; inline-only) | [audit-modes.md](context/audit-modes.md) |
| `audit half-rename <old> to <new>` | **Audit Half-Rename** — files mentioning BOTH old AND new (incomplete-rename hygiene) | [audit-modes.md](context/audit-modes.md) |
| `audit orphans <old> to <new>` | **Audit Orphans** — refs at old name OR vanished path AFTER rename (REQUIRES pair) | [audit-modes.md](context/audit-modes.md) |
| `<old> to <new>` | **Apply** full rename | [context/apply.md](context/apply.md) |
| `preview <old> to <new>` | **Preview** dry-run | [context/apply.md](context/apply.md) (skip Edit phase) |
| `<old>` (single token, no separator) | **Reverse** — find refs, ask what to replace with | [context/audit.md](context/audit.md) |
| `blocklist` | **Print English-verb blocklist** (read-only introspection of triage-bucket safety mechanism) | inline below |

**Pattern library is the load-bearing component** — the full form registry lives in [context/patterns.md](context/patterns.md); execute sweeps with the Grep tool. Read it before any sweep. Triage logic is in [context/triage.md](context/triage.md). Audit sub-mode detail (Blast / Half-rename / Orphans) is in [context/audit-modes.md](context/audit-modes.md).

## Override flags (audit modes)

Six flags. Four widen the sweep; two override the rename-mode resolution. Defaults preserve safety (rename-documenting plan docs / frozen historical notes / memory entries excluded). Long-form only, position-agnostic.

| Flag | Effect | Apply mode? |
|---|---|---|
| `--include-historical` | Sweep archived/completed work notes and frozen records of past work | OK |
| `--include-memory` | Sweep Claude Code auto-memory files (`~/.claude/projects/*/memory/*.md`) and `MEMORY.md` indices | OK |
| `--include-plan-docs` | Sweep the active plan/work-notes documents that document THIS rename | **AUDIT-MODE ONLY** — apply mode rejects with explicit error (footgun prevention; the plan doc documents the rename — both names appear by design) |
| `--include-bare-token` | Surface the bare-token residue that container-rename mode suppresses ([patterns.md](context/patterns.md) "Phase 0b"). Always **Ambiguous**, never Certain. Not applicable to `audit orphans`, which sweeps no bare-token form | **AUDIT-MODE ONLY** |
| `--container` | Force container-rename mode, skipping the evidence ladder ([patterns.md](context/patterns.md) "Phase 0b") | OK |
| `--identifier` | Force identifier-rename mode | OK |

Multiple flags compose. Unknown flags raise an error. Detail in [audit-modes.md](context/audit-modes.md) "Override flags" section.

## Blocklist action

`/rename-references blocklist` prints the English-verb blocklist literal from [context/triage.md](context/triage.md). Read-only — no edits, no sweeps. Use to inspect which tokens force the ambiguous-bucket safety path. To extend, edit `triage.md` directly.

## Smart default (no arguments)

Detect rename pairs in this priority order:

1. **Explicit args** (highest precedence — never overridden)
2. **Recent conversation** — scan last 20 turns for prose like "I renamed X to Y", "rename X → Y", "git mv X Y", or assistant edits replacing identifier X with Y across multiple files
3. **Git rename detection** — `git diff --name-status -M HEAD` and `git diff --cached --name-status -M`; `R<score>` lines map old path → new path
4. **Paired `D <path>` + `?? <similar-path>`** in `git status --porcelain` (heuristic — Levenshtein-similar basenames within same dir)

If multiple candidates surface, present via `AskUserQuestion` — user picks which pair to audit.

If zero candidates: report "No rename detected in conversation or git state. Provide `/rename-references <old> to <new>` or `/rename-references audit <old>` to invoke explicitly."

## Natural-language parser

The argument string after the action keyword can be:

| Form | Example | Parses to |
|---|---|---|
| `<old> to <new>` | `/verify to /verify-changes` | old=`/verify`, new=`/verify-changes` |
| `<old> to <new>` (mode) | `/verify to /verify-changes outcome` | old=`/verify outcome`, new=`/verify-changes outcome` |
| `<old> → <new>` | `test live → test e2e` | old=`test live`, new=`test e2e` |
| `<old> -> <new>` | `foo -> bar` | old=`foo`, new=`bar` |
| `<old> into <new>` | `legacy into modern` | old=`legacy`, new=`modern` |
| `<path/old.md> to <path/new.md>` | `confirm/SKILL.md to verify/SKILL.md` | path rename — skill applies extra path-form patterns |

Multi-word old/new is fine — separator is the only delimiter. Quote characters (`"foo bar"`) optional. Old/new taken verbatim — leading slashes preserved (`/confirm` stays `/confirm`, not `confirm`).

## Workflow phases (apply mode)

1. **Detect** — gather rename pair (args / conversation / git per Smart default)
2. **Survey** — run all patterns from `context/patterns.md` in parallel against tracked text files; aggregate per-file hit counts. For a skill/identifier rename, FIRST enumerate coupled-sibling renames (dot-form behavior point-IDs, internal mode names, content-file basenames that changed in lockstep) and queue EACH as its own rename pair — they carry no primary token, so the primary sweep never reaches them (see Gotchas "coupled-rename")
3. **Triage** — classify each match into 3 buckets per `context/triage.md`:
   - **Certain** — slash-token, path, frontmatter glob (high precision, auto-apply candidate)
   - **Chain-context** — preceded/followed by other known skill names; numbered table rows; chain prose with multiple skill tokens
   - **Ambiguous** — bare-token matches where token is in English-verb blocklist (`confirm`/`test`/`review`/`fix`/`clean`/`build`/`lint`/`verify`/`plan`/etc.)
4. **Confirm** — present buckets via `AskUserQuestion`:
   - Certain → "auto-apply N matches?" — yes/no
   - Chain-context → "review N matches one-by-one?" — yes/skip-bucket/auto-apply-all
   - Ambiguous → per-match yes/no with surrounding context
5. **Apply** — Edit each accepted match. Idempotent — running twice is safe.
6. **Re-sweep** — re-run Phase 2; exit when the ACTIONABLE count is 0 (the survey after `context/patterns.md` "Phase 0" span-precedence and "Phase 0b" container-rename mode — residue the mode rule deliberately leaves unrenamed never counts, or the loop cannot terminate). If non-zero, NEW form not in pattern library — report to user, add to `context/patterns.md`, re-iterate.
7. **Hand off** — suggest running the consuming repository's verification workflow (build + test + lint) to confirm no semantic regression in the rename target.

Audit mode runs phases 1-3 only and reports — no Edit calls. Preview mode runs 1-4 and reports planned edits — no Edit.

## Auto-exclusions

Paths skipped from sweeps automatically:

- **Rename-documenting plan/work-notes documents** — an active plan file, migration notes, or changelog entry drafted for THIS rename references the rename pair as part of documenting the migration; both names appear by design. Identify these from conversation context and the consuming repository's work-notes conventions (its CLAUDE.md / rules). Skipping prevents self-reference loops.
- **Archived/historical work notes** — completed plan documents and frozen records of past work are deliberately preserved as-is; past renames documented there are historical record, not stale references.
- `.git/`, `node_modules/`, `bin/`, `obj/`, `.venv/`, `dist/`, `build/`
- Claude Code auto-memory files in `~/.claude/projects/*/memory/` describing past renames

## Composition

| Stage | How | Why |
|---|---|---|
| Pre-rename impact analysis | `/rename-references audit <old>` | Read-only sweep, see blast radius before changing anything |
| Rename execution | `/rename-references <old> to <new>` | Sweep → triage → edit → re-sweep |
| Post-rename verification | the consuming repository's build/test/lint workflow | Confirm no semantic regression |
| Cleanup near rename sites | a separate simplification/refactor pass | Opportunistic refactor (separate concern) |

## Edge cases

- **English-verb collision** — tokens like `confirm`, `test`, `review`, `clean`, `fix`, `build`, `lint`, `plan`, `run`, `view`, `start`, `stop`, `merge`, `split`, `sort`, `filter`, `group`, `head`, `body`, `link`, `list`, `work`, `log`, `watch`, `monitor`. Triage forces these into ambiguous bucket regardless of regex hit position. User confirms each.
- **Self-reference in plan docs** — the active plan/work-notes document mentions the rename pair as part of *documenting* the migration. Auto-excluded; never modify.
- **Concurrent sessions** — Edit tool's read-before-write guard catches racing edits. If guard fails, report to user and abort.
- **Word-boundary trap** — `confirm` inside `confirmation` MUST NOT match. All bare-token patterns use `\b`.
- **Slash-token specificity** — `/confirm` should match but not `/confirmation` or `path/confirm`. Use `\B/<old>\b` (non-word-boundary before slash, word-boundary after).
- **Frontmatter trailing newline** — YAML frontmatter description strings can span lines. Patterns must handle multi-line. Use `multiline: true` on the Grep tool.
- **Renames with overlap** — `test` → `test e2e` is a substring expansion. Apply most-specific match first, mark already-edited regions to prevent double-edit.
- **Pattern false negative** — if Phase 6 re-sweep reveals a NEW syntactic form, that's a feature gap. Add the pattern to `context/patterns.md`, re-iterate. Do NOT silently apply.

## What this skill does NOT do

- **Does not perform AST-level renames** — Python class names, C# type names, JS function refactors. Use IDE refactor tools or language-aware refactoring tooling. This skill handles documentation, configuration, and identifier-string renames in text files.
- **Does not rename git branches** — use `git branch -m`. Operates on file content, not git refs.
- **Does not handle framework version migrations** — use dedicated migration tooling. Different concern: behavioral upgrade, not text rename.
- **Does not auto-fix conversation history or memory entries** — past mentions of the old name in conversation/memory are deliberately preserved as historical record. Future renames are the user's responsibility to invoke this skill for.
- **Does not run builds or tests** — hand off to the consuming repository's build/test/verification workflow after the rename completes.
- **Does not perform general dead-reference scanning** — `audit orphans` is STRICTLY pair-driven (post-rename hygiene only). For repo-wide dead-link / dead-reference checks unrelated to a specific rename, use a codebase-audit workflow or documentation link checker if your environment provides one. Charter boundary preserves single responsibility.

## Gotchas

- **NEVER trust a single-pattern grep as "clean."** That was the bug this skill exists to prevent. In the skill-rename incident that motivated the pattern library, token-only grep returned 0 matches across 4 sweep passes; chain prose, comma-lists, numbered rows, and frontmatter forms surfaced one round at a time. Run all patterns or invoke `/rename-references audit`.
- **Ambiguous bucket is mandatory triage, not optional.** English-verb collisions are the highest false-positive vector. If a token is in the blocklist, force into ambiguous regardless of position. Cost of one extra confirmation prompt is far lower than silently mangling prose.
- **Re-sweep until the ACTIONABLE count is 0.** Don't trust Phase 5 ended cleanly without verification. Phase 6 is the gate. "Actionable" is load-bearing: under container-rename mode the bare-token residue is left unrenamed by design and still matches forever, so gating on the RAW count means the loop never terminates.
- **Plan-doc exclusion is mandatory.** The active plan/work-notes document *documents the rename* and contains both old and new names by design. Editing it would break the documentation narrative.
- **Pattern library evolves.** When Phase 6 finds a NEW form, treat as a learning event: extend `context/patterns.md`, add an eval case. Future renames benefit immediately.
- **A file MOVE breaks the moved files' own relative paths — sweep INSIDE the moved set, not just refs TO it.** When `git mv` changes directory depth, relative refs *inside* the moved files (`source ../../lib.sh`, `# shellcheck source=../../../../tests/...`, relative markdown links) silently break — they carry no renamed token, so every token-keyed pattern returns clean while the moved file itself is broken. After any depth-changing move: `grep -nE '\.\./' <moved-files>` + re-run the moved code from its new location (tests, `--help`). Real example: a directory promotion left a `# shellcheck source=` directive pointing four levels up when the new home was two.
- **A rename couples sibling renames — sweep each as its own pair.** Renaming a skill or identifier usually drags coupled siblings that do NOT contain the primary token: dot-form action/mode IDs (`verify.runtime-affecting-paths` — Form 12), internal mode names (`quality` mode), content-file basenames (context/quality.md style paths). A phase-scoped, skill-only grep on the primary token (`/verify`) leaves these EXTERNAL refs — in skill bodies, config files, and other skills' dispatch tables — unverified. A slash-anchored token sweep can return "clean" while `<old>.id` / `<old-mode>` / `<old>.md`-path refs survive elsewhere. Before declaring a rename complete: enumerate the coupled identifiers (Survey phase) and run a sweep per pair.

## Integration with workflow

`/rename-references` is invocable mid-workflow whenever a rename happens — typically during implementation (when the work includes a rename) or as a precursor to final verification, to confirm no stragglers before declaring done.

**Skill chaining:**

| Condition | Action |
|---|---|
| User says "I renamed X to Y" mid-implementation | Invoke `/rename-references <X> to <Y>` to sweep before continuing |
| `git mv` just executed | Invoke `/rename-references audit` to surface stragglers |
| Pre-PR: working tree contains R-status files | Suggest `/rename-references audit` before final verification |
| `/rename-references` finds 0 matches | Proceed to verification (or done if already past it) |
| `/rename-references` finds NEW form not in pattern library | Update `context/patterns.md`, add eval case, re-iterate |
