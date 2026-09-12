# plugin-evals

Topic slug `plugin-evals`. Branch `plugin-evals`, one worktree, one PR. Interview locked 2026-09-11.
Inputs and ledgers: `.work/plugin-evals/INDEX.md`.

## Brief

### TLDR

Adopt `claude plugin eval` (Claude Code 2.1.269) in this marketplace as a guided, repeatable,
metric-driven practice: a workflow skill and a static case validator in `plugins/evals/`, a pilot
suite on the `evals` plugin, and the removal of every recorded decision or statement the command's
release invalidates.

### Goal

A user of this marketplace can take any plugin (or a standalone skill or agent, wrapped as one),
set up an eval suite, validate it without spending, run it under a cost policy they chose, read the
with-versus-without-plugin delta correctly, and iterate on the plugin from that number. This repo
does the same for itself, starting with one pilot suite.

### Constraints

- The plugin is the only unit the harness loads and ablates. Skills and agents are evaluated through
  the wrap route (`claude plugin init <name>` or a minimal `.claude-plugin/plugin.json`); hooks and
  commands as plugin components, hooks with the docs' advisory caveat; `CLAUDE.md` and rules are out
  of scope and routed to `claude-config:unhobble`.
- Both new pieces live in `plugins/evals/`. `skill-quality:check validate-evals` keeps the
  skill-creator `evals.json` format; the two descriptions cross-reference. `evals:design` hands plugin
  targets to `claude plugin eval init` rather than scaffolding the new format.
- Native Windows has no sandbox backend; cases that grant Bash, Write, or Edit are refused there.
  Preflight detects the backend and says so; read-only suites run locally; Bash-granting suites run
  on another machine or a Claude cloud session.
- Cost: a plugin user-config ceiling passed as `--max-cost-usd` (default 5 USD) and an unlimited
  option that removes the ceiling only; the estimate is always shown; with unlimited set the run
  starts without waiting. The ceiling bounds a list-price estimate, not subscription usage.
- Every volatile fact about the command (flags, schema bounds, exit codes, sandbox behavior,
  version floor) is carried as a four-part upstream-drift record per
  `.claude/rules/skill-bodies-state-current-rules.md`; no date-conditional prose, no bare pinned
  version as fact. The feature shipped 2026-09-11 and has no independent corroborating source yet.
- A `plugin eval` record is added to `docs/native-surfaces/records.json` before any skill references
  the command.
- `evals/results/` is gitignored per the docs; any committed pilot evidence is a stated exception.
- Recorded decisions reopened, each in the open: the migration playbook "Evals" deferral becomes an
  adoption record with `melodic-software/medley#1418` linked, not closed; every "does not execute
  evals" statement in the `evals` plugin is replaced; the unhobble routing in
  `docs/specs/prompt-audit-skills-2026-09.md` narrows to `CLAUDE.md` and rules; a sweep removes
  anything else the change invalidates.
- No tracker writes without explicit say-so. The PR opens as a draft and is flipped when done.
- New skill leaf names are registered in `scripts/skill-leaf-name-registry.txt` if shared across
  plugins; the `evals` plugin CHANGELOG and version are bumped.

### Acceptance criteria

- The guide skill's preflight, run on this machine, reports the Claude Code version, the absence of
  a sandbox backend, and the target type correctly for a plugin, a wrapped skill, and a rules target
  (refused with the unhobble pointer).
- The static validator flags an unknown `prompt.md` frontmatter key, a duplicate grader name, and a
  case with no grader, and passes the pilot suite, with no model call.
- The pilot suite on `plugins/evals/` runs locally under the ceiling, writes `aggregate-result.json`
  with a delta per case, and at least one case shows a positive delta.
- IF the sandbox backend is absent and a case grants Bash, THEN the guide refuses the run before any
  spend and names the reason and the cloud route.
- WHILE the cost option is unlimited, the pre-run estimate is still shown and the run proceeds
  without a prompt.
- No tracked file still states that this marketplace does not execute evals, and no tracked file
  still describes `claude plugin eval` as early access or deferred.
- `scripts/affected-tests.sh --run`, `scripts/check-changed-skills.sh`, the skill-quality check, and
  the leaf-name check pass on the branch.

### Captured assumptions

- "Let's start there" in round 2 was read as accepting Q8 through Q11 as recommended; stated to the
  user, not corrected.
- The pilot suite's read-only cases are enough to produce a meaningful delta for the `evals` plugin;
  if they are not, the pilot moves to the cloud follow-up rather than granting Bash here.
- The acceptance-criteria format resolved to `free-text` (default) because the repo declares no
  convention-home pointer.

### Out-of-scope

- Evaluating `CLAUDE.md` or rules through the harness, including an `append_system_prompt` shim.
- A rollout of eval suites across the other plugins in this repo; one pilot only.
- Retargeting `evals:design` to emit the plugin-eval case format.
- Any change to the `planning` plugin's emoji markers.

### Deferred questions

- Q12 (arbiter: USER-RESERVED): empirical execution of Bash-granting and Write-granting cases,
  which native Windows refuses. Worked in a Claude cloud session or on a Linux/macOS machine after
  this PR; findings feed corrections to the guide. Captured here and in the PR body; a GitHub issue
  is opened only when the user says so at PR time.

## Plan

(empty; `/planning:plan` fills this)
