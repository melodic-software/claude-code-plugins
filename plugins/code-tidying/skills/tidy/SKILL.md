---
description: "When the bundled simplify skill resolves in this session, prefer it for the current diff; this skill for proactive lane hunts. Hunts one rotated lane for Beck tidyings and ships one structure-only PR. Use when: 'tidy', 'tidy up', 'boy scout', 'polish', 'small refactors', 'improve gradually', 'clean up in passing', 'tidying day', 'tidy lane', 'run tidy'. Skip when /simplify refines the current diff; batch-simplify processes a diff window."
argument-hint: "[<lane>|<glob>...|dry-run [<lane>|<glob>...]|self-update|help] [override] [in-place[=commit]]"
disable-model-invocation: false
user-invocable: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/open-pr-count.sh:*)", "Bash(grep:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Proactively hunt one lane for safe structural tidyings and ship a structure-only PR
---

## Repository context. Gather first

Collect each with its own Bash call, never combined, and not as pre-compute lines ([gather-block record](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md), "The pre-compute block runs as one shell invocation"):

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`
- Working tree status (empty = clean), `git status --porcelain | head -20`

The pipe is the bound and belongs in the command: the Bash tool returns a command's complete output before any read-time cap applies. Treat a failure (not a repository, git unavailable) as an unknown value and carry on.

## Pre-computed context

Open chore/tidy-* PRs: !`${CLAUDE_SKILL_DIR}/scripts/open-pr-count.sh 2>/dev/null | { grep -E '^(Open tidy|Throttle)' || echo "unknown"; }; :`

## Variables

Arguments: `$ARGUMENTS`

HARD path exclusions: `${user_config.hard_exclusions}` (unexpanded, empty, or any value outside `enforce` and `advisory` means `enforce`).

## Purpose

Tidy is the proactive Boy Scout loop: what small structural improvements can one slice of the codebase safely take today, shipped as one tight PR that never mixes structural and behavioral change? It applies Kent Beck's *Tidy First?* tidyings, separated from behavioral changes by commit and by PR (*"Always one or the other, never both at the same time."*), under the Boy Scout Rule, and keeps to structure-only work because autonomous agents introduce defects measurably more often in unhealthy code (Tornhill / CodeScene). Its value is rotated lane discipline, a scope budget, structure-only commits, and research before editing.

**Not**: `/simplify`, which tightens the conversation's recent diff, while tidy hunts a lane independent of recent activity; `batch-simplify`, which sweeps a time window, a branch, or the repository in waves (on docs it owns factual staleness across the whole doc set in one pass, while tidy's `docs-prose` lane owns incremental structural prose work under a scope budget); issue-tracker work, since tidy never starts from a filed item and files its overflow as deferred items; a docs fact-checker, since tidy improves structure, not factual accuracy.

## Action Router

Parse `$ARGUMENTS` to determine the action:

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | Infer the most appropriate lane from current branch / recent commits / git status. If the inference is ambiguous, pause and ask the user. Otherwise proceed as if `<lane>` was passed. |
| `<lane>` (from the catalog below) | **Targeted lane run** | Load the lane file, run the full Workflow on that lane's scope. |
| `<glob>...` | **Ad hoc scope** | No lane covers the files. Run the full Workflow on those globs per **Ad hoc scope when no lane fits** below. Combines with `dry-run`. |
| `dry-run [<lane>]` | **Plan + present, no edits** | Run Phases A-D (triage, explore, research, hunt). Present the prioritized findings table and the proposed PR scope. No edits, no branch, no push, no tracker items. The user reviews and decides whether to proceed. |
| `self-update` | **Maintainer lane** | Shorthand for `<lane>=self-update`. Operates on this plugin's own files. Valid ONLY in a working-tree checkout of the plugin (marketplace clone or `--plugin-dir`), never an installed copy. Manual-merge always. |
| `help` | **Print this Action Router + lane catalog** | Diagnostic / orientation. |
| `override` (flag, combines with any row above) | **Lift the GLOBAL HARD path list for this run, behind an enumeration gate** | The user wants this lane's tidyings to reach a path the HARD list would otherwise drop (agent config, a CI workflow, lint config). Strip the token before reading the rest of `$ARGUMENTS`; match it whole, never as a substring, and treat `./override` as a path. Because a lane is a glob set rather than a named file, Phase D enumerates the specific HARD paths it intends to touch and takes a go-ahead on that list before Phase E edits any of them; non-interactive, the run reports the list and proceeds without those edits (`reference/exclusions.md` section 4). `dry-run override` produces the enumeration alone. Path entries only: the behavioral guards, the work-tracking entries, SELF-UPDATE EXTRA HARD, and the override machinery itself hold regardless. Every lifted path is named in Phase H's report with the channel that lifted it. |
| `in-place` or `in-place=commit` (flag, combines with the smart default, `<lane>`, and `override`) | **Run on the current branch, no branch, no PR** | A caller already holds the branch and PR (a repo-sweep playbook, a feature branch). Strip the token before reading the rest of `$ARGUMENTS`, matched whole like `override`. Phase B stays on the current branch and refuses the default branch; Phase E stages tidyings without committing; Phase H opens no PR and posts no comment, and prints its report to the user instead. `in-place` leaves the changes staged; `in-place=commit` makes one commit of them. The backlog throttle does not apply; every other gate (exclusions, scope budget, verification, self-review) still runs, measured on the staged diff. |

## Lane catalog

A lane is a glob-scoped slice of the repo, defined in a lane file that specifies scope globs, watch-for tidyings, lane-specific exclusions, verification commands, default Conventional Commits type, and preferred research sources.

**Lane resolution.** A lane named `<lane>` has up to two layers:

1. `${CLAUDE_PROJECT_DIR}/.claude/tidy-lanes/<lane>.md`, the consuming project's own lane definition, if present
2. `${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/<lane>.md`, the bundled generic lane

With no project layer, the bundled lane resolves alone. With one, the **project layer's own `## Merge semantics` section** governs (per the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md)):

- Declared → **read both layers and merge per that declaration** (typically `Scope` and most sections override per section, watch-for patterns additive). A section absent from the project layer keeps the bundled value. The bundled `docs-prose` and `shell-tooling` lanes each publish a recommended declaration a project layer adopts by reference or restates; the project layer's declaration governs.
- Not declared → it resolves **project-only** (the bundled lane is not read).

Bundled lanes cover surfaces that look the same in most repos; templates scaffold the ones that do not. To define a project lane, copy the closest template from `${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/` into `.claude/tidy-lanes/<lane>.md` and fill in the scope globs and watch-for patterns. The catalog is the union of both locations: list `.claude/tidy-lanes/*.md` (if the directory exists) plus the bundled lanes when printing `help`.

**Declared deviation: no user-global or `*.local.*` overlay.** Unlike the config-cascade contract, this surface resolves only the team layer (`.claude/tidy-lanes/<lane>.md`) over the bundled lane, because lane globs, verification commands, and watch-for patterns are anchored to this repo's layout, CI, and stack, and the bundled lane is already the portable baseline. Personal variation is limited to lane names the team does not track: keep an uncommitted `.claude/tidy-lanes/<lane>.md` (never added to the index), not a `*.local.*` sibling, so rotation and catalog discovery stay on one filename per lane. Gitignoring a path the team already tracks does not make it personal; setup documents that escape hatch and its limits. Merge granularity within the team+bundled pair is unchanged.

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

### Ad hoc scope when no lane fits

When no bundled or project lane covers the target files (for example a lone `.github/scripts/*.mjs` tree tested with `node --test`), pass globs in place of a lane name: `dry-run <glob>...` to plan, `<glob>...` to run. An argument that names no catalog lane and contains `/` or a glob character is ad hoc scope. The run then:

- takes its scope from those globs, still filtered by the global exclusions below;
- borrows the watch-for list, the lane-specific extra exclusions, and the Conventional Commits type from the closest template (`templates/polyglot-services-lane.template.md` for source code, the `docs-prose` lane for markdown), filling each template `<placeholder>` from the scoped files or dropping just that placeholder's clause when nothing in scope fills it;
- takes verification from the repository's documented test command;
- names its branch `chore/tidy-adhoc-<slug>-YYYY-MM-DD`, where `<slug>` is the first glob's literal directory prefix in kebab case (`github-scripts` for `.github/scripts/*.mjs`), or `root` when the glob has no directory;
- skips the anchor-commit lookup and hunts the whole scope, since no earlier sweep is known to cover the same globs;
- writes no `.claude/tidy-lanes/` file, so Phase H's Summary names the globs in place of the lane and `none (ad hoc)` in place of the anchor commit.

## Workflow (8 phases)

Run in order. Each phase has one job, and every phase runs whatever the tidying's size.

### Phase A. Triage

1. Resolve the lane from `$ARGUMENTS` per the Action Router.
2. Load the lane per **Lane resolution** and read the full file(s), merging both layers when the project lane declares `## Merge semantics`. The resolved lane owns scope globs, watch-for list, lane-specific exclusions, verification commands, Conventional Commits type, and preferred research sources.
3. Resolve the HARD-path override channels per `reference/exclusions.md` section 4 (the `override` argument, `.claude/code-tidying/exclusion-overrides.md`, then `hard_exclusions`) and write down the lifted set with the channel that lifted each entry. Empty is the normal answer.
4. Backlog throttle (skipped under `in-place`): if ≥3 open PRs match `chore/tidy-*` (pre-computed context above), STOP, surface a one-line note, and exit cleanly. It is a stop signal, not a warning: reviews are backed up, so do not queue one more.
5. Find the anchor commit: the most recent merged `chore/tidy-<lane>-` PR for this lane (or `git log --grep` if none merged yet), the "what has drifted since the last sweep" baseline.

### Phase B. Branch

`git checkout -b chore/tidy-<lane>-YYYY-MM-DD origin/<default-branch>`. The date suffix disambiguates daily reruns. **Never** commit tidyings directly on the default branch; a feature-prefixed branch keeps the structure-only PR reviewable and revertable.

**`in-place`:** create no branch; stay on the current one. If it is the default branch, or the index already holds staged changes, stop and tell the user: the staged set this run hands back (or commits under `in-place=commit`) must be the tidyings alone.

### Phase C. Explore + research

Understand before changing; this holds even for a one-line tidying, since rework from skipped research costs more than the research.

1. Explore the lane's scope globs: if the `discovery` plugin is installed, invoke `/discovery:explore` via the Skill tool on the lane scope; otherwise read 5-10 representative files in the lane to understand current patterns, conventions, and existing tidyings.
2. Research current best practice for the lane's stack: if the `discovery` plugin is installed, invoke `/discovery:research` via the Skill tool using the lane file's preferred-source list; otherwise do a focused inline research pass (official docs + the lane's preferred sources) before editing.

### Phase D. Hunt + prioritize + scope-budget enforce

1. Read `reference/tidyings.md` for the full taxonomy (Beck 15 + Fowler 5 + prose tidyings P-1..P-6 = 26 entries).
2. Hunt: walk the lane's scope globs for instances of the lane's watch-for tidyings. Classify each candidate: tidying type, file, line range, estimated LOC delta, confidence.
3. Build a prioritized findings table. Each row carries a `Basis:`, `verified` with the `file:line`, tool output, or Phase C source URL it rests on, or `judgment` (never for a consequential change: cross-repo, shared infrastructure, irreversible, or security; one that cannot be verified is withheld and routed to the overflow list as an open question naming the evidence that would settle it). Contract: [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md); full convention: [recommendation-basis](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md#basis-label).
4. Apply the scope budget: the target and hard cap in [`${CLAUDE_PLUGIN_ROOT}/reference/pr-scope-budget.md`](../../reference/pr-scope-budget.md), with tidy's priority order and greedy selection in `reference/scope-budget.md` (spokes write the plugin directory as `<plugin-root>`, which is `${CLAUDE_PLUGIN_ROOT}`). Take the highest-priority subset that fits.
5. **Override enumeration gate**, only for paths lifted by the `override` argument. List those specific HARD paths the surviving candidates would touch, each with its tidying, and take a go-ahead on that list before Phase E. Interactive: the user answers. Non-interactive: report the list and continue with those argument-lifted candidates dropped, since a blanket token is not a decision about paths nobody has seen yet. Paths lifted by `hard_exclusions=advisory` or by `.claude/code-tidying/exclusion-overrides.md` skip this gate: those channels already are a standing decision, and a non-interactive run must honor them. A `dry-run` presents the argument-lifted enumeration and stops there. An argument-lifted path that no candidate touches never reaches this gate.
6. Overflow → file one work item per deferred candidate using the template in `reference/scope-budget.md`: invoke `/work-items:track add` via the Skill tool when that plugin is installed, else `gh issue create` (or present the list to the user when no tracker is reachable). **In `dry-run` mode, present the overflow list instead. Dry-run never files tracker items or causes any other external side effect.**

Zero applicable improvements: clean exit with a one-line note and NO PR. Do not produce empty-PR churn.

### Phase E. Implement

1. Use the Edit tool, never `sed -i`.
2. **One commit per logical tidying.** Atomic, structure-only. Beck: *"Each commit should fit comfortably in your head, on your screen, and in the team's review pipeline."*
3. `git add <path>` only, never `-A` or `.`: WIP from a parallel session can sneak in, even on a tidy branch.
4. Pre-flight every file with `git diff <path>` *before* staging. After staging, use `git diff --cached <path>` to confirm only the tidying went in.
5. Commit messages follow Conventional Commits with the lane's default type (e.g., `refactor:` for code lanes, `docs:` for prose lanes, `chore:` for tooling).
6. **`in-place`:** stage each tidying per steps 3-4 but do not commit; Phase H handles it.

### Phase F. Verify

Tidying is behavior-preserving, so verification confirms exactly that: run the project's build + tests + linters for the affected ecosystem (the lane file's verification commands; the consuming project's own CLAUDE.md / rules may name canonical commands). Red branch → fix or abort cleanly. **Never push red.** A tidying that broke a test or build was secretly behavioral: back it out; it belongs in a different PR with proper test coverage.

### Phase G. Self-review + simplify

1. Review the full diff yourself (`git diff origin/<default-branch>...HEAD`; under `in-place`, `git diff --cached`) hunting for accidental behavior change, scope creep, and convention violations. Drive real findings to zero before push.
2. Run `/simplify` on the touched files (NOT scope creep. Only files already edited). Rebuild and re-verify after simplify. Under `in-place`, stage what `/simplify` changed and re-review `git diff --cached` so Phase H ships it.

Self-review by the producing context is enough here: a fresh-context verifier is the rule where a verdict is subjective, and Phase F is an objective build/test/lint pass/fail. A change that turns out behavioral fails Phase F and is backed out, never verdict-reviewed into acceptance.

### Phase H. Ship

**`in-place`:** open no PR and post no comment. `in-place` leaves the tidyings staged; `in-place=commit` makes one commit of them, titled per the format below (via `/source-control:commit` when installed). Print to the user the title, Summary, Test plan, and the audit-trail sections below that would have gone to the PR, then stop.

Otherwise, never call `git commit` or `gh pr create` directly. Phase E already committed the tidyings, so what is left is PR creation, and that has a canonical gate (issue-linkage resolution, injection-safe body assembly, a pre-create check for a valid closing keyword or explicit opt-out) that a bare `gh pr create` skips.

If the `source-control` plugin is installed, invoke `/source-control:pull-request create` via the Skill tool. Its stage-and-commit step is a no-op here (the tree is clean from Phase E), so it goes straight to rebase-check, issue-linkage resolution, and gated PR creation. Its body template is fixed to Summary + Test plan, so supply only those two sections; tidy's own audit trail goes in a follow-up comment (below), not the PR body:

Title:

```text
<lane-default-type>(<lane-area>): <what was tidied>
```

Examples:

- `refactor(core): rename result helpers for reading order`
- `docs(skills): repair stale cross-references`
- `chore(tools): apply shellcheck/shfmt drift across tools/*.sh`

Body sections:

- **Summary**. 1-3 bullets: which lane, which tidyings, anchor commit.
- **Test plan**. Verification commands run + results.

`/source-control:pull-request create` reports the created `<pr_number>`. Immediately post one follow-up comment on that PR with `tidy`'s audit trail:

```bash
gh pr comment <pr_number> --body-file - <<'EOF'
## Tidyings applied

<table: tidying type → file → line range → LOC delta>

## Deferred items

<links to filed issue numbers, if the scope budget capped the run>

## Lifted HARD exclusions

<table: path → channel that lifted it (override argument | overrides file | hard_exclusions=advisory)>
EOF
```

The comment is never optional when a PR was created, and "Tidyings applied" is never empty then (no PR is created when there is nothing to tidy). Omit "Deferred items" when nothing was deferred and "Lifted HARD exclusions" when nothing was lifted; never post either as an empty table. A run that lifted a path and cannot post that table has not met the override contract; back the lifted edits out rather than shipping them unnamed.

If `source-control` is not installed, apply the same invariants inline: resolve issue-linkage before writing a closing keyword (`Closes #N` only after confirming issue #N exists in this repo, e.g. `gh issue view N`; otherwise state `No related issue: <reason>`), assemble the body via a quoted heredoc (`<<'EOF'`) plus parameter-expansion concat rather than an unquoted `<<EOF` (which would execute any `$(...)` embedded in prompt-derived text), and refuse to call `gh pr create` until the assembled body contains a valid closing keyword or the opt-out marker. In this fallback path only, the Tidyings-applied / Deferred-items / Lifted-HARD-exclusions sections stay in the PR body itself.

Then monitor checks (`gh pr checks <n> --watch`) until green. Address review-bot findings: verify each against the current code, fix the correct ones, rebut the incorrect ones with evidence. **Manual merge by a human**; this skill does NOT auto-merge.

## Global HARD/SOFT exclusions

Three exclusion tiers gate every lane. The full lists live in `reference/exclusions.md`; read it at the start of every run. This summary is orientation only.

1. **GLOBAL HARD**: paths not touched by default, regardless of lane, and lifted only through the override channels below: agent/CI/hook configuration (`.claude/**` in full, any script wired as a hook command in `.claude/settings.json` or `.claude/settings.local.json` wherever it lives, `.github/workflows/**`, git-hook manager config, `.mcp.json`, lint configs like `.editorconfig`) plus every path the consuming project's own rules declare protected.
2. **GLOBAL SOFT**: areas an autonomous run cannot verify safely (browser-rendered UI, interactive auth flows, DB migrations against real instances, IDE-only flows, and areas the project marks unverifiable). Routed to the deferred-items list in Phase D unless an interactive user explicitly overrides.
3. **SELF-UPDATE EXTRA HARD**: added when `<lane>=self-update`. Protects the skill's contract surface: frontmatter, the Action Router / Workflow / Lane-catalog sections, lane-file `## Scope` / `## Watch-for patterns` / `## Lane-specific extra exclusions` blocks, and `${CLAUDE_PLUGIN_ROOT}/reference/pr-scope-budget.md`, a generated copy of the shared convention whose numbers change only there. It is the only thing between an autonomous self-update run and this skill's own contract surface.

**Behavioral exclusions** apply whatever path an edit targets: DB migrations against real instances (safe only against an ephemeral test DB), breaking API changes, HTTP route signature changes, MCP tool schema changes, branch-protection or security-workflow rule changes, and work-tracking exclusions (items another agent claimed, items with an open linked PR, items labeled blocked/deferred). A candidate that would alter any of these is behavioral: file an issue instead.

**Overriding the HARD path list.** Every tier-1 path entry is overridable through three channels: the `override` argument (this run), the `hard_exclusions` userConfig option (this operator), and a tracked `.claude/code-tidying/exclusion-overrides.md` of root-relative globs (this repository). Precedence per path: argument, then repository file, then userConfig, then enforced. Full contract, file shape, and collision rules: `reference/exclusions.md` section 4. Nothing outside the tier-1 **path** entries is reachable: the behavioral guards, the work-tracking entries, tier 2 SOFT, and tier 3 EXTRA HARD hold at every setting. Lifting is not silent: a run that lifted anything names every lifted path and its channel in the Phase H report; a run that cannot produce that line enforces instead.

**Enforcement across phases:** Phase A seeds path-validation from the HARD list and resolves the three override channels into a lifted set. Phase D classifies candidates against HARD (drop unless lifted) and SOFT (defer). Phase E validates every Edit / Write target path against the HARD list minus the lifted set. The self-update lane additionally applies the EXTRA HARD list during Phases D and E, and the override channels do not reach it.

## Deferred items contract

Full template: [reference/scope-budget.md](reference/scope-budget.md). Every item the scope budget cuts becomes one filed work item, titled `<conv-type>(<area>): <what>`, whose body carries rationale, file list, scope estimate (LOC + files), and a link to the parent tidy PR (under `in-place`, the branch name). Phase H's "Deferred items" follow-up comment (or, without `source-control`, the PR body's own section; under `in-place`, the printed report) links every filed item by number.

## Boundary with the bundled `simplify` skill

`simplify` reviews the changed code, or a path or PR the user passes, for reuse, simplification, efficiency, and altitude cleanups, and applies the fixes; it does not hunt for bugs. This skill hunts unfiled structural drift across a rotated, glob-scoped lane regardless of recent activity, under a scope budget, and ships one structure-only PR. When `simplify` resolves, prefer it for refining a diff that exists (what you just wrote, a path, a PR); prefer this skill when nothing has changed yet and the question is what small structural improvement one slice can take today. `batch-simplify` owns the same cleanup at sweep scale.

**Mutation gate.** `simplify` edits the working tree. This skill makes its own scope-budgeted edits and commits them as tidyings, so never chain into a `simplify` run on this skill's behalf; the two anchors differ and their diffs would mix.

Bundled surfaces are gated by settings, environment, plan, and host; this section states what to do when one resolves, never that it is present. The four-part records live in [reference/bundled-simplify.md](reference/bundled-simplify.md).

## Gotchas

- **Beck's New Interface, Old Implementation is context-dependent.** Safe ONLY when the new interface has zero existing consumers. If consumers exist, treat it as behavioral and skip. Do not trust the "structural" label blindly.
- **Do not tidy your way around a banned or deprecated API.** If the lane scope contains call sites of an API the project bans, migrating them is behavioral. File an issue and defer.
