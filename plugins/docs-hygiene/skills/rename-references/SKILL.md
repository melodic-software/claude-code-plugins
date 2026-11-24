---
description: "Sweep stale references after a rename, including forms token-only grep misses (slash-tokens, paths, chain prose, table rows, frontmatter globs). Use when: 'rename X to Y', 'I renamed X', 'audit rename', 'find stale refs', 'check for stragglers', 'after git mv', 'sweep references', 'rename impact preview', 'find half-renamed state', 'broken refs after rename', 'pre-PR rename check'. A whole tree against a casing rule is docs-naming:audit-file-names, if enabled."
argument-hint: "[audit|preview|blocklist] [<old> [to <new>]] [--container|--identifier…] [--repo <repo> ...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Sweep stale references after renames, including forms grep misses
---

**Arguments.** `[audit|preview|blocklist] [<old> [to <new>]] [--container|--identifier…] [--repo <repo> ...]`. Full form: [audit [blast|half-rename|orphans]|preview|blocklist] [<old> [to <new>]] [--include-historical|--include-memory|--include-plan-docs|--include-bare-token|--container|--identifier] [--repo <repo> ...|--repos-from <file|->|--owner <owner>|--fleet] [--skip <entry> ...] (e.g., /rename-references audit, /rename-references audit blast /verify to /verify-changes, /rename-references audit half-rename /a to /b, /rename-references audit orphans /a to /b, /rename-references blocklist)

## Repository context. Gather first

<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->
Run each command below as its own Bash call, all sent together in one message ([worktree isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)).
Keep any bound in the command's own pipe ([output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
<!-- END GENERATED: gather-block -->

- Working tree status (empty = clean), `git status --porcelain | head -20`
- Rename pairs (git), unstaged, `git diff --name-status -M HEAD | grep '^R' | head -15`
- Rename pairs (git), staged, `git diff --cached --name-status -M | grep '^R' | head -15`
- Current branch, `git branch --show-current`

## Purpose

After renaming a skill, file, or identifier, references survive in 7+ syntactic forms. Token-only grep (`/old`) catches the obvious ones; the rest hide in chain prose (`→ old →`), comma-lists (`Test, Old, Retro`), numbered table rows (`| 7. Old |`), frontmatter chain strings (`description: "...→ old → retro process."`), frontmatter globs (`{a,b,old,c}`), cross-skill mode references, and content-file paths (context/old.md style).

This skill makes "find every reference" one invocation instead of 4 manual sweep passes: it runs the full pattern library, triages matches into 3 buckets, and surfaces ambiguity (English-verb collisions like `confirm`/`test`/`review`) for user confirmation rather than auto-applying.

## Adapting to your environment

The pattern library, triage classifier, and audit modes need only git and the Grep tool. An adjacent capability named in prose (a verification workflow, an issue tracker, a codebase-audit routine) is optional: invoke it if present, otherwise proceed without. Consumer conventions (work-notes locations, commit policy, naming rules) come from the consuming repository's CLAUDE.md and rules; read them, never assume them.

## Action router

Parse `$ARGUMENTS` first token to determine action. Subsequent tokens are the rename pair (with `to`/`→`/`->`/`into` separator) or single token for reverse-mode.

| Argument shape | Action | Read |
|---|---|---|
| *(empty)* | **Smart default** | inline below. Detect rename pair from conversation/git/staged |
| `audit` | **Audit** (read-only sweep. Alias for `audit blast`) | [context/audit.md](context/audit.md) + [audit-modes.md](context/audit-modes.md) |
| `audit <old>` or `audit <old> to <new>` | **Audit** with explicit pair | [context/audit.md](context/audit.md) |
| `audit blast [<old> [to <new>]]` | **Audit Blast**. Pre-rename impact (counts + per-file + bucket distribution; inline-only) | [audit-modes.md](context/audit-modes.md) |
| `audit half-rename <old> to <new>` | **Audit Half-Rename**. Files mentioning both old and new (incomplete-rename hygiene) | [audit-modes.md](context/audit-modes.md) |
| `audit orphans <old> to <new>` | **Audit Orphans**. Refs at old name or vanished path after rename (requires pair) | [audit-modes.md](context/audit-modes.md) |
| `<old> to <new>` | **Apply** full rename | [context/apply.md](context/apply.md) |
| `preview <old> to <new>` | **Preview** dry-run | [context/apply.md](context/apply.md) (skip Edit phase) |
| `<old>` (single token, no separator) | **Reverse**. Find refs, ask what to replace with | [context/audit.md](context/audit.md) |
| `blocklist` | **Print English-verb blocklist** (read-only introspection of triage-bucket safety mechanism) | inline below |

