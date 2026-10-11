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
| `head-sha` | empty | The gated head SHA; a `mergeable` predicate needs it |
| `prepare-supported` | `false` | `true` only from a runner that performs a leaf's `prepare` step |
| `github-token` | `${{ github.token }}` | Read-only; used only when a predicate needs the PR's labels, draft state, mergeability or changed files |

It reads, all under `base-path`: the config, `docs/conventions/pr-pipeline/pr-pipeline.schema.json`
and `.github/standards/github-actions-conventions/vocabulary.json`. The lane rules
([`lane-rules.json`](lane-rules.json)), per-leaf rules ([`activity-rules.json`](activity-rules.json))
and effect grants ([`effect-grants.json`](effect-grants.json)) ship in this folder, which a lane
runs from its own base checkout.

## What it rejects

The step fails and writes no file when:

1. The config is missing, is not valid YAML (duplicate keys and aliases included), or fails the
   schema.
2. It sets `extends:`, with any value.
3. A leaf's `effect` or `gating` is one its lane's `lane-rules.json` row forbids, for every leaf
   of every composite in the lane (`forbidden-by-lane`); or a leaf's `effect` is one its own
   `activity-rules.json` row forbids, in any lane or none (`forbidden-by-activity`). A leaf with no
   row in `activity-rules.json` is valid; a missing or malformed file, or a forbidden effect `effect-grants.json` lacks, is rejected
   (`activity-rules`).
4. A lane's `stage` differs from its `lane-rules.json` row, or the lane has no row.
5. A lane slot's `needs:` names an activity that is not one of the lane's slots
   (`needs-outside-lane`), or a composite child's names one that is not its sibling
   (`needs-not-sibling`).
6. A lane or activity name, composite names included, fails the vocabulary, or the vocabulary is
   missing.
7. A slot or composite child names an undefined activity, a leaf appears more than once in a lane's
   expanded tree, or the requested lane or activity is absent; a composite key is never a
   requested activity (`undefined-activity`).
8. `config-path` is absolute, contains `..`, has a basename other than `pr-pipeline.yaml`, or sits
   under `.github/actions/`; or the file it names resolves outside `base-path`.
9. An activity is named `run` or `report`, the runner's own job names.
10. A composite contains itself, directly or through another (`activity-cycle`), or holds a
    composite, which would put a leaf more than two layers below its lane (`activity-depth`).
11. A leaf whose effect is `read` sets `prepare` (`invalid-prepare`).
12. The selected leaf applies and sets `prepare`, and `prepare-supported` is not `true`: the
    runner would run the skill without its prepare step. The action checks this; `resolveGrant`
    does not.

It also fails when a predicate it decides cannot be decided: `pulls/{n}/files` lists 3000 files or
fewer than the PR's `changed_files`, a predicate needs the PR and there is no `pr-number`, a
`mergeable` predicate has no `head-sha`, or a predicate reads `work-classes`, which no run supplies
yet. With `activity` set it decides only the selected slot's predicates, so another slot's
predicate cannot fail the run; without it, every enabled slot's.

`mergeable` comes only from `GET /pulls/{n}`, never from the event payload, and only from a
response whose `head.sha` is `head-sha`: `mergeable: false` is `conflicting`, `true` is `clean`.
While the answer is null or describes another head, it reads again, three reads 5 seconds apart at
most, then leaves the fact unknown, which skips the slot with `prerequisite-missing`. `draft` comes
from the `pull_request` payload or the same response; on `workflow_dispatch`, labels, draft state
and mergeability all come from one response when its first read settles. A `labels-absent`
predicate always reads labels from that response, never from the payload, so a hold added after
the event still holds a queued run.

## Output

The file at `output-path` holds `version`, `source` (`base-path`, `config-path`), `lane` (name,
stage, enabled, and every slot resolved), `selected` (the requested activity's slot, or null),
`loop` and `merge`. Every default is applied: `scope` `diff`, `enabled` true, `loop` 2 and 3,
`merge.rung` `off`, `stack-landing` `manual`, and `model` and `max-turns` null for the runner's
defaults. A slot's `applies-when` replaces its activity's. `merge.diff-check.denied-paths` always
gains the config path, `.github/**` and the trusted-actor list.

The lane's slots are its leaves: each composite is replaced by its children, depth first in list
order. A leaf is enabled only when the lane, every slot on its path and its own slot are; it must
pass every composite predicate on its path and its own, and a composite's `paths` also narrows the
leaf's `changed-paths`. Its `needs` are the needs of each slot on its path, then its own, with a
composite named in `needs` replaced by its leaves. Its `applies-when` is its own predicate, and a
leaf that sets `prepare` carries it.

Each resolved slot carries `applies` and `skip-reason`: `disabled-by-config` when the lane or a
slot on the path sets `enabled: false`, `not-applicable-paths` when a `paths` predicate misses,
`awaiting-human` when a `labels-absent` label is on the PR, `not-applicable` when a `labels`,
`events`, `work-classes`, `mergeable` or `draft` predicate misses, and `prerequisite-missing` when
mergeability stayed unknown, in that order when several miss. An enabled slot whose predicate was
not decided carries `applies` and `skip-reason` null. Its `grant` is the effect's row in
`effect-grants.json`. The step fails when that row does not set exactly `contents`,
`pull-requests` and `issues`, each `read` or `write`, or when an `effect` is not a string: an empty
grant would mint a token with every App permission.

A slot whose activity declares the `changed-paths` input and applies also carries
`changed-paths`: the PR's changed files the head still holds, filtered as the
[skill activities contract](../../../docs/conventions/pr-pipeline/pr-run-activity.md#skill-activities)
states. It selects what the activity is asked to work on and is not a control; for a write effect
it leaves out instruction surfaces and every path in the base `.github/CODEOWNERS`. An empty
result turns the slot into `not-applicable-paths`. Declaring the
input makes the reader fetch the PR's files even without a `paths` predicate.

Step outputs: `enabled` and `slots` (a JSON list of names); with `activity`, also `kind`,
`effect`, `gating` (`gate` or `advisory`), `skill`, `script`, `model`, `max-turns`,
`reads-untrusted`, `applies`, `skip-reason`, `contents`, `pull-requests`, `issues` and
`can-commit` (`false` only when `contents` is `read`), and `prepare` only when the leaf sets it.
`args` is free text and stays in the file.

## Token broker entry point

`resolve.mjs` exports `resolveGrant(files, { lane, activity, configPath })` for the token broker,
which fetches `effect-grants.json` and `lane-rules.json` from this repository's default-branch tip
and decides a lane's App token grant through it. It runs the same file checks as the action
(rejections 1-11 above) and the effect-grant check, for one required leaf `activity`, and returns
`{ effect, grant }`, where `grant` is a frozen copy of the effect's row in `effect-grants.json`. A
slot whose lane or slot sets `enabled: false` gets no grant: it rejects with `slot-disabled`. It
decides no `applies-when` predicate, so it takes no facts. `applies-when` is not an authorization
control: it decides whether a slot runs, never what its token may do. Like `resolve()`, it throws
a `Rejection` whose `code` names the failure. `files.activityRules` is required: a caller that
passes none is rejected with `activity-rules`.

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
