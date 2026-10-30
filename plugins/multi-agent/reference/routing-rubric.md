# Routing rubric: when a role may run on Haiku

Owner document for whether a role in [`defaults.yaml`](defaults.yaml), or any
routing guidance in this repository, may name `haiku`. Accuracy comes before
cost: a cheaper model that answers worse is not a saving.

## The rule

- **No role routes to Haiku until it passes this repository's routing eval**
  ([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901))
  for that role. Passing means matching the role's current default on
  accuracy at no higher tokens per completed task and no longer wall time. A
  retry or a re-run counts against the task it completes.
- **Haiku runs at effort `high` when a role does use it, never `xhigh` or
  `max`.**
- **No advisor is required.** A Haiku role is judged on its own output, not on
  an advisor model escalating for it.
- **A judge model the user selects is outside the rule.** The rubric governs
  the defaults this plugin ships and the guidance that cites them, not a model
  a user names for a run.

`/multi-agent:route` still resolves a role a config layer sets to `haiku`, or
that inherits a `haiku` session model, and adds a `notes` entry pointing here.
Nothing is blocked.

## Evidence so far

The `retrieval` role was evaluated against `sonnet` at `low`, its default at
the time, and Haiku
failed on accuracy
([#6955](https://github.com/melodic-software/claude-code-plugins/issues/6955)).
`retrieval` stays on `sonnet`.

The paired routing eval
([#10022](https://github.com/melodic-software/claude-code-plugins/issues/10022))
ran the worker (`evals/routing/mechanical-edit/`), retrieval and verifier
(`evals/routing/review/`) cases on Claude Code 2.1.314, 3 runs per case. Haiku
5.5 at `high` matched each role's current default on accuracy, but used more
input and output tokens per completed task in every role and took longer per
run on the verifier cases, so no role moves to `haiku` and every default in
`defaults.yaml` stands. Nearly every arm scored at or near 1.00, so these
cases barely separate the models on accuracy. The advisor arm did not run:
`claude plugin eval` loads no user settings, and no advisor tool appeared in a
probe run's tools.

## Where to read the specifics

- **Pointer**: when choosing an effort level for a role, fetch
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: a Claude Code release that changes the effort levels or
  which models accept them.

- **Pointer**: when checking what the `haiku` alias resolves to on a provider,
  fetch
  [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: a new Haiku model, or a change to the alias table.

- **Pointer**: when deciding whether evidence justifies changing a role's
  model, fetch
  [choosing a model: decide whether to upgrade or change models](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#decide-whether-to-upgrade-or-change-models)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: a new model row in that page's selection matrix.

- **Pointer**: when an advisor pairing is proposed for a Haiku role, read
  [anthropics/claude-code#91715](https://github.com/anthropics/claude-code/issues/91715)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: that issue closes, or a release note adds a
  per-subagent advisor setting.
