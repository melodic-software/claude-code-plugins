---
name: tidy
description: "Proactively hunt a rotated lane of the codebase for safe structural improvements (Beck's 15 tidyings + a Fowler subset + prose tidyings), apply scope-budgeted edits, and ship one tight structure-only PR per invocation. Use when: 'tidy', 'tidy up', 'boy scout', 'polish', 'small refactors', 'improve gradually', 'clean up in passing', 'tidying day', 'tidy lane', 'run tidy'. Actions: [<lane>] targeted lane run; [dry-run [<lane>]] plan-only, no edits; [help] print the lane catalog. Skip when: /simplify refines the current diff; batch-simplify processes a diff window; issue-tracker work drains already-filed items — tidy proactively hunts unfiled drift across a glob-scoped lane."
argument-hint: "[<lane> | dry-run [<lane>] | self-update | help]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/tidy/scripts/open-pr-count.sh:*)
shell: bash
metadata:
  workflow-stage: anytime
  summary: Proactively hunt one lane for safe structural tidyings and ship a structure-only PR
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Open chore/tidy-* PRs: !`bash ${CLAUDE_PLUGIN_ROOT}/skills/tidy/scripts/open-pr-count.sh 2>/dev/null | grep -E '^(Open tidy|Throttle)' || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Tidy is the proactive "Boy Scout in passing" loop — step zero of the long-game improvement story. Answers: "What small structural improvements can I safely make to one slice of the codebase today, and ship as one tight PR, without mixing structural and behavioral changes?"

This skill encapsulates the agentic application of three converging ideas:

- **Kent Beck, *Tidy First?* (2024)** — small, named refactorings called "tidyings" (Beck's 15), separated from behavioral changes by commit and by PR. *"Always one or the other, never both at the same time."*
- **Robert C. Martin / Steve Smith — Boy Scout Rule** — leave the campsite cleaner than you found it. Empirically validated against the *Pragmatic Programmer*'s Broken Windows hypothesis: small drift compounds.
- **Adam Tornhill / CodeScene 2026 — agentic refactoring research** — autonomous AI agents introduce defects ~30% more often in unhealthy code. Agents need a higher Code Health bar than humans. Structure-only Boy Scout work is the safest agentic move.

**What tidy is NOT** — read carefully, differentiation matters:

- **Not `/simplify`** (Claude Code's bundled skill) — that takes the conversation's recent diff and tightens it. Tidy hunts a lane independent of recent activity.
- **Not `batch-simplify`** (this plugin's sibling skill) — that processes a time-window or branch diff in waves. Tidy targets a glob-scoped lane and stops when the scope budget is hit.
- **Not issue-tracker work** — tidy never starts from a filed item; it discovers improvements not yet filed, and files overflow as deferred items.
- **Not a docs fact-checker** — tidy improves *structure*, not factual accuracy.

Unique value: **rotated lane discipline + scope budget + structure-only commits + research-driven approach**. Lane rotation drains drift bit-by-bit across the codebase so no area ossifies. Use `/simplify` when refining what you just wrote; use tidy when you want to make tomorrow's reading easier than today's.

## Action Router

Parse `$ARGUMENTS` to determine the action:

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | Infer the most appropriate lane from current branch / recent commits / git status. If the inference is ambiguous, pause and ask the user. Otherwise proceed as if `<lane>` was passed. |
| `<lane>` (from the catalog below) | **Targeted lane run** | Load the lane file, run the full Workflow on that lane's scope. |
| `dry-run [<lane>]` | **Plan + present, no edits** | Run Phases A-D (triage, explore, research, hunt). Present the prioritized findings table and the proposed PR scope. Do NOT make edits. Do NOT branch. Do NOT push. Do NOT file tracker items. The user reviews and decides whether to proceed. |
| `self-update` | **Maintainer lane** | Shorthand for `<lane>=self-update`. Operates on this plugin's own files — valid ONLY in a working-tree checkout of the plugin (marketplace clone or `--plugin-dir`), never an installed copy. Manual-merge always. |
| `help` | **Print this Action Router + lane catalog** | Diagnostic / orientation. |

## Lane catalog

A lane is a discrete glob-scoped slice of the repo, defined in a lane file that specifies scope globs, watch-for tidyings, lane-specific exclusions, verification commands, default Conventional Commits type, and preferred research sources.

**Lane resolution — read both layers, merge per the lane's declared semantics.** A lane named `<lane>` has up to two layers:

1. `${CLAUDE_PROJECT_DIR}/.claude/tidy-lanes/<lane>.md` — the consuming project's own lane definition, if present
2. `${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/<lane>.md` — the bundled generic lane

When the project layer is absent, resolution is the bundled lane alone. When it is present, how the two layers combine is governed by the **project layer's own `## Merge semantics` section** (per the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md)):

- The project layer declares a `## Merge semantics` section → **read both layers and merge per that declaration** (typically: `Scope` and most sections per-section override, watch-for patterns additive). A section absent from the project layer keeps the bundled value; the bundled generic patterns are never frozen out. The bundled `docs-prose` and `shell-tooling` lanes each publish a recommended declaration for their own sections, which a project layer adopts by reference or by restating it; the project layer's declaration is what governs.
- The project layer declares no such section → it resolves **project-only** (the bundled lane is not read). This is the legacy first-match path; lanes still on it are migrated one at a time.

Lane files are project-specific **by design** — the bundled lanes cover surfaces that look the same in most repos, and the bundled templates scaffold the ones that don't. To define a project lane, copy the closest template from `${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/` into `.claude/tidy-lanes/<lane>.md` and fill in the scope globs and watch-for patterns for your stack. The catalog is the union of both locations — list `.claude/tidy-lanes/*.md` (if the directory exists) plus the bundled lanes when printing `help`.

Bundled lanes:

| Lane | File | Covers |
|------|------|--------|
| `shell-tooling` | `lanes/shell-tooling.md` | Shell/PowerShell scripts under the project's tooling directories |
| `docs-prose` | `lanes/docs-prose.md` | Markdown prose: skill bodies, docs |
| `self-update` | `lanes/self-update.md` | This plugin's own files (maintainer checkout only) |

Bundled templates (copy + adapt into `.claude/tidy-lanes/`):

| Universal pattern | Template |
|------|------|
| Framework/library core that downstream code depends on | `templates/dependency-root-lane.template.md` |
| Hosting infrastructure, logging, registration, service defaults | `templates/host-wiring-lane.template.md` |
| User-facing applications + their tests | `templates/apps-lane.template.md` |
| Non-primary-language services / MCP servers / sidecars | `templates/polyglot-services-lane.template.md` |

Read the resolved lane file in full at Phase A entry; do not infer scope from this table.

## Workflow (8 phases)

Run in order. Each phase has one job. Don't skip phases for "small" tidyings — the structure-only-per-PR rule is non-negotiable.

### Phase A — Triage

1. Resolve lane from `$ARGUMENTS` per Action Router. Empty arg → infer from current branch / recent commits / git status; if ambiguous, ask the user.
2. Load the lane per **Lane resolution** above — read the full file(s). When a project lane declares `## Merge semantics`, read **both** the project and bundled layers and merge per that declaration (e.g. project `Scope` replaces bundled globs; project watch-for entries append to the bundled ones); otherwise read the single resolved file. The resolved lane owns scope globs, watch-for list, lane-specific exclusions, verification commands, Conventional Commits type, and preferred research sources.
3. Backlog throttle — if ≥3 open PRs match `chore/tidy-*` (see pre-computed context above), STOP. Surface a one-line note to the user and exit cleanly. Do NOT pile on.
4. Find anchor commit: the most recent merged `chore/tidy-<lane>-` PR for this lane (or `git log --grep` if no merged PRs yet). The anchor establishes the "what's drifted since last sweep" baseline.

### Phase B — Branch

`git checkout -b chore/tidy-<lane>-YYYY-MM-DD origin/<default-branch>`. The date suffix disambiguates daily reruns. **Never** commit tidyings directly on the default branch — a feature-prefixed branch keeps the structure-only PR reviewable and revertable.

### Phase C — Explore + research (mandatory)

Understand before changing. No exceptions for "small" tidyings — workflow discipline is what keeps tidy runs safe.

1. Explore the lane's scope globs: if the `discovery` plugin is installed, invoke `/discovery:explore` on the lane scope; otherwise read 5-10 representative files in the lane to understand current patterns, conventions, and existing tidyings.
2. Research current best practice for the lane's stack: if the `discovery` plugin is installed, invoke `/discovery:research` using the lane file's preferred-source list; otherwise do a focused inline research pass (official docs + the lane's preferred sources) before editing.

### Phase D — Hunt + prioritize + scope-budget enforce

1. Read `reference/tidyings.md` for the full taxonomy (Beck 15 + Fowler 5 + prose tidyings P-1..P-6 = 26 entries).
2. Hunt: walk the lane's scope globs, looking for instances of the lane's watch-for tidyings. For each candidate, classify: tidying type, file, line range, estimated LOC delta, confidence.
3. Build a prioritized findings table.
4. Apply the scope budget (`reference/scope-budget.md`): target ≤200 LOC + ≤8 files; hard cap ≤400 LOC + ≤15 files. Take the highest-priority subset that fits.
5. Overflow → file one work item per deferred candidate using the template in `reference/scope-budget.md`: via `/work-items:track add` when that plugin is installed, else `gh issue create` (or present the list to the user when no tracker is reachable). **In `dry-run` mode, present the overflow list instead — dry-run never files tracker items or causes any other external side effect.**

If the hunt finds zero applicable improvements after thorough exploration: clean exit, NO PR. Do not produce empty-PR churn.

### Phase E — Implement

1. Use the Edit tool, never `sed -i`.
2. **One commit per logical tidying.** Atomic, structure-only. Beck: *"Each commit should fit comfortably in your head, on your screen, and in the team's review pipeline."*
3. `git add <path>` only — never `-A` or `.` (parallel-session WIP can sneak in).
4. Pre-flight every file with `git diff <path>` *before* staging. After staging, use `git diff --cached <path>` to confirm only the tidying went in.
5. Commit messages follow Conventional Commits with the lane's default type (e.g., `refactor:` for code lanes, `docs:` for prose lanes, `chore:` for tooling).

### Phase F — Verify

Tidying is behavior-preserving, so verification must confirm exactly that: run the project's build + tests + linters for the affected ecosystem (use the lane file's verification commands; the consuming project's own CLAUDE.md / rules may name canonical commands). Red branch → fix or abort cleanly. **Never push red.** If a tidying broke a test or build, it was secretly behavioral — back it out and re-classify.

### Phase G — Self-review + simplify

1. Review the full diff yourself (`git diff origin/<default-branch>...HEAD`) hunting for accidental behavior change, scope creep, and convention violations. Drive real findings to zero before push.
2. Run `/simplify` on the touched files (NOT scope creep — only files already edited). Rebuild and re-verify after simplify.

Self-review by the producing context is enough here — a fresh-context verifier is the rule where a verdict is subjective, but tidying is behavior-preserving and Phase F is an objective build/test/lint pass/fail. A change that turns out behavioral fails Phase F and is backed out (Gotchas), never verdict-reviewed into acceptance.

### Phase H — Ship

Never call `git commit` or `gh pr create` directly — Phase E already committed the tidyings, so what's left is PR creation, and that has a canonical gate (issue-linkage resolution, injection-safe body assembly, a pre-create check for a valid closing keyword or explicit opt-out) that a bare `gh pr create` skips entirely.

If the `source-control` plugin is installed, invoke `/pull-request create`. Its stage-and-commit step is a no-op here (tree is already clean from Phase E), so it goes straight to rebase-check, issue-linkage resolution, and gated PR creation. Supply it this PR's title and body content — the canonical flow's body template is fixed to Summary + Test plan (`plugins/source-control/skills/pull-request/reference/create.md` §2.4.1), so give it only those two sections; tidy's own audit-trail content goes in a follow-up comment (below), not the PR body:

Title:

```text
<lane-default-type>(<lane-area>): <what was tidied>
```

Examples:

- `refactor(core): rename result helpers for reading order`
- `docs(skills): repair stale cross-references`
- `chore(tools): apply shellcheck/shfmt drift across tools/*.sh`

Body sections:

- **Summary** — 1-3 bullets: which lane, which tidyings, anchor commit.
- **Test plan** — verification commands run + results.

`/pull-request create` reports the created `<pr_number>` back on completion (its own §2.6 "Report and stop"). Immediately post one follow-up comment on that PR with `tidy`'s own audit trail — content the canonical body template has no slot for:

```bash
gh pr comment <pr_number> --body-file - <<'EOF'
## Tidyings applied

<table: tidying type → file → line range → LOC delta>

## Deferred items

<links to filed issue numbers, if the scope budget capped the run>
EOF
```

The comment itself is never optional when a PR was created — "Tidyings applied" is never empty at that point (Phase D's empty-PR-avoidance rule means no PR gets created when there's nothing to tidy), and it's the only place this content appears now that the canonical body template has no slot for it. Only the "Deferred items" subsection is conditional: omit it when nothing was deferred, and never post it as an empty table.

If `source-control` isn't installed, apply the same invariants inline: resolve issue-linkage before writing a closing keyword (`Closes #N` only after confirming issue #N exists in this repo — e.g. `gh issue view N`; otherwise state `No related issue: <reason>`), assemble the body via a quoted heredoc (`<<'EOF'`) plus parameter-expansion concat rather than an unquoted `<<EOF` (which would execute any `$(...)` embedded in prompt-derived text), and refuse to call `gh pr create` until the assembled body contains a valid closing keyword or the opt-out marker. In this fallback path only, the Tidyings-applied/Deferred-items sections stay in the PR body itself (there is no canonical gate to conflict with).

Then monitor checks (`gh pr checks <n> --watch`) until green. Address review-bot findings: verify each against the current code — fix the correct ones, rebut the incorrect ones with evidence. **Manual merge by a human** — this skill does NOT auto-merge.

## Global HARD/SOFT EXCLUSIONS

Three exclusion tiers gate every lane. The full lists live in `reference/exclusions.md` — read it at the start of every run; the summary below is orientation only.

1. **GLOBAL HARD EXCLUSIONS** — paths NEVER touched, regardless of lane: agent/CI/hook configuration surfaces (`.claude/settings*`, `.claude/agents/**`, `.claude/hooks/**`, `.claude/rules/**`, `.github/workflows/**`, git-hook manager config, `.mcp.json`, lint configs like `.editorconfig`) plus every path the consuming project's own rules declare protected (build/analyzer infrastructure, solution/workspace files, architecture-test suites, bootstrap scripts are typical).
2. **GLOBAL SOFT EXCLUSIONS** — areas where edits are technically allowed but an autonomous run cannot verify safely (browser-rendered UI, interactive auth flows, DB migrations against real instances, IDE-only flows, and any areas the consuming project marks as unverifiable). Routed to the deferred-items list during Phase D unless an interactive user explicitly overrides.
3. **SELF-UPDATE EXTRA HARD** — additional restrictions when `<lane>=self-update`. Protects the skill's contract surface: frontmatter, the Action Router / Workflow / Lane-catalog sections, lane-file `## Scope` / `## Watch-for patterns` / `## Lane-specific extra exclusions` blocks, and `reference/scope-budget.md` numeric values (research-derived).

### Behavioral exclusions (cross-cutting concepts, NOT in the path lists)

Path lists above are glob-matchable. Behavioral concerns are agent-judgment guards — apply regardless of which file path the edit targets:

- **DB migrations against real instances** — touching migration code is safe only against an ephemeral test DB
- **Breaking API changes** — any change to public symbols consumers depend on
- **HTTP route signature changes** — endpoint URL, method, request/response DTO shapes
- **MCP tool schema changes** — tool name, input schema, output schema, behavior
- **Branch-protection / security-workflow rule changes** — out of scope for any lane
- **Work-tracking exclusions** — items another agent has claimed, items with an open PR linked, items labeled blocked/deferred

If a candidate tidying would alter any of the above behaviors regardless of which path it edits, treat it as behavioral and file an issue instead.

**Read `reference/exclusions.md` at the start of every run.** Do not trust memory of these lists across sessions.

**Enforcement across phases:** Phase A seeds path-validation from the HARD list. Phase D classifies candidates against HARD (drop) and SOFT (defer). Phase E validates every Edit / Write target path against the HARD list. The self-update lane additionally applies the EXTRA HARD list during Phases D and E.

## Deferred items contract

Full template: [reference/scope-budget.md](reference/scope-budget.md). Summary:

- Every item the scope budget cuts becomes one filed work item.
- Title format: `<conv-type>(<area>): <what>`.
- Body must include: rationale, file list, scope estimate (LOC + files), and a link to the parent tidy PR.
- Phase H's "Deferred items" follow-up comment (or, when `source-control` isn't installed, the PR body's own "Deferred items" section) links every filed item by number.

## Gotchas

- **Beck #4 (New Interface, Old Implementation) is context-dependent.** Safe ONLY when the new interface has zero existing consumers. If consumers exist, treat as behavioral and skip. Don't trust the "structural" label blindly.
- **A tidying that breaks a test was secretly behavioral.** If verification goes red after a "structural" change, back it out. It altered observable behavior — that's a feature/bugfix belonging in a different PR with proper test coverage.
- **Don't tidy your way around a banned/deprecated API.** If the lane scope contains call sites of an API the project bans, migrating them is behavioral. File an issue, defer.
- **Self-update's safety relies on the EXTRA HARD list.** Read `reference/exclusions.md` SELF-UPDATE EXTRA HARD in full at the start of every self-update run.
- **Empty-PR avoidance.** Zero applicable improvements → clean exit + one-line note. NO empty PR.
- **Backlog throttle is a STOP signal, not a warning.** ≥3 open `chore/tidy-*` PRs means reviews are backed up. Stop until the humans catch up — don't "just queue one more."
- **`git add <path>` not `-A`.** Always `git diff <path>` before staging — even on a tidy branch, WIP from a parallel session can sneak in.
- **Explore + research are non-negotiable** even for one-line tidyings — rework from skipped research costs more than the research itself.
