# skill-playbook

Design formats: [design/design-resolution.md](design/design-resolution.md).

## Brief

### TLDR

`/playbooks:repo-sweep` runs a catalog of hygiene skills through one repo per sweep: one worktree,
one branch, one draft PR, one commit per step, `/clear` between steps. Actions: `plan`, `next`,
`review`.

### Goal

A repeatable, updatable way to run the same ordered set of hygiene skills in every repo (and the
chezmoi dotfiles source), adapted per repo, resumable from any session or machine, with skill
defects fed back as issues against the owning plugin.

### Constraints

- Catalog file is the single home for skill inventory, default order, applies-when tests,
  arguments, default checked state, and interim override text (Q21). Updates ship as plugin
  releases.
- Lives in the `playbooks` plugin (Q22).
- Default order, six phases (Q11; basis `.work/skill-playbook/scope-matrix.md`):
  1. Code: audit-dead-code; batch-simplify repo docs; audit-comment-residue then dissolve-comments
     (one step); testing:audit and work-items:scan-todos (resolve/delete only) checked by default.
  2. Existence and copies: audit-derivability sweep; provenance sweep (checked by default, Q30);
     codebase-health:audit --fix (checked).
  3. Instruction content: /claude-api prompt-audit (agent-instruction files only, apply accepted
     edits, Q13); claude-config:audit-instructions; claude-memory:audit. These apply deletes and
     rewrites only; moves go to realign (Q31). `~/.claude` findings dropped in repo runs, handled
     in the dotfiles run (Q32).
  4. Structure: audit-noise; extract-ssot; instruction-placement audit, realign, check (one step,
     Q14); audit-progressive-disclosure; audit-encapsulation.
  5. Prose: writing:be-concise in place on an explicit list of human-facing markdown (Q19);
     ai-slop `audit fix .` last.
  6. Checks: toolchain:lint --fix, skill-quality:check, evals:validate, verification:confirm.
  Remaining qualifying skills from `.work/skill-playbook/candidate-scan.md` are in the catalog,
  unchecked (Q17); docs-hygiene:compress unchecked. rename-references is not a step.
- `plan`: recommends per entry from repo contents plus history (commit trailers and prior sweep PR
  checklists): run, rerun (version changed), rerun optional (same version ran; runs are
  non-deterministic, never auto-skipped), or not applicable, shown unchecked with the reason
  (Q15, Q23). Selection via a playground page: checkboxes, drag to reorder, copy the final plan;
  markdown checklist fallback; same format every time (Q24). Confirming opens the draft PR with the
  plan as a checklist (Q25, Q27).
- `next`: invokes /session-flow:orchestrate and /discipline:use-your-skills, then the first
  unticked step (Q18): audit, user reviews findings for accuracy, short inline scope questions (not
  /planning:interview), fix, one commit (Q4, Q5). Commit carries a
  `Playbook-Step: <plugin>:<skill>@<version>` trailer and a `Scope decisions:` section (Q29).
  No-change runs get a ticked checklist line with skill@version, no commit (Q3). Push every step;
  PR ready after the last (Q7). `/clear` between steps; handoff only when a step stops partway (Q6).
- Skills that create their own branch, PR, or commit structure run with an explicit override
  prompt (stay on the sweep branch, no PR, commits left to repo-sweep), each naming its tracking
  issue; `plan` flags an override for removal once that issue closes (Q34). Issues cite
  `docs/plugin-philosophy.md` "Two-lane convention posture" (Q33). Filed: #4503 (code-tidying
  tidy + batch-simplify), #4504 (docs-hygiene extract-ssot); scan in `own-branch-scan.md`.
  Related: #4502 (planning:interview lightweight mode, affects the per-step scope round).
- `review`: after every step, asks what went wrong; each problem goes through
  /plugin-quality:audit and is filed after user approval; catalog problems are filed separately
  (Q26).
- Repo order: alphabetical from `.github`; dotfiles last, run on the chezmoi source in a worktree,
  changes applied immediately with a targeted `chezmoi apply --source <worktree> <target>` (Q8, Q9,
  Q35).

### Acceptance criteria

