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

A repository's config lives at `docs/conventions/pr-pipeline.yaml` unless the lane passes another
path as the config reader's `config-path` input. The reader reads that path at the base SHA; it
must be relative with no `..`, have the basename `pr-pipeline.yaml`, and sit outside
`.github/actions/**`. Config values live only in that YAML file; agent instructions live only in
Markdown.

## Stages

A PR moves through these stages in order. Stages are named, never numbered, so a new stage needs
no renumbering.

| Stage | What happens | Starts on |
|---|---|---|
| `intake` | Issues are triaged into work items. | issue events |
| `pre-ready` | The implementer writes the change and may push draft checkpoints at any time. Local today; the design assumes no particular implementer. | the implementer |
| `refine` | Behavior-preserving changes that make the PR review-ready: simplify, tidy, docs and format fixes. One push at the end. | ready (or opened ready) |
| `verify` | Checks, reviews and outcome verification on the refined commit. Mechanical and judgment lanes start together; a failed mechanical gate cancels the running judgment lanes, and `pr-require-checks` aggregates the results into `ci-status`. | dispatch from `refine` |
| `respond` | Address review feedback, fix failing CI, and update from the base branch. These lanes run concurrently. | see [Lanes](#lanes) |
| `merge` | Merge, within the configured rung. | final check green, or a hold removed |
| `post-merge` | Verify the default branch and sweep late comments into issues. | push to the default branch |

`maintenance` and `upstream` are scheduled producers, not steps in a PR's path. They file work
into `intake`.

Pipeline lanes skip draft PRs; `ci-status` still reports on them. Converting a PR back to draft
cancels every running pipeline lane for it.

## Lanes

A lane is one workflow with one model job; scripted jobs beside it report its check runs. The lane
name is its workflow file stem, and the lane never does another lane's job. Each activity runs
through the shared runner,
[`pr-run-activity.yml`](../../../.github/workflows/pr-run-activity.yml); its job contract is
[`pr-run-activity.md`](pr-run-activity.md).

Each lane's stage, the effects and gating it may not use, and what it never does are in
[`lane-rules.json`](../../../.github/actions/resolve-config/lane-rules.json), which the config
reader applies.

| Lane | Starts on |
|---|---|
| `pr-refine` | ready |
| `pr-run-checks` | dispatch from `pr-refine` |
| `pr-review`, `pr-review-security` | dispatch from `pr-refine` |
| `pr-verify` | dispatch from `pr-refine` |
| `pr-explain` | dispatch from `pr-refine`, alongside verify |
| `pr-require-checks` | each verify result |
| `pr-address-feedback` | dispatch from the last verify step |
| `pr-fix-ci` | a failed check, via `workflow_run` |
| `pr-update` | push to the default branch, the hourly sweep, a merge-queue dequeue |
| `pr-merge` | final check green, or a hold removed |
| `post-merge-verify` | push to the default branch |
| `post-merge-sweep-comments` | push to the default branch |

`workflow_run` runs the default-branch copy of a workflow with secrets; the conditions `pr-fix-ci`
holds to are in [ADR 0051](../../adr/0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md).
Lanes run on GitHub-hosted runners without default-deny egress under the conditions in
[ADR 0049](../../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md).
Lane commits are signed, and signing is enforced by the default-branch rule only:
[ADR 0054](../../adr/0054-keep-commit-signing-on-the-default-branch-rule-and-add-no-all-branch-rule.md).

Every lane:

- Acts only on same-repository PRs, and only trusted actors' text reaches its prompt. The filter
  runs per item: each comment, review reply and linked issue is checked by its own author, not by
  the PR's. Web pages and CI logs are untrusted wherever they came from and stay data. The
  trusted-actor list is one central standards component that every lane reads.
- Runs Claude Code with `--permission-mode dontAsk` and every tool allowed, and gets the write
  access its job needs through a short-lived, job-scoped App token, revoked when the job ends.
  Local lanes keep auto mode (AGENTS.md). Capability is never removed for safety; safety comes from
  who can trigger a lane, token lifetime and scope, workflow execution protections, the kill switch,
  and a `ci-status` no lane can write (below).
- Reads its config, scripts and the trusted-actor list from the base SHA, never from the PR head,
  so a PR cannot change the rules it is judged by. Only the default branch is a trusted base, and a
  skill activity loads nothing else from the head:
  [ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md).
- Checks the kill switch before its model step starts. A switch it cannot read counts as off.
- Never holds `checks: write` or `workflows` permission in a job that runs the model. `ci-status`
  and the `<lane> / <activity>` check runs are written by scripted jobs with no model step, and
  branch protection pins `ci-status` to the source that writes it
  ([ADR 0053](../../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md)).
  A base merge that touches
  `.github/workflows/` escalates to a human instead of being pushed by a lane.
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

- `skill` (`<plugin>:<skill>`) or `script` (a repository path), with optional `args` passed
  verbatim: after the skill name in that skill's own syntax, or to the script.
- `model` and `max-turns` (optional, `skill` only): the model and turn budget for the Claude Code
  run. When unset, `pr-run-activity`'s defaults apply.
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `publish-artifact`, `merge`. The
  runner derives ordering from it, takes the token grant from
  [`effect-grants.json`](../../../.github/actions/resolve-config/effect-grants.json), and fails a
  `read` activity that leaves the working tree dirty. An activity that runs head code (tests,
  linters, builds) takes effect `read`, because a write-effect activity must not execute head
  code; a fix-and-push lane waits on a split design (a read-only run, then a separate
  signed-commit step).
- `gating`: `gate` feeds `ci-status`; `advisory` is reported only. `ci-status` stays the only
  required check. A `gate` skill activity must not execute head code, since its verdict is read
  in the same job after the skill ran; tests, linters and builds that gate run as a `script`
  activity or under a separate design.
- `reads-untrusted`: whether it reads issue, PR, comment, web or CI-log text. Ingested text is
  data, never instructions ([`untrusted-content`](../untrusted-content/README.md)).
- `inputs`: typed, from a closed set (`base-sha`, `head-sha`, `changed-paths`, `pr`, `issue`,
  `baseline`, `findings`). An activity reads nothing from a session.
- `scope` (`diff`, `tree`, `target`) and `applies-when` (paths, labels, work classes, events).

An activity is idempotent: a rerun on the same commit gives the same verdict or reuses it, a
mutating activity with nothing to change makes no commit, and each commit it makes names the
activity in a trailer. Unchanged content (same patch id) reuses the earlier verdict.

When an activity needs a human, it escalates with a resume key and exits instead of blocking. A
trusted label on that item resumes it. An expedite label from a human with write access skips
`refine`. A label counts only when the actor on its label event is a trusted human: a label the App
set never resumes an item, expedites it, sets its work class or lifts a hold.

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

- an activity whose `effect` or `gating` the lane's row in `lane-rules.json` forbids, such as a
  branch-writing activity in `pr-run-checks` or a `merge` effect outside `pr-merge`;
- a lane whose `stage` differs from its `lane-rules.json` row, or a lane with no row;
- a `needs:` entry naming an activity that is not in the same lane;
- a lane or activity name missing from the vocabulary ([Names](#names));
- an activity named `run` or `report`, `pr-run-activity`'s own job names;
- any `extends:` value ([Not settled yet](#not-settled-yet)).

The reader also adds the config file's own path, `.github/**` and the trusted-actor list to
`merge.diff-check.denied-paths`, whatever the config says.

## Outputs and skips

Each activity reports:

- A verdict: `pass`, `fail`, `neutral` or `skipped`.
- Findings in the detector-findings shape ([`detector-findings`](../detector-findings/README.md)),
  keyed by commit fingerprint so a verdict carries over when content is unchanged.
- An artifact bundle per [`record-bundle`](../record-bundle/README.md).
- A check run named `<lane> / <activity>`, for example `pr-refine / simplify`.

A skip reports as a neutral check with one reason from the schema's `$defs/skip-reason`:
`not-applicable-paths` (a `paths` predicate missed), `not-applicable` (a label, event or
work-class predicate missed), `prerequisite-missing`, `cost-gated`, `awaiting-human`,
`superseded-sha`, `disabled-by-config` or `untrusted-trigger` (a fork, no same-repository PR, or an
actor or author not on the trusted-actor list). Silence is not a skip, with three exceptions that
post no check: a fork PR, whose read-only token cannot write checks; the lanes App's own
`synchronize` runs; and a `no-pr` run with no head SHA.

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
- C5 always needs a human. C4 becomes promotable under
  [ADR 0050](../../adr/0050-let-merge-authority-reach-c4-by-evidence-and-drop-the-vendor-hosted-cap.md),
  but the schema adds no C4 rung until the autonomy plugin and loop-lane carry the matching change.
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
list. The config reader reads the synced copy from the base SHA's
`.github/standards/github-actions-conventions/vocabulary.json`. Pipeline stage keys (the
[Stages](#stages) table) belong to this convention.

## Not settled yet

- Deferred: the `extends:` grammar for layering a repository file on org defaults. The reader
  rejects any value until a second repository adopts.
- The post-merge failure remedy (revert or fail forward, by change type). Until it is decided, the
  rung drop and `needs-human` issue above apply.

## Versioning

The schema's `version` is the contract major. [`CHANGELOG.md`](CHANGELOG.md) records each change.