**Every sweep runs off the pattern library**, the full form registry in [context/patterns.md](context/patterns.md); read it before any sweep. A sweep runs through the Grep tool with the patterns.md regexes over the tracked tree, covering every form the action sweeps (every form in patterns.md for apply, preview, audit and Blast; the forms [Audit Orphans](context/audit-modes.md#audit-orphans) names for Orphans). One Grep may combine forms in an alternation as long as every form's regex is in it; never let one token grep stand in for them. Attribute each hit to its form, and a form whose regex no call ran is a form the sweep missed. Reading files one by one is not a sweep; use Read only to confirm a Grep hit in its surrounding context before classifying or editing it. Triage logic is in [context/triage.md](context/triage.md). Audit sub-mode detail (Blast / Half-rename / Orphans) is in [context/audit-modes.md](context/audit-modes.md).

## Override flags (audit modes)

Six flags. Four widen the sweep; two override the rename-mode resolution. Defaults preserve safety (rename-documenting plan docs / frozen historical notes / memory entries excluded). Long-form only, position-agnostic.

| Flag | Effect | Apply mode? |
|---|---|---|
| `--include-historical` | Sweep archived/completed work notes and frozen records of past work | OK |
| `--include-memory` | Sweep Claude Code auto-memory files and `MEMORY.md` indices in the auto-memory directory (resolution: [Auto-memory location](#auto-memory-location)) | OK |
| `--include-plan-docs` | Sweep the active plan/work-notes documents that document this rename | **audit-mode only**, apply mode rejects with explicit error (the plan doc documents the rename, both names appear by design) |
| `--include-bare-token` | Surface the bare-token residue that container-rename mode suppresses ([patterns.md](context/patterns.md) "Phase 0b"). Always **Ambiguous**, never Certain. Not applicable to `audit orphans`, which sweeps no bare-token form | **audit-mode only** |
| `--container` | Force container-rename mode, skipping the evidence ladder ([patterns.md](context/patterns.md) "Phase 0b") | OK |
| `--identifier` | Force identifier-rename mode | OK |

Multiple flags compose. Unknown flags raise an error. Detail in [audit-modes.md](context/audit-modes.md) "Override flags" section.

**Several repositories.** A target form (`--repo <repo>` and the others) is accepted by every action except `blocklist`, and sweeps the one rename pair in each repository, per [`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](../../reference/target-scope.md) and [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md) "Several repositories": one subagent per repository runs Phases 2-3, the Grep sweep with its path set to that repository's root and the triage, and hits are reported per repository. The pair comes from the arguments, or from the Smart default run in the session's own repository. The main session runs Phase 4 over the merged report, so every confirmation is asked there. Apply edits the session's own repository in place, as without a target form, and each other repository in its own worktree with its own pull request; Phase 6's re-sweep runs per repository.

### Auto-memory location

Memory exclusion and `--include-memory` act on the auto-memory directory the session actually uses.
Settings and environment can move it away from the default under `~/.claude/projects/`, so resolve
the configured location before sweeping or excluding, and fall back to the default only when nothing
overrides it.

- **Pointer**: <https://code.claude.com/docs/en/memory#storage-location>

## Blocklist action

`/docs-hygiene:rename-references blocklist` prints the English-verb blocklist literal from [context/triage.md](context/triage.md). Read-only: no edits, no sweeps. To extend, edit `triage.md` directly.

## Smart default (no arguments)

Detect rename pairs in this priority order:

1. **Explicit args** (highest precedence, never overridden)
2. **Recent conversation**. Scan last 20 turns for prose like "I renamed X to Y", "rename X → Y", "git mv X Y", or assistant edits replacing identifier X with Y across multiple files
3. **Git rename detection**. `git diff --name-status -M HEAD` and `git diff --cached --name-status -M`; `R<score>` lines map old path → new path
4. **Paired `D <path>` + `?? <similar-path>`** in `git status --porcelain` (heuristic. Levenshtein-similar basenames within same dir)

If multiple candidates surface, present via `AskUserQuestion`. User picks which pair to audit.

If zero candidates: report "No rename detected in conversation or git state. Provide `/docs-hygiene:rename-references <old> to <new>` or `/docs-hygiene:rename-references audit <old>` to invoke explicitly."

## Natural-language parser

The argument string after the action keyword can be:

| Form | Example | Parses to |
|---|---|---|
| `<old> to <new>` | `/verify to /verify-changes` | old=`/verify`, new=`/verify-changes` |
| `<old> to <new>` (mode) | `/verify to /verify-changes outcome` | old=`/verify outcome`, new=`/verify-changes outcome` |
| `<old> → <new>` | `test live → test e2e` | old=`test live`, new=`test e2e` |
| `<old> -> <new>` | `foo -> bar` | old=`foo`, new=`bar` |
| `<old> into <new>` | `legacy into modern` | old=`legacy`, new=`modern` |
| `<path/old.md> to <path/new.md>` | `confirm/SKILL.md to verify/SKILL.md` | path rename. Skill applies extra path-form patterns |

Multi-word old/new is fine. Separator is the only delimiter. Quote characters (`"foo bar"`) optional. Old/new taken verbatim. Leading slashes preserved (`/confirm` stays `/confirm`, not `confirm`).

## Workflow phases (apply mode)

1. **Detect**. Gather rename pair (args / conversation / git per Smart default)
2. **Survey**. Run all patterns from `context/patterns.md` in parallel as Grep tool calls against tracked text files; aggregate per-file hit counts. For a skill/identifier rename, first enumerate coupled-sibling renames (dot-form behavior point-IDs, internal mode names, content-file basenames that changed in lockstep) and queue each as its own rename pair. They carry no primary token, so the primary sweep never reaches them (see Gotchas "coupled-rename")
3. **Triage**. Classify each match into 3 buckets per `context/triage.md`:
   - **Certain**. Slash-token, path, frontmatter glob (high precision, auto-apply candidate)
   - **Chain-context**. Preceded/followed by other known skill names; numbered table rows; chain prose with multiple skill tokens
   - **Ambiguous**. Bare-token matches where token is in English-verb blocklist (`confirm`/`test`/`review`/`fix`/`clean`/`build`/`lint`/`verify`/`plan`/etc.)
4. **Confirm**. Present the bucket-count report, gate proceed/abort via `AskUserQuestion`, then per bucket:
   - Certain → no per-bucket question: auto-apply; the report gives the count, 1-2 examples and how to review one by one instead
   - Chain-context → "review N matches one-by-one?". Yes/skip-bucket/auto-apply-all
   - Ambiguous → per-match yes/no with surrounding context
5. **Apply**, Edit each accepted match. Idempotent, running twice is safe.
6. **Re-sweep**. Re-run Phase 2; exit when the actionable count is 0 (the survey after `context/patterns.md` "Phase 0" span-precedence and "Phase 0b" container-rename mode, minus the matches the user confirmed skipping in Phase 4: neither the mode's residue nor a deliberate skip ever counts, or the loop cannot terminate). If non-zero, new form not in pattern library. Report to user, add to `context/patterns.md`, re-iterate.
7. **Hand off**. Suggest running the consuming repository's verification workflow (build + test + lint) to confirm no semantic regression in the rename target.

Audit mode runs phases 1-3 only and reports, no Edit calls. Preview mode runs 1-4 and reports planned edits, no Edit.

## Auto-exclusions

Paths skipped from sweeps automatically:

- **Rename-documenting plan/work-notes documents**: an active plan file, migration notes, or changelog entry drafted for this rename names both old and new by design. Identify these from conversation context and the consuming repository's work-notes conventions (its CLAUDE.md / rules). Skipping prevents self-reference loops.
- **Archived/historical work notes**. Completed plan documents and frozen records of past work, released changelog entries included, are historical record, not stale references: unless `--include-historical` is passed, report them only as "Kept as history" ([triage.md](context/triage.md) "Frozen historical records"), never as a choice for the user.
- `.git/`, `node_modules/`, `bin/`, `obj/`, `.venv/`, `dist/`, `build/`
- Claude Code auto-memory files ([Auto-memory location](#auto-memory-location)) describing past renames

## Composition

| Stage | How | Why |
|---|---|---|
| Pre-rename impact analysis | `/docs-hygiene:rename-references audit <old>` | Read-only sweep, see blast radius before changing anything |
| Rename execution | `/docs-hygiene:rename-references <old> to <new>` | Sweep → triage → edit → re-sweep |
| Post-rename verification | the consuming repository's build/test/lint workflow | Confirm no semantic regression |
| Cleanup near rename sites | a separate simplification/refactor pass | Opportunistic refactor (separate concern) |

## Edge cases

- **English-verb collision**. Tokens like `confirm`, `test`, `review`, `clean`, `fix`, `build`, `lint`, `plan`, `run`, `view`, `start`, `stop`, `merge`, `split`, `sort`, `filter`, `group`, `head`, `body`, `link`, `list`, `work`, `log`, `watch`, `monitor`. Triage forces these into ambiguous bucket regardless of regex hit position. User confirms each.
- **Concurrent sessions**. If an Edit call fails, report to the user and abort. **Pointer**: when judging what the Edit tool checks before an edit applies, fetch [Edit tool behavior](https://code.claude.com/docs/en/tools-reference#edit-tool-behavior) live.
- **Word-boundary trap**. `confirm` inside `confirmation` must not match. All bare-token patterns use `\b`.
- **Slash-token specificity**. `/confirm` should match but not `/confirmation`, `/confirm-changes`, or `path/confirm`. Use `\B/<old>([^\w-]|$)` (non-word-boundary before the slash; a consumed terminator after that excludes a hyphen). A trailing `\b` is not enough: it treats a hyphen as a boundary, so it matches inside kebab-case sibling commands, and Form 1 is Certain, so that auto-applies. The consumed character is not part of the reference.
- **Frontmatter trailing newline**. YAML frontmatter description strings can span lines. Patterns must handle multi-line. Use `multiline: true` on the Grep tool.
- **Renames with overlap**. `test` → `test e2e` is a substring expansion. Apply most-specific match first, mark already-edited regions to prevent double-edit.

## Glossary-driven renames

When the pair comes from a domain glossary change (a term renamed, a word moved to the entry's
`Avoid:` line, or a verb moved into the parentheses of an entity's `Actions:` line, usually handed
over by `/domain-driven-design:ubiquitous-language` (if enabled)), code names
follow the glossary too, and the sweep runs as its own reviewed change, never folded into the
glossary edit. When the `domain-driven-design` plugin is enabled, the
sweep also matches the term inside identifiers the way that skill's glossary contract counts a
term ("Counting a term"), so `addLearner` is found for `learner`; when it is not, the report says the identifier-part pass
did not run. Ordinary renames keep the `\b` anchor ("Word-boundary trap"). The report groups hits
by layer:

- **Code and identifiers**: renamed in one reviewed change. Occurrences in config, comments and
  string literals are swept here like any other form; declarations of types, functions, variables
  and enum members, and the call sites a symbol rename reaches, are listed for a language-aware
  refactor tool, per "What this skill does NOT do".
- **Docs and ADR text**: updated like any other prose. ADR file names and numbers stay unchanged,
  so a hit in an ADR's file name, or in a path or link naming that file, is kept, never edited.
- **User-facing copy and error messages** (UI strings, emails, notifications, error text): report
  only. Each hit is listed with `file:line` and the glossary term; none is edited, because users'
  words may rightly differ from the model's. A hit matching the entry's `Shown to users as:`
  wording is intended, not drift.
- **Stored values and migrations** (an enum value or string persisted in a database, a migration,
  seed or fixture, a message schema, a public API field): never edited. The report names each as a
  decision, a phased migration or a mapping that keeps the stored name, recorded as an ADR through
  `/architecture:adr` (if enabled).

## What this skill does NOT do

- **Does not perform AST-level renames** (Python class names, C# type names, JS function refactors). Use IDE or language-aware refactoring tools; a glossary-driven rename lists them for that tool ([Glossary-driven renames](#glossary-driven-renames)). This skill handles documentation, configuration, and identifier-string renames in text files.
- **Does not rename git branches**. Use `git branch -m`.
- **Does not handle framework version migrations**. Use dedicated migration tooling: that is a behavioral upgrade, not a text rename.
- **Does not auto-fix conversation history or memory entries**. Past mentions of the old name there are preserved as historical record. Future renames are the user's responsibility to invoke this skill for.
- **Does not audit a whole tree against a casing rule**. If `docs-naming` is enabled, `/docs-naming:audit-file-names` (if enabled) does. Without it, list the tree with `git ls-files`, compare each name against the rule by hand, and run `audit` here once per pair you decide to rename.
- **Does not run builds or tests**. Hand off to the consuming repository's build/test/verification workflow after the rename completes.
- **Does not perform general dead-reference scanning**. `audit orphans` is strictly pair-driven (post-rename hygiene only). For repo-wide dead-link / dead-reference checks unrelated to a specific rename, use a codebase-audit workflow or documentation link checker if your environment provides one.

## Next

- A whole tree to measure against a casing rule, not one pair swept after a rename:
  `/docs-naming:audit-file-names`.
- The sweep edited code or config and the build must still pass: `/toolchain:check`.

## Related

- Curate domain glossary terms behind a rename: /domain-driven-design:ubiquitous-language.
- Record ADR for persisted stored names left unchanged: /architecture:adr.
- Sweep a changed config value rather than an identifier: /coupling:reduce.

## Gotchas

- **A single-pattern grep is never evidence of a clean sweep.** Token-only grep reaches Forms 1 and
  2 and nothing else; chain prose, comma-lists, numbered rows, and frontmatter forms each need their
  own pattern, and each surfaces only when that pattern runs. Run the whole library, or invoke
  `/docs-hygiene:rename-references audit`.
- **Ambiguous bucket is mandatory triage, not optional.** English-verb collisions are the highest false-positive vector. If a token is in the blocklist, force into ambiguous regardless of position: one extra confirmation prompt costs far less than silently mangling prose.
- **Re-sweep until the actionable count is 0.** Don't trust Phase 5 ended cleanly; Phase 6 is the gate. Gating on the raw count, or on residue alone, means the loop never terminates (see Workflow phase 6). Skips are keyed by occurrence span, remapped as Phase 5's edits shift later columns on the same line, and reported separately from residue in the hand-off ([context/apply.md](context/apply.md) Phase 6).
- **Plan-doc exclusion is mandatory.** The active plan/work-notes document contains both old and new names by design; editing it would break the documentation narrative.
- **Pattern library evolves.** When Phase 6 finds a new form, extend `context/patterns.md`, add an eval case, and re-iterate. Do not silently apply.
- **A file move breaks the moved files' own relative paths. Sweep inside the moved set, not just refs to it.** When `git mv` changes directory depth, relative refs *inside* the moved files (`source ../../lib.sh`, `# shellcheck source=../../../../tests/...`, relative markdown links) silently break. They carry no renamed token, so every token-keyed pattern returns clean while the moved file itself is broken. After any depth-changing move: run the Grep tool with pattern `\.\./` over the moved files, then re-run the moved code from its new location (tests, `--help`).
- **A rename couples sibling renames. That is the coupled-rename case. Sweep each as its own pair.** Renaming a skill or identifier usually drags coupled siblings that do not contain the primary token: dot-form action/mode IDs (`verify.runtime-affecting-paths`, Form 12), internal mode names (`quality` mode), content-file basenames (context/quality.md style paths). A phase-scoped, skill-only grep on the primary token (`/verify`) leaves these external refs, in skill bodies, config files, and other skills' dispatch tables, unverified. A slash-anchored token sweep can return "clean" while `<old>.id` / `<old-mode>` / `<old>.md`-path refs survive elsewhere. Before declaring a rename complete: enumerate the coupled identifiers (Survey phase) and run a sweep per pair.

## Integration with workflow

Invoke `/docs-hygiene:rename-references` whenever a rename happens: during implementation, or before final verification to confirm no stragglers.

**Skill chaining:**

| Condition | Action |
|---|---|
| User says "I renamed X to Y" mid-implementation | Invoke `/docs-hygiene:rename-references <X> to <Y>` to sweep before continuing |
| `git mv` just executed | Invoke `/docs-hygiene:rename-references audit` to surface stragglers |
| Pre-PR: working tree contains R-status files | Suggest `/docs-hygiene:rename-references audit` before final verification |
| `/docs-hygiene:rename-references` finds 0 matches | Proceed to verification (or done if already past it) |
| `/docs-hygiene:rename-references` finds new form not in pattern library | Update `context/patterns.md`, add eval case, re-iterate |