- `/playbooks:repo-sweep plan` in `.github` lists every catalog entry with a recommendation and
  reason.
- A confirmed plan appears as a checklist in a newly opened draft PR.
- `next` after `/clear`, in any session or machine, resumes at the first unticked step.
- Each executed step produces exactly one commit with the trailer and a `Scope decisions:` section,
  or a ticked "no findings" line with skill@version.
- An override whose tracking issue is closed is flagged by `plan`.
- Changing the catalog order or membership needs no edit outside the catalog file.
- IF a skill ignores its override and creates a branch or PR, THEN `next` stops the step and
  `review` files the defect.
- IF the working tree is dirty when `next` starts, THEN it stops and asks.
- WHILE the sweep PR is merged or closed, `next` refuses to continue and points to `plan`.

### Captured assumptions

- Coverage cases (the three IF/WHILE criteria) were proposed by the agent and accepted with the
  user's general confirmation; the user may strike any.
- `acceptance_criteria_format` resolved to `free-text` (default): no convention-home pointer in
  claude-code-plugins.
- Memory slice placed in claude-code-plugins `.work/` because the session started outside a repo.

### Out-of-scope

- code-tidying:tidy as a checked step until it gains a caller-controlled mode (runs with override
  if the user ticks it).
- Fixing plugins that hardcode branch/PR creation (tracked by the Q33 issues).
- Running multiple playbooks (see Deferred questions).

### Deferred questions

- Q36 (arbiter: /planning:plan): the user expects future playbooks with other operating modes
  (more code cleanup, refactoring, other skill sets). Decide the skill name and layout that do not
  block that, e.g. catalogs as named files (`catalogs/hygiene.md`) and the playbook name in the
  trailer, without building multi-playbook support now.

## Plan

Skill root below: `plugins/playbooks/skills/repo-sweep/` (`<root>`). Scripts are bash plus `jq`
and `gh`, each with a sibling `*.test.sh` picked up by `scripts/run-plugin-tests.sh`.

Standards grounding: `.claude/rules/skill-bodies-state-current-rules.md` (`## Next` section,
verification records), `plugins/skill-quality/scripts/check-skill.sh --require-evals`
(frontmatter, evals), `scripts/check-changelog-parity.sh` (version bump),
`scripts/check-shell-portability.sh`, `scripts/check-fixture-git-isolation.sh`,
`scripts/check-html-assets.sh`, `.claude/rules/pr-body-contract.md`.

Tests run per suite: `bash scripts/run-plugin-tests.sh --suites-from <list>`, where `<list>` is
`find plugins/playbooks/skills/repo-sweep -name '*.test.sh'` written to a temp file.

Repo order (Q8) stays manual: SKILL.md states the rule (alphabetical from `.github`, dotfiles
last) and `plan` prints it; no state file tracks which repo is next.

Q36 settled: skill name `repo-sweep`; catalogs are named files under `<root>/catalogs/`, only
`hygiene.md` ships; commits carry `Playbook: <name>` beside `Playbook-Step`; the checklist marker
names the playbook. No `--catalog` argument until a second catalog exists.

### Phase 1: Catalog parser and version lookup [DONE]

Red-green per script.

- `<root>/scripts/catalog.sh <catalog-file>`: prints one TSV row per entry (`id`, `phase`,
  `skills`, `args`, `checked`, `issue`, `applies-when`) in file order; `--override <id>` and
  `--notes <id>` print that entry's block. Exits non-zero on a duplicate id or an entry with no
  `skill:`.
- `<root>/scripts/skill-version.sh <plugin:skill>...`: prints `plugin:skill@version` from
  `~/.claude/plugins/installed_plugins.json` (path overridable by env for tests). Keys there are
  `<plugin>@<marketplace>` with an array of installs; match on the `<plugin>@` prefix. Several
  installs: the project-scope entry whose `projectPath` equals the main checkout (`git rev-parse
  --path-format=absolute --git-common-dir`, parent dir) wins, else user scope. SHA-style versions
  are kept verbatim. No plugin prefix (built-in skills such as `/claude-api`): `@builtin`. Not
  installed: `@unknown`. A plugin loaded through `--plugin-dir` reads that plugin's `plugin.json`
  when `REPO_SWEEP_PLUGIN_DIRS` names it.
