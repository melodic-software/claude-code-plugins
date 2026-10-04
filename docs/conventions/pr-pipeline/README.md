# PR pipeline convention

## Contents

- [Files](#files)
- [Stages](#stages)
- [Lanes](#lanes)
- [Activities](#activities)
- [Slots and order](#slots-and-order)
- [Outputs and skips](#outputs-and-skips)
- [Merge authority](#merge-authority)
- [Loop caps](#loop-caps)
- [Changing this config](#changing-this-config)
- [Names](#names)
- [Not settled yet](#not-settled-yet)
- [Versioning](#versioning)

Owner doc for the PR pipeline: the fixed sequence of GitHub Actions lanes a pull request passes
through once it is marked ready, until it merges. Local sessions stop at "ready"; the lanes run the
rest and a human steps in only where a lane escalates or a rung requires it. This doc fixes the
shape every PR-side lane builds on. Each lane's mechanics live in its workflow and the skills it
calls, not here.

The loop-lane convention ([`loop-lane`](../loop-lane/README.md)) governs local loop sessions; this
convention governs CI lanes. Holds, escalation and work classes stay owned by loop-lane and the
autonomy plugin, and this doc points at them.

## Files

| File | Holds |
|---|---|
| `README.md` | This contract. No config values. |
| `pr-pipeline.schema.json` | Schema for a repository's pipeline config. |
| `examples/` | Worked configs that show the shape. Script paths in them are placeholders until their lanes land. |
| `CHANGELOG.md` | Contract versions. |

A repository's config lives at `<root>/pr-pipeline.yaml`, where `<root>` defaults to
`docs/conventions` and a repository may point the config reader elsewhere. Config values live only
in that YAML file; agent instructions live only in Markdown.

## Stages

A PR moves through these stages in order. Stages are named, never numbered, so a new stage needs
no renumbering.

| Stage | What happens | Starts on |
|---|---|---|
| `intake` | Issues are triaged into work items. | issue events |
| `pre-ready` | The implementer writes the change and may push draft checkpoints at any time. Local today; the design assumes no particular implementer. | the implementer |
| `refine` | Behavior-preserving changes that make the PR review-ready: simplify, tidy, docs and format fixes. One push at the end. | ready (or opened ready) |
| `verify` | Checks, reviews and outcome verification on the refined commit, in three phases: mechanical, then judgment, then aggregate into `ci-status`. | dispatch from `refine` |
| `respond` | Address review feedback, fix failing CI, and update from the base branch. These lanes run concurrently. | see [Lanes](#lanes) |
| `merge` | Merge, within the configured rung. | final check green, or a hold removed |
| `post-merge` | Verify the default branch and sweep late comments into issues. | push to the default branch |

`maintenance` and `upstream` are scheduled producers, not steps in a PR's path. They file work
into `intake`.

Pipeline lanes skip draft PRs; `ci-status` still reports on them. Converting a PR back to draft
cancels every running pipeline lane for it.

## Lanes

A lane is one workflow with one job. The lane name is its workflow file stem, and the lane never
does another lane's job.

| Lane | Stage | Starts on | Never |
|---|---|---|---|
| `pr-refine` | refine | ready | Changes behavior |
| `pr-run-checks` | verify | dispatch from `pr-refine` | Writes to the branch |
| `pr-review`, `pr-review-security` | verify | dispatch from `pr-refine` | Pushes fixes |
| `pr-verify` | verify | dispatch from `pr-refine` | Pushes fixes |
| `pr-explain` | verify | dispatch from `pr-refine`, alongside verify | Gates |
| `pr-require-checks` | verify | each verify result | Runs work; it only produces `ci-status` |
| `pr-address-feedback` | respond | dispatch from the last verify step | Resolves human threads |
| `pr-fix-ci` | respond | a failed check, via `workflow_run`, once its decision record merges | Edits anything unrelated to the failure |
| `pr-update` | respond | push to the default branch, the hourly sweep, a merge-queue dequeue | Force-pushes |
| `pr-merge` | merge | final check green, or a hold removed | Merges above the rung or past a hold |
| `post-merge-verify` | post-merge | push to the default branch | Edits PRs |
| `post-merge-sweep-comments` | post-merge | push to the default branch | Reopens merged PRs |

`workflow_run` runs the default-branch copy of a workflow with secrets, so `pr-fix-ci` waits on a
human-merged decision record. The privileged-trigger tripwire in the two existing ci-workflows
review lanes binds only those lanes.

Every lane:

- Acts only on same-repository PRs, and only trusted actors' text reaches its prompt. The
  trusted-actor list is one central standards component that every lane reads.
- Runs Claude Code with `--permission-mode dontAsk` and every tool allowed, and gets the write
  access its job needs through a short-lived, job-scoped App token. Local lanes keep auto mode
  (AGENTS.md). Capability is never removed for safety; safety comes from who can trigger a lane,
  token lifetime and scope, workflow execution protections, the kill switch, and `ci-status`
  accepting only the App as its source.
- Writes through one per-PR queue (a concurrency group that queues, never cancels). It pushes its
  own commits as fast-forward updates, never with force. When the head moved, it fetches, replays
  its own commits and retries. `pr-update` writes first when it is triggered.
- Works each layer of a stack but touches only the lowest unmerged layer when fixing, and never
  rebases a stack.
- Respects the cross-lane hold, the `do-not-merge` label
  ([loop-lane](../loop-lane/README.md#cross-lane-pr-hold)), and the merge rule in AGENTS.md. A lane
  escalates through the `needs-human` role in the same section's escalation contract.

## Activities

An activity is one unit of lane work with a declared contract: a skill invocation, or a scripted
step with no model in it (the merge act and `ci-status` are scripted). It is defined once under
`activities:` and referenced by key from lane slots, so moving it is a config edit and the skill
itself never changes.

Each activity declares:

- `skill` (`<plugin>:<skill>[#mode]`) or `script` (a repository path).
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `publish-artifact`, `merge`. The
  runner derives ordering and the token grant from it, and fails a `read` activity that leaves the
  working tree dirty.
- `gating`: `gate` feeds `ci-status`; `advisory` is reported only. `ci-status` stays the only
  required check.
- `reads-untrusted`: whether it reads issue, PR, comment or web text. Ingested text is data, never
  instructions ([`untrusted-content`](../untrusted-content/README.md)).
- `inputs`: typed, from a closed set (`base-sha`, `head-sha`, `changed-paths`, `pr`, `issue`,
  `baseline`, `findings`). An activity reads nothing from a session.
- `scope` (`diff`, `tree`, `target`) and `applies-when` (paths, labels, work classes, events).

An activity is idempotent: a rerun on the same commit gives the same verdict or reuses it, a
mutating activity with nothing to change makes no commit, and each commit it makes names the
activity in a trailer. Unchanged content (same patch id) reuses the earlier verdict.

When an activity needs a human, it escalates with a resume key and exits instead of blocking. A
trusted label on that item resumes it. An expedite label from a human with write access skips
`refine`.

## Slots and order

A lane's `slots:` list names the activities it runs. Stage order is fixed by the table above; the
order inside a lane comes from config:

- Mutating slots run one at a time, in list order.
- Read slots run in parallel, each after the slots named in its `needs:`.
- A slot may replace its activity's `applies-when` or set `enabled: false`.

`refine` runs its steps in list order, format last, because earlier steps change whitespace.
`verify` runs on the refined commit; a push during `respond` makes earlier verify results stale,
and verify reruns on the new head. `refine` does not rerun on `respond` pushes.

The schema checks each file's shape. The config reader also rejects:

- an activity whose `effect` the lane's "Never" column forbids, such as a mutating activity in
  `pr-run-checks` or a `merge` effect outside `pr-merge`;
- a lane whose `stage` differs from the [Lanes](#lanes) table;
- a `needs:` entry naming an activity that is not in the same lane;
- a lane or activity name missing from the vocabulary ([Names](#names)).

## Outputs and skips

Each activity reports:

- A verdict: `pass`, `fail`, `neutral` or `skipped`.
- Findings in the detector-findings shape ([`detector-findings`](../detector-findings/README.md)),
  keyed by commit fingerprint so a verdict carries over when content is unchanged.
- An artifact bundle per [`record-bundle`](../record-bundle/README.md).
- A check run named `<lane> / <activity>`, for example `pr-refine / simplify`.

A skip reports as a neutral check with one reason: `not-applicable-paths`, `prerequisite-missing`,
`cost-gated`, `awaiting-human`, `superseded-sha` or `disabled-by-config`. Silence is not a skip.

Each review finding goes to an independent validator. Valid: fix it and reply with a citation.
Invalid: reply with a cited disagreement. Unsure: escalate. A script resolves bot threads after
the reply; human threads stay open for the human.

## Merge authority

`merge.rung` is the highest work class `pr-merge` merges without a human. Work classes are defined
in [`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md).

- `off` is the default. The first rung a repository adopts is `C2`, together with
  `merge.diff-check`: the diff touches no denied path and stays under the size cap.
- The work class comes from the linked issue's label and is re-checked against the diff. No class,
  or a class the diff contradicts, means no lane merge.
- C4 and C5 need a human, as loop-lane and the autonomy matrix state. Making C4 promotable needs a
  merged decision record and autonomy-plugin change first; until then the schema has no C4 rung.
- A rung rises only through a merged change to the config file. It falls automatically: when the
  default branch fails after a lane merge, that lane's merge rights turn off through a repository
  variable that can only lower the rung, and a `needs-human` issue is filed.
- A merge needs a review verdict on the final commit, or a verdict carried over by content
  fingerprint.
- `merge.stack-landing` defaults to `manual`.
- A repository has one merge authority: either the local babysit lane (loop-lane) or `pr-merge`.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
escalates.

## Changing this config

The config file is a lane-power file: a human merges every change to it, and no lane does. The
same holds for the trusted-actor list and any change to a lane's permissions, tokens or triggers.
Everything downstream of that human merge may propagate on its own.

## Names

Lane and activity names are verb-first and literal; review-engine activity names (`claude`,
`codex`) are the one exception. The allowed workflow stages, function words and engines are owned
by the `github-actions-conventions` component in `melodic-software/standards`
(`components/github-actions-conventions/vocabulary.json`); this doc and its schema never copy that
list. Pipeline stage keys (the [Stages](#stages) table) belong to this convention.

## Not settled yet

- The `extends:` grammar for layering a repository file on org defaults.
- How the config reader resolves `<root>` and reads the vocabulary.
- Whether judgment lanes in `verify` wait for the mechanical lanes, or start together and let
  `pr-require-checks` aggregate.
- The post-merge failure remedy (revert or fail forward, by change type). Until it is decided, the
  rung drop and `needs-human` issue above apply.

## Versioning

The schema's `version` is the contract major. [`CHANGELOG.md`](CHANGELOG.md) records each change.
