# resolve-config

Read a repository's PR pipeline config from the base-SHA checkout, validate it, and resolve one
lane and activity into what the runner needs: the skill or script, the model, the turn budget and
the App token grant. The config's contract is the
[`pr-pipeline` convention](../../../docs/conventions/pr-pipeline/README.md).

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, its workflow's file stem |
| `activity` | empty | The activity to select from the lane's slots |
| `base-path` | `.base` | The base-SHA checkout; every config, schema and vocabulary read is under it |
| `config-path` | `docs/conventions/pr-pipeline.yaml` | The config, relative to `base-path`; for test callers only |
| `output-path` | required | Where the `ResolvedConfig` JSON file is written |
| `event-name`, `event-path` | the run's event | Decide an `events` predicate |
| `pr-number` | empty | `check-trusted-trigger`'s `pr-number` output |
| `github-token` | `${{ github.token }}` | Read-only; used only when a predicate needs the PR's labels or changed files |

It reads, all under `base-path`: the config, `docs/conventions/pr-pipeline/pr-pipeline.schema.json`
and `.github/standards/github-actions-conventions/vocabulary.json`. The lane rules
([`lane-rules.json`](lane-rules.json)) and effect grants ([`effect-grants.json`](effect-grants.json))
ship in this folder, which a lane runs from its own base checkout.

## What it rejects

The step fails and writes no file when:

1. The config is missing, is not valid YAML (duplicate keys and aliases included), or fails the
   schema.
2. It sets `extends:`, with any value.
3. An activity's `effect` or `gating` is one its lane's `lane-rules.json` row forbids.
4. A lane's `stage` differs from its `lane-rules.json` row, or the lane has no row.
5. A `needs:` entry names an activity that is not in the same lane.
6. A lane or activity name fails the vocabulary, or the vocabulary is missing.
7. A slot names an undefined activity, or the requested lane or activity is absent (an activity in
   two slots of the requested lane counts as absent).
8. `config-path` is absolute, contains `..`, has a basename other than `pr-pipeline.yaml`, or sits
   under `.github/actions/`; or the file it names resolves outside `base-path`.
9. An activity is named `run` or `report`, the runner's own job names.

It also fails when a predicate it decides cannot be decided: `pulls/{n}/files` lists 3000 files or
fewer than the PR's `changed_files`, a predicate needs the PR and there is no `pr-number`, or a
predicate reads `work-classes`, which no run supplies yet. With `activity` set it decides only the
selected slot's predicate, so another slot's predicate cannot fail the run; without it, every
enabled slot's.

## Output

The file at `output-path` holds `version`, `source` (`base-path`, `config-path`), `lane` (name,
stage, enabled, and every slot resolved), `selected` (the requested activity's slot, or null),
`loop` and `merge`. Every default is applied: `scope` `diff`, `enabled` true, `loop` 2 and 3,
`merge.rung` `off`, `stack-landing` `manual`, and `model` and `max-turns` null for the runner's
defaults. A slot's `applies-when` replaces its activity's. `merge.diff-check.denied-paths` always
gains the config path, `.github/**` and the trusted-actor list.

Each resolved slot carries `applies` and `skip-reason`: `disabled-by-config` when the lane or slot
sets `enabled: false`, `not-applicable-paths` when a `paths` predicate misses, `not-applicable`
when a `labels`, `events` or `work-classes` predicate misses. An enabled slot whose predicate was
not decided carries `applies` and `skip-reason` null. Its `grant` is the effect's row in
`effect-grants.json`.

Step outputs: `enabled` and `slots` (a JSON list of names); with `activity`, also `kind`,
`effect`, `gating` (`gate` or `advisory`), `skill`, `script`, `model`, `max-turns`,
`reads-untrusted`, `applies`, `skip-reason`, `contents`, `pull-requests`, `issues` and
`can-commit` (`false` only when `contents` is `read`).
`args` is free text and stays in the file.

## Job contract

A job that uses this action:

- Runs it after [`check-kill-switch`](../check-kill-switch/README.md) and
  [`check-trusted-trigger`](../check-trusted-trigger/README.md) both proceed, and before the PR
  head is checked out, from the base checkout: `uses: ./.base/.github/actions/resolve-config`.
- Leaves it without `continue-on-error`. An invalid config fails red; it is never a skip and never
  `proceed=false`.
- Passes `config-path` only from a test caller, never from a production dispatch input.
- Reads `args` from the file at `output-path`, never from a step output.

## Tests

`npm ci && npm test` in this directory runs `node --test`, with no network. Unit tests use the
minimal vocabulary in `fixtures/vocabulary.json` and the live schema; one integration test reads
the synced standards vocabulary and is skipped, with a message, while that file is absent. CI runs
the suite in the `Test resolve-config` step of the `test-node` job of
`.github/workflows/pr-require-checks.yml`.