- Tests with fixture catalogs and a fixture `installed_plugins.json`.

**Sanity Check:** `bash <root>/scripts/catalog.test.sh && bash <root>/scripts/skill-version.test.sh`
exits 0 (the duplicate-id fixture case asserts a non-zero exit); `bash
scripts/check-shell-portability.sh --paths <root>/scripts/*.sh` exits 0.

### Phase 2: Hygiene catalog [DONE]

- `<root>/catalogs/hygiene.md`: every entry in the Brief's six phases in that order, using the
  arguments and merged steps from scope-matrix section 5, plus the unchecked candidate-scan
  entries (Q17) and `docs-hygiene:compress` unchecked. `code-tidying:tidy` present, unchecked.
- Override blocks on batch-simplify and tidy (#4503) and extract-ssot (#4504). Notes carry the
  Brief's per-entry rules: prompt-audit on agent-instruction files only (Q13); instruction-content
  steps apply deletes and rewrites only, moves go to realign (Q31); drop `~/.claude` findings in
  repo runs (Q32); scan-todos resolve or delete only; `evals:validate` args name the repo's eval
  suites, applies-when "repo has plugin eval suites".
- `catalog.test.sh` gains a structural check over the shipped catalog only: every entry with an
  `issue:` has a non-empty override naming that issue. No test pins ids or order, so reordering
  the catalog needs no other edit (acceptance criterion).

**Sanity Check:** `bash <root>/scripts/catalog.sh <root>/catalogs/hygiene.md | awk -F'\t'
'$5=="true"{print $1}'` prints the checked ids in the Brief's six-phase order (compared once, by
the phase commit's author, against the Brief list); `bash <root>/scripts/catalog.test.sh` exits
0.

### Phase 3: History, render, and sweep state [DONE]

- `<root>/scripts/history.sh`: per skill, the last version run. Primary source: the markers block
  of merged sweep PRs (`gh pr list --state merged --search "head:chore/repo-sweep-" --limit 1000
  --json headRefName,body`, then jq `startswith("chore/repo-sweep-")` as the exact filter), which
  survives squash merges. `@builtin` skills always recommend `rerun-optional` at most. Secondary: `Playbook-Step`
  trailers on the default branch. `gh` absent or unauthenticated: trailers only, with a warning
  line.
- `<root>/scripts/render.sh`: `--checklist <catalog> <selection-line> [<not-run-tsv>]` prints the
  PR checklist block; `--page <catalog> <recommendations-tsv>` prints the filled HTML page.
  Recommendation values: `run`, `rerun`, `rerun-optional`, `not-applicable`, each with a reason.
- `<root>/scripts/state.sh`: finds the sweep PR. On a `chore/repo-sweep-*` branch, the PR for
  that branch. Otherwise the open PRs in this repo whose `headRefName` starts with
  `chore/repo-sweep-` (same `--search ... --limit 1000` plus jq filter); one match prints the
  branch; several matches list them and stop. `next` then runs `git fetch origin <branch>` and
  `git worktree add <path> <branch>` itself, because `/source-control:worktree`'s helper always
  creates a new branch (`worktree-create.sh:914`, `worktree add -b`). Prints `pr-state`, `dirty`
  (yes/no), and the next line. Dirty ignores `.work/**` (skills write scratch there and not every
  repo ignores it). Body lines are read with `\r` stripped. Reconciles: a pending line whose skills
  already have a `Playbook-Step` trailer on the branch prints `untick-committed <id> <sha>` so
  `next` ticks it instead of rerunning; a bare `[x]` with no version (ticked in the web UI) is
  checked the same way and reported `done-unverified` when no trailer backs it. A `- [~]` line is
  the next step and a dirty tree under it means resume, not stop. The `repo-sweep: seed` commit
  (below) is ignored everywhere. Exit codes distinguish: no PR, PR merged or closed, dirty tree
  with no step in progress, all steps done, next step found.
- `<root>/scripts/tick.sh <id> <in-progress | committed <sha> | no-findings> <skill@version>...`:
  sets that one line to `[~]` or `[x]` via `gh pr view --json body` then `gh pr edit --body-file
  -`; re-reads the body after writing and fails if the edit did not land; fails if the line is
  missing or already done. One session per sweep; stated in SKILL.md gotchas.
- `<root>/scripts/guard.sh <base-sha> <pr-snapshot-file>`: `next` snapshots `gh pr list --author
  @me --limit 1000 --json number` before the step. After the step, guard stops on a branch change or a PR
  absent from the snapshot (Brief acceptance criterion). Any commit since `<base-sha>`
  on the same branch: prints the soft-reset squash command (`git reset --soft <base-sha>`) for
  `next` to run before the single step commit, since batch-simplify and extract-ssot commit per
  group or wave by design.
- Tests stub `gh` and `git` state with fixture repos in a temp dir.

**Sanity Check:** `bash scripts/run-plugin-tests.sh --suites-from <list>` exits 0 (covers
history, render, state, tick, guard tests); `render.test.sh` asserts the checklist output of a
fixture selection byte-equals a golden file; `state.test.sh` covers the other-branch discovery,
the reconcile, and the `[~]` resume cases; `bash scripts/check-fixture-git-isolation.sh` and `bash
scripts/check-shell-portability.sh --paths <root>/scripts/*.sh` exit 0.

### Phase 4: Selection page [TODO]

- `plugins/playbooks/reference/repo-sweep-plan-page.html`: static template, no network. The
  user chose a bundled template over `/playgrounds:use` so the page is identical every run.
  Checkbox per entry, drag to reorder, recommendation and reason per row, not-applicable rows
  unchecked. A copy button emits the `repo-sweep-selection:` line. `render.sh --page` injects a
  JSON data block and writes the filled page under `.work/`. Placed under `reference/` so
  `scripts/check-html-assets.sh` lints it; added to that script's manifest.
- Markdown fallback: `render.sh --checklist` over the recommended default selection, printed in
  chat for the user to edit.

**Sanity Check:** `render.test.sh` asserts the filled page contains every catalog id and no
external `src=`/`href=http`; `bash scripts/check-html-assets.sh` exits 0.

### Phase 5: SKILL.md, action references, evals [DONE]

- `<root>/SKILL.md`: action router (`plan`, `next`, `review`), `argument-hint`, description with
  triggers, `## Next` naming `/source-control:pull-request ready`, gotchas (non-deterministic
  reruns, override issues, dotfiles apply).
- `<root>/reference/plan.md`: dirty-tree and existing-sweep checks; run the scripts; judge each
  `applies-when` against the repo; flag overrides whose issue is closed (`gh issue view --json
  state`); open the page; on the pasted selection create the worktree via
  `/source-control:worktree`, branch `chore/repo-sweep-<playbook>-<yyyymmdd>` (suffix `-2`, `-3`
  when the branch exists), push an empty `repo-sweep: seed` commit (GitHub refuses a PR with no
  commits), and open the draft PR after user approval. Body per `pr-body-contract.md`: `No related
  issue: repo hygiene sweep`, checklist block in `## Summary`. `plan` prints the recommendation
  table in chat as well as the page, so a headless run shows every id.
- `<root>/reference/next.md`: `state.sh` gate (refuse on merged or closed PR and point to `plan`;
  stop and ask on a dirty tree with no step in progress; tick reconciled steps); invoke
  `/session-flow:orchestrate` and `/discipline:use-your-skills`; `tick.sh in-progress`; snapshot
  PRs; state the override and notes as `next`'s own instructions, then invoke each skill with only
  its `args` (skills parse their arguments as targets and actions); findings review with the user;
  inline scope questions; fix; `guard.sh` (squash if it says so); one commit through
  `/source-control:commit` with `Scope decisions:` in the body and `Playbook:`,
  `Playbook-Step:`, and `Co-Authored-By:` in one final trailer paragraph; push; `tick.sh`. Then
  prompt `review` before `/clear`. After the last step suggest `/source-control:pull-request
  ready` and confirm the markers block survived its body edit. Step stopped partway: leave `[~]`,
  invoke `/session-flow:handoff`. Dotfiles: run in the chezmoi source worktree
  (`~/.local/share/chezmoi-worktrees/`, found or created by `state.sh` discovery on another
  machine) and `chezmoi --source <worktree> apply <target>` per changed or added target, after the
  step commit. Deleted source files: chezmoi stops managing them and leaves the rendered file, so
  list them (`git diff --name-status --diff-filter=D <base>`), map each to its target, and remove
  it after user approval. Settings and hook targets under `~/.claude` take effect after a
  restart; say so in the step report.
- `<root>/reference/review.md`: ask what went wrong; per problem run `/plugin-quality:audit`;
  draft issues against the owning plugin, catalog problems as separate issues; file each only
  after user approval.
- `<root>/evals/evals.json`: trigger and action-routing cases for all three actions plus the
  dirty-tree and merged-PR refusals.

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT=plugins/playbooks/skills bash
plugins/skill-quality/scripts/check-skill.sh --require-evals repo-sweep` exits 0; `bash
plugins/skill-quality/scripts/check-evals-quality.sh <root>/evals/evals.json` exits 0; `grep -c
'^## Next' <root>/SKILL.md` is 1.

### Phase 6: Release plumbing [TODO]

- `plugins/playbooks/.claude-plugin/plugin.json` minor bump; `CHANGELOG.md` entry; plugin README
  skill list if one exists.

**Sanity Check:** `bash scripts/check-changelog-parity.sh --check-bump origin/main`, `bash
scripts/check-changed-skills.sh origin/main`, and `bash scripts/run-plugin-tests.sh --suites-from
<list>` exit 0.

### Phase 7: Acceptance run in .github [TODO]

- In a `melodic-software/.github` checkout, start every session with `claude --plugin-dir
  /home/kyle/worktrees/melodic-software-claude-code-plugins-feat-playbooks-repo-sweep/plugins/playbooks`.
  How to keep the installed `playbooks` from shadowing it is unverified: first try `--settings`
  with `enabledPlugins` setting `playbooks@melodic-software` to false; if that does not hold,
  disable the installed plugin for the test and re-enable it after. Either way, confirm the loaded
  copy by checking that the `plan` output names `repo-sweep-plan-page.html` under the worktree
  path.
- `claude -p '/playbooks:repo-sweep plan' --allowedTools 'Bash(bash:*)' 'Bash(gh:*)' 'Bash(git:*)'
  > /tmp/repo-sweep-plan-output.txt` (same flags) for the recommendation list. Whether `-p` runs a
  plugin slash command is unverified; if it does not, capture the interactive run's table
  instead. The interactive run confirms and opens the draft PR only after user approval
  (outward action).
- Run one `next` step, `/clear`, run `next` again in a new session with the same flags: it
  resumes at the first unticked step.

**Sanity Check:** `bash <root>/scripts/catalog.sh <root>/catalogs/hygiene.md | cut -f1 | while
read -r id; do grep -qw -- "$id" /tmp/repo-sweep-plan-output.txt || echo "missing $id"; done`
prints nothing;
`gh pr view <n> -R melodic-software/.github --json body` contains `repo-sweep:begin
playbook=hygiene`; `git log -1 --format='%(trailers:key=Playbook-Step)'` on the sweep branch is
non-empty and `git log -1 --format=%B | grep -c '^Scope decisions:'` is 1.

## Blast radius

MEDIUM. New skill in one plugin (10+ new files); no existing skill or contract changes. Trigger
matched: a new skill that composes other skills and has side effects (pushes, PR body edits,
draft PRs in other repos, chezmoi apply). All git-reversible; PR edits behind user approval.

## Stress-test summary

Plan-reviewer (fresh context): 24 findings, all verified against the repo and applied: sanity
checks fixed (check-skill.sh takes the skill name, run-plugin-tests.sh uses `--suites-from`, evals
via `check-evals-quality.sh`, no manual browser check); other-machine resume via
`headRefName` discovery; checklist/branch reconcile; `[~]` in-progress state; squash instead of
stop for multi-commit skills; PR snapshot baseline in guard; history primary source is PR markers
(squash-safe); commit through `/source-control:commit` with one trailer paragraph; `review`
prompted before `/clear`; page moved under `reference/` for the HTML lint; catalog tests pin no
order; portability and fixture-isolation checks added.

Devil's-advocate (fresh context, `/planning:devils-advocate`): 13 findings, confidence MEDIUM
before fixes; all applied. The worktree helper cannot check out an existing branch, so `next`
runs `git worktree add` for resume (confirmed at `worktree-create.sh:914`); an empty seed commit
before the draft PR; `--limit 1000` on every `gh pr list`; `.work/**` ignored in the dirty check;
dotfiles deletions and restart-bound targets handled; `skill-version.sh` matches
`<plugin>@<marketplace>` keys (confirmed in `installed_plugins.json`) and marks built-ins; CRLF
and web-UI ticks reconciled; override stated in context, never appended to skill args; branch
suffix on collision; word-anchored id check. Unverified, resolved in Phase 7: per-session
disabling of an installed plugin, and `claude -p` running a plugin slash command.

## Execution shape

Fully sequential. Phase 1 gates 2 (catalog test uses the parser); 3 gates 4 (page rendered by
`render.sh`); 5 cites every script; 6 and 7 need all prior phases. Parallel candidates (2 and 3)
save under 100 LOC of independent work.

| Phase | Surface | Basis |
|---|---|---|
| 1, 3 | sub-agent worker (Opus) | mechanical scripts with tests, file-disjoint from PLAN.md |
| 2 | main session | catalog content encodes interview decisions |
| 4 | sub-agent worker (Sonnet) | single static file |
| 5 | main session | skill body is judgment-heavy |
| 6 | sub-agent worker (Sonnet) | mechanical |
| 7 | main session | outward action, user gates |

## Open questions

None.

## Handoff to implementation

### User-approval gates

- Phase 7: opening the draft PR in `melodic-software/.github`, and every push there.
- Pushing this branch and opening its draft PR.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis |
|---|---|---|
| [EXEC-SHAPE] Squash a skill's several commits into the one step commit | `guard.sh` prints `git reset --soft <base>` instead of stopping; stops only on a branch or PR change | Brief acceptance criterion "exactly one commit" per step; batch-simplify and extract-ssot commit per group or wave by design |
| [EXEC-SHAPE] `[~]` in-progress checklist state | Checklist grammar gains a third state; a dirty tree under `[~]` resumes | Brief Q6 (handoff when a step stops partway) needs a resumable state |
| [EXEC-SHAPE] Empty `repo-sweep: seed` commit before the draft PR | `plan` pushes it; scripts ignore it | Brief Q27 (PR opens at plan confirm, before any step commit); GitHub refuses a PR with no commits |
| [EXEC-SHAPE] Branch `chore/repo-sweep-<playbook>-<yyyymmdd>` with `-2` suffix | `state.sh` and `history.sh` discover sweeps by this prefix | Needs a stable prefix for cross-machine discovery; `chore/` per branch convention |
| [EXEC-SHAPE] History reads merged PR markers first, trailers second | `history.sh` source order | Squash merges fold step trailers into one message |
| [EXEC-SHAPE] Page template at `plugins/playbooks/reference/repo-sweep-plan-page.html` | Phase 4 path; `check-html-assets.sh` manifest entry | That lint covers `plugins/*/reference/*.html` only |
| [FALLBACK — confirm or override] One session per sweep | Stated in SKILL.md gotchas; `tick.sh` verifies its write but does not lock | Concurrent sessions on one sweep can lose ticks; the Brief does not mention concurrency |
| [EXEC-SHAPE] Repo order stays manual | SKILL.md and `plan` print the rule; no state file | Brief Q8 sets the order but no tracking; fewest moving parts |

### Execution shape ([EXEC-SHAPE] tagged)

See Execution shape above. Workers may edit only their phase's files; PLAN.md edits stay
main-session.

### Mechanical work

One commit per phase, PLAN.md tag update in the same commit. Sequential fallback is the default
shape.
