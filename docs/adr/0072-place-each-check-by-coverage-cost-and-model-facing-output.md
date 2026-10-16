# Place each check by coverage, measured cost and model-facing output

- Status: accepted
- Date: 2026-10-15
- Related: [ADR 0003](0003-verification-guards-earn-default-on-by-measured-precision.md) (guard
  defaults by measured precision), [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)
  (vendored shared code), [ADR 0048](0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md) (changelog
  fragments). The rubric, the registration contract and the duration budgets are in
  [`docs/conventions/check-placement/README.md`](../conventions/check-placement/README.md).

## Context

Every check plugin in this marketplace (formatters, linters, typos, actionlint) runs from a
per-edit `PostToolUse` row, and most report their findings to the model as `additionalContext` on
every matching edit while findings remain. Two problems follow:

- **Coverage.** A Claude Code hook sees only Claude Code's tool calls. A human, another agent, or a
  Bash write that bypasses Write and Edit commits without the check ever running.
- **Cost and noise.** Probes on Claude Code 2.1.300-2.1.301 with Sonnet 5.5 (2026-10-15) measured
  most real per-edit hooks at 40-180 ms on the reference host, and powershell-format at about 1 s
  per `.ps1` edit. A per-edit formatter on a partly formatted file broke 2-3 of 5 batched edits in
  every run and nearly doubled wall time, turns and context; the same formatter run once per batch
  from `PostToolBatch` broke none and cost about 0.7 s. In an open-ended task, an exit-2 per-edit
  lint finding led 2 of 2 runs to edit a line the user had not asked about.

A git `pre-commit` hook blocked every commit form probed (`git commit`, `git -C . commit`,
`git -c k=v commit`, `cd . && git commit`, `sh -c 'git commit'`) and passed its stderr straight
into the Bash result. A Claude Code `if: Bash(git commit *)` filter missed `git -C`, `git -c` and
`sh -c` forms.

Matt Pocock's guidance puts typecheck and tests in a pre-commit hook
([aihero.dev](https://www.aihero.dev/essential-ai-coding-feedback-loops-for-type-script-projects)).
This decision adopts that placement on the probe evidence above, not on his authority: his
"slows, fills context, distracts" wording was not found at his own sources, and Anthropic's own
docs show per-edit lint and test hooks as well.

## Decision

1. **Placement by rubric.** Each check runs where the rubric in
   [check-placement](../conventions/check-placement/README.md#the-rubric) puts it: a Claude Code
   hook to act before a tool call or change files in session; a git hook to cover every author;
   `pre-commit` within the commit budget, `pre-push` up to 60 s, CI beyond. Report-only findings
   never reach the model per edit. Each report-only check runs in exactly one local place
   (formatters excepted; the typos-format pilot left the end-of-turn check opt-in, off by default)
   and CI re-runs it on the change only; CI never skips a check because a
   hook passed; the twice-daily full-tree CI run stays.
2. **Formatters** rewrite once per batch in session from `PostToolBatch`, with no model-facing
   output, while the median per fire stays at or under 1 s, and again at `pre-commit`, rewriting
   and re-staging. A slower formatter runs at `pre-commit` only.
3. **Durations live in the convention**, one row per hook with the host that measured it. Other
   hosts re-measure; CI enforces counts ([hook-budget](../conventions/hook-budget/README.md)), not
   durations.
4. **One skip, defined once.** `git -c checks.skipmissing=<tool>[,<tool>]`, honored only for a tool
   the check finds absent and printed on stderr. An agent commit with a missing tool fails with the
   install command; a human commit gets a one-line notice. Both rely on CI re-running the check.

### The registration contract

Each check plugin ships `git-hooks/entries.json` (entry name, event, script, tools, whether it
rewrites) and its check scripts. Its setup gains `apply install-git-hooks [scope=local|shared]`,
and `check` runs `verify`. One installer, `lib/git-hooks/install.mjs`, vendored per ADR 0019,
implements a `HookManager` port (`detect`, `list`, `plan`, `copy`, `decline`) with lefthook, husky
and plain adapters, and `lib/git-hooks/check-lib.sh` gives every check script the same inputs:
staged files or the push range, changed-line ranges, the skip key, and agent detection. Installed
copies live in the repository, not the plugin cache: git hooks run outside Claude Code, and a
committed entry cannot name a versioned per-user cache path. Plain shared hooks are a committed
`.githooks/`, activated per clone with `git config core.hooksPath .githooks`; for teams with
non-Claude authors the convention recommends lefthook or husky. The convention's
[registration contract](../conventions/check-placement/README.md#the-registration-contract) holds
the manifest schema, the runtime contract and the port.

### The content-hash stamp

Line 2 of every installed copy is `# <plugin> <name> sha256:<hex>`, the hash of the source script
plus the check lib. `verify` compares it with the current source (stale) and with the copy's own
body (modified locally), and reports missing and declined entries; the SessionStart drift line runs
inside each plugin's existing `prerequisites.mjs probe` row. A plugin-version stamp was rejected:
this repository releases several times a day, so most version-drift notices would be false, and at
shared scope each rerun would add a commit to every consumer repository.

### The D1 split

Scripts only detect, list, diff, render snippets, verify, and write files the plugin owns outright:
copied check scripts, the plain dispatcher and its entries, and the `git config --local` decline
key. Every step that needs judgment returns to the setup agent as data, and the agent applies it:
edits to user-owned hook-manager config, a foreign hook, a manager conflict, scope in an attended
run, local-to-shared migration, which install command to run, and acting on drift.

## Alternatives considered

- **Keep per-edit hooks and tune them.** Rejected: they cover only Claude Code's own tool calls,
  and the probes measured broken batched edits and off-task fixes from per-edit output.
- **A Claude Code `if: Bash(git commit *)` gate in place of a git hook.** Rejected: the `if` filter
  missed `git -C`, `git -c` and `sh -c` commit forms, and each global git option would need its own
  pattern; it still covers no human or non-Claude author.
- **An environment-variable skip.** Rejected: any process inherits it, so one exported variable
  silently disables checks for every later commit. A `git -c` key applies to one command, is
  visible in the command line, and is honored only for a tool the check finds absent.
- **Agent-followed install recipes per plugin** (guardrails' current shape). Rejected: a SessionStart
  hook cannot run a recipe, so drift detection needs a script anyway; a recipe has no unit test; and
  the recipe repeats in every plugin.
- **git config-defined hooks (`hook.<name>.*`).** Not adopted: git 2.53.0 ignored a configured
  pre-commit entry in a probe. Recheck when the consumer git floor reaches the release that
  introduced them.

## Consequences

- Check plugins replace their per-edit report rows with git-hook entries, after a measured
  typos-format pilot; formatters move to one `PostToolBatch` row per plugin or to `pre-commit` only.
- Consumer repositories gain installed hook copies: local scope under the git hooks directory or
  `lefthook-local.yml`, shared scope under a committed `.githooks/`.
- A consumer without a CI job that re-runs a check should not use the skip, since nothing then
  backs it up; setup's agent says so per entry.
- Consumer-facing audit skills stop recommending per-edit report-only hooks and flag existing ones
  with the rubric's placement.

Recheck when a Claude Code release changes `PostToolBatch`, the "hook modified <file>" note, `if`
matching, or hook `ask` handling in auto mode, or when the typos-format pilot's verdict lands.
