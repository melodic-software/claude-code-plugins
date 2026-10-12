# PR pipeline convention

## Contents

- [Files](#files)
- [Stages](#stages)
- [Lanes](#lanes)
- [Activities](#activities)
- [Slots and order](#slots-and-order)
- [Concurrency](#concurrency)
- [Outputs and skips](#outputs-and-skips)
- [Merge authority](#merge-authority)
- [Trust-root paths](#trust-root-paths)
- [Loop caps](#loop-caps)
- [Changing this config](#changing-this-config)
- [Outside this repository](#outside-this-repository)
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
| `unblock` | Take the action that unblocks a PR: today, resolve conflicts with the base branch. Fixing failing CI and addressing review feedback join as composites. | see [Lanes](#lanes) |
| `merge` | Merge, within the configured rung. | final check green, or a hold removed |
| `post-merge` | Verify the default branch and sweep late comments into issues. | push to the default branch |

`maintenance` and `upstream` are scheduled producers, not steps in a PR's path. They file work
into `intake`.

Pipeline lanes skip draft PRs; `ci-status` still reports on them. Converting a PR back to draft
cancels every running pipeline lane for it.

## Lanes

A lane is one workflow with one model job; scripted jobs beside it report its check runs. The lane
name is its workflow file stem, and the lane never does another lane's job. Each activity runs
through one of two shared runners:
[`pr-run-activity-read.yml`](../../../.github/workflows/pr-run-activity-read.yml) for a `read`
effect, with no App key and no OIDC token in the job that runs head code, after a separate job
asks the lanes token broker whether the lane may run, and
[`pr-run-activity-write.yml`](../../../.github/workflows/pr-run-activity-write.yml) for any other
effect, which gets its effect-scoped App token from the lanes token broker before any head
checkout. No workflow holds the App key. Their job contract is
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
| `pr-unblock` | a dispatch for each conflicting PR after a push to the default branch, or a trusted human's dispatch |
| `pr-merge` | final check green, or a hold removed |
| `post-merge-verify` | push to the default branch |
| `post-merge-sweep-comments` | push to the default branch |

`pr-unblock`'s dispatches come from `pr-unblock-dispatch.yml`, a scripted workflow with no model
that runs on a push to `main` and on a trusted human's `workflow_dispatch`:

- It lists open, non-draft, same-repository PRs into `main` that GitHub reports as `CONFLICTING`,
  re-querying an `UNKNOWN` PR up to 5 times, 10 s apart.
- It skips a PR whose head already has a `pr-unblock / resolve-conflicts` check run from the
  GitHub Actions app, unless that run is a neutral `Skipped: untrusted-trigger`.
- It dispatches `pr-unblock.yml` on `refs/heads/main` for at most 3 PRs per run, lowest number
  first, passing `pr-number` and `dispatcher-run-id`.
- A hand run or a re-run must be started by a listed human (`check-trusted-trigger` with
  `require-pr: false` and `require-kind: human`).
- With the kill switch on, the run ends green with a notice and dispatches nothing.

`workflow_run` runs the default-branch copy of a workflow with secrets; the conditions fixing CI
from it holds to are in [ADR 0051](../../adr/0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md).
Lanes run on GitHub-hosted runners without default-deny egress under the conditions in
[ADR 0049](../../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md).
Lane commits are signed, and signing is enforced by the default-branch rule only:
[ADR 0054](../../adr/0054-keep-commit-signing-on-the-default-branch-rule-and-add-no-all-branch-rule.md).

Every lane:

- Acts only on same-repository PRs, and only trusted actors' text reaches its prompt. The filter
  runs per item: each comment, review reply and linked issue is checked by its own author, not by
  the PR's. Web pages and CI logs are untrusted wherever they came from and stay data. The
  trusted-actor list is one central standards component that every lane reads.
- Runs Claude Code with `--permission-mode dontAsk` and the tools its skill needs to do its job: a
  write-effect skill can change, commit and push any file in the repository with its token
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). It gets the write access its job
  needs through a short-lived, job-scoped App token, revoked when the job ends. Local lanes keep
  auto mode (AGENTS.md). Capability is never removed for safety: a lane's scope comes from how
  granular its activity is, the PR is the review step, and safety comes from who can trigger a
  lane, token lifetime and scope, workflow execution protections, the kill switch, and a
  `ci-status` no lane can write (below).
- Reads its config, scripts and the trusted-actor list from the base SHA, never from the PR head,
  so a PR cannot change the rules it is judged by. Only the default branch is a trusted base, and a
  skill activity loads nothing else from the head:
  [ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md).
- Checks the org and repository kill switches before its model step starts, and runs only when
  both read exactly `false`.
- Never holds `checks: write` or `workflows` permission in a job that runs the model. `ci-status`
  and the `<lane> / <activity>` check runs are written by scripted jobs with no model step, and
  branch protection pins `ci-status` to the source that writes it
  ([ADR 0053](../../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md)).
  A base merge escalates to a human instead of being pushed when a path under
  `.github/workflows/` is left conflicted by the merge (before any model turn), or when the model
  staged a change under `.github/workflows/` (after it). A workflow change that comes cleanly from
  the base is merged and pushed with the rest.
- Writes through one per-PR queue (a concurrency group that queues, never cancels; see
  [Concurrency](#concurrency)). It pushes its own commits as fast-forward updates, never with
  force. A head that moved before the token mint skips the run with `superseded-sha`; one that
  moved during the run fails its push. Either way a later run on the new head does the work.
- Works each layer of a stack but touches only the lowest unmerged layer when fixing, and never
  rebases a stack.
- Respects the cross-lane hold, the `do-not-merge` label
  ([loop-lane](../loop-lane/README.md#cross-lane-pr-hold)), and the merge rule in AGENTS.md. A lane
  escalates through the `needs-human` role in the same section's escalation contract.

## Activities

An activity is one unit of lane work with a declared contract. A leaf is a skill invocation, or a
scripted step with no model in it (the merge act and `ci-status` are scripted). A composite groups
leaves under `children:`, a list of slots with the same keys and order rules as a lane's
`slots:`, and may set an `applies-when` that gates every child. Every activity is defined once
under `activities:` and referenced by key from lane slots or composite children, so moving it is a
config edit and the skill itself never changes.

A composite holds only leaves, so no leaf sits more than two layers below its lane. It declares no
effect, gating or inputs: each leaf keeps its own, gets its own grant, runs as its own job and
reports its own `<lane> / <leaf>` check, and the lane's rules apply to every leaf. A leaf runs only
when its lane, every slot on its path and its own slot are enabled, and when the composite's
predicate and its own both match. A leaf key appears at most once in a lane, so the key alone
selects it.

Each leaf declares:

- `skill` (`<plugin>:<skill>`) or `script` (a repository path), with optional `args` passed
  verbatim: after the skill name in that skill's own syntax, or to the script.
- `prepare` (optional, `skill` only, effect other than `read`): what the write runner does around
  the skill. `merge-base` merges the base tip into the gated head without committing before the
  skill runs, and commits the result with both as parents after it. A write runner performs this
  only where it declares support by passing `prepare-supported: true` to `resolve-config`; anywhere
  else an applying leaf that sets `prepare` fails red rather than running without it.
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
- `reads-untrusted`: whether it reads issue, PR, comment, web or CI-log text, or PR head files,
  which can quote such text. Ingested text is data, never instructions
  ([`untrusted-content`](../untrusted-content/README.md)).
- `inputs`: typed, from a closed set (`base-sha`, `head-sha`, `changed-paths`, `pr`, `issue`,
  `baseline`, `findings`). An activity reads nothing from a session. `changed-paths` is computed
  by the base-SHA config reader from the PR's file list, never from head text. It names what the
  activity is asked to work on, not what it can touch; for a write effect it leaves out
  instruction surfaces and paths `.github/CODEOWNERS` lists
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities); `changedPathTargets` in
  [`resolve.mjs`](../../../.github/actions/resolve-config/resolve.mjs)). When nothing is left, the
  activity skips with `not-applicable-paths`: `pr-refine / fix-docs` does not run on a PR whose
  only changed Markdown is instruction surfaces or CODEOWNERS paths, such as this directory.
- `scope` (`diff`, `tree`, `target`) and `applies-when` (paths, labels, `labels-absent`, work
  classes, events, `mergeable`, `draft`). `mergeable` is `conflicting` or `clean`, read from the
  PR at the gated head SHA only; unknown mergeability never matches. `labels-absent` matches only
  when none of its labels is on the PR.

An activity is idempotent: a rerun on the same commit gives the same verdict or reuses it, a
mutating activity with nothing to change makes no commit, and each commit it makes names the
activity in a trailer. Unchanged content (same patch id) reuses the earlier verdict.

When an activity needs a human, it escalates with a resume key and exits instead of blocking. An
activity whose `labels-absent` lists `needs-human` or `do-not-merge` skips with `awaiting-human`
while that label is on the PR; a human removes the label, then dispatches the lane, to resume it.
`labels-absent` reads only whether a label is present, not who set or removed it: it is a hold, not
a trust gate. An expedite label from a human with write access skips
`refine`. A label counts only when the actor on its label event is a trusted human: a label the App
set never resumes an item, expedites it, sets its work class or lifts a hold.

## Slots and order

A lane's `slots:` list names the activities it runs. Stage order is fixed by the table above; the
order inside a lane comes from config:

- Mutating slots run one at a time, in list order.
- Read slots run in parallel, each after the slots named in its `needs:`.
- A slot may replace its activity's `applies-when` or set `enabled: false`.

`refine` runs its steps in list order, format last, because earlier steps change whitespace.
`verify` runs on the refined commit; a push during `unblock` makes earlier verify results stale,
and verify reruns on the new head. `refine` does not rerun on `unblock` pushes.

The schema checks each file's shape. The config reader also rejects:

- an activity whose `effect` or `gating` the lane's row in `lane-rules.json` forbids, such as a
  branch-writing activity in `pr-run-checks` or a `merge` effect outside `pr-merge`;
- a leaf whose `effect` its row in
  [`activity-rules.json`](../../../.github/actions/resolve-config/activity-rules.json) forbids; a
  leaf with no row is valid;
- a lane whose `stage` differs from its `lane-rules.json` row, or a lane with no row;
- a `needs:` entry naming an activity that is not in the same `slots:` or `children:` list;
- a composite child that is undefined or itself a composite, a composite that contains itself, or
  a leaf that appears twice in one lane;
- `prepare` on a leaf whose effect is `read`;
- a lane or activity name missing from the vocabulary ([Names](#names));
- an activity named `run` or `report`, `pr-run-activity`'s own job names;
- any `extends:` value ([Not settled yet](#not-settled-yet)).

The reader also adds the config file's own path, `.github/**` and the trusted-actor list to
`merge.diff-check.denied-paths`, whatever the config says.

## Concurrency

| Scope | Rule | Set by |
|---|---|---|
| Triggers of one PR's `pr-unblock` | A newer dispatch replaces one still waiting; a running one finishes | workflow group `pr-unblock-<n>`, `cancel-in-progress: false` |
| Within one run | Leaves run in slot order: `report-escalation` after `resolve-conflicts`, and only when it escalated | the caller's `needs:` |
| Across PRs | Unbounded: every group is per PR | group names |
| Within one PR, across write lanes | One queue: a write job waits for the one ahead and never cancels it | job group `pr-pipeline-write-<n>`, `queue: max`, on every write caller job |
| `pr-unblock-dispatch` | One run at a time; a newer push replaces a waiting run | workflow group `pr-unblock-dispatch` |

The write group sits on each caller job, behind an `if:` that leaves out the lanes App's own
`pull_request` events, so a lane's push never queues a job in it.

## Outputs and skips

Each leaf reports:

- A verdict: `pass`, `fail`, `neutral` or `skipped`.
- Findings in the detector-findings shape ([`detector-findings`](../detector-findings/README.md)),
  keyed by commit fingerprint so a verdict carries over when content is unchanged.
- An artifact bundle per [`record-bundle`](../record-bundle/README.md).
- A check run named `<lane> / <leaf>`, for example `pr-refine / simplify`; a composite gets none.

A skip reports as a neutral check with one reason from the schema's `$defs/skip-reason`:
`not-applicable-paths` (a `paths` predicate missed, or every matching path was left out of
`changed-paths`), `not-applicable` (a label, event, work-class, `mergeable` or `draft` predicate
missed), `prerequisite-missing` (among others, mergeability still unknown at the gated head after
bounded re-reads), `cost-gated`, `awaiting-human` (among others, a `labels-absent` label is on the
PR), `superseded-sha`, `disabled-by-config` or `untrusted-trigger` (a fork, no same-repository PR, or an
actor or author not on the trusted-actor list). Silence is not a skip, with three exceptions that
post no check: a fork PR, whose read-only token cannot write checks; a `pull_request` event sent
by the lanes App; and a run on any other event whose run job gated no head SHA.

Each review finding goes to an independent validator. Valid: fix it and reply with a citation.
Invalid: reply with a cited disagreement. Unsure: escalate. A script resolves bot threads after
the reply; human threads stay open for the human.

## Merge authority

`merge.authority` names the repository's one merge authority: `local-babysit`, the babysit wrapper
run by the local babysit lane (loop-lane), or `pr-merge`. It has no default. `merge.rung` is the
highest work class that authority merges without a human. Work classes are defined in
[`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md).

- `off` is the default. The first rung a repository adopts is `C2`, together with
  `merge.diff-check`: the diff touches no denied path and stays under the size cap.
- The work class comes from the linked issue's label and is re-checked against the diff. No class,
  or a class the diff contradicts, means no lane merge.
- C5 always needs a human. C4 becomes promotable under
  [ADR 0050](../../adr/0050-let-merge-authority-reach-c4-by-evidence-and-drop-the-vendor-hosted-cap.md),
  but the schema adds no C4 rung until the autonomy plugin and loop-lane carry the matching change.
- A rung rises only through a merged change to the config file. Under `pr-merge` it falls
  automatically: when the default branch fails after a lane merge, that lane's merge rights turn off
  through a repository variable that can only lower the rung, and a `needs-human` issue is filed.
  The local babysit lane falls through a demotion issue instead (below).
- A merge needs a review verdict on the final commit, or a verdict carried over by content
  fingerprint.
- `merge.stack-landing` defaults to `manual`.
- A repository has one merge authority. The one exception is
  `.github/workflows/pr-automerge-dependabot.yml`, which merges Dependabot pull requests on its own
  rules whatever `merge.authority` says.

### The local babysit lane

The babysit wrapper (`babysit_merge.py` in the source-control plugin) may merge without a human
only when every read below allows it. Each read happens at one captured base SHA, and any read
that fails counts as a refusal.

- **Authority and identity.** `merge.authority` reads `local-babysit` and `merge.agent-identity`
  names the login the lane acts as. The schema rejects `local-babysit` without an identity. The
  identity must be a GitHub App's `[bot]` login, and the schema rejects any other login: a machine
  user is a GitHub user and would pass every human test. With no `merge:` block the
  rung is `off` and the wrapper merges nothing.
- **Effective rung.** The lowest of `merge.rung`, the `babysit_loop_merge` key in
  `.claude/source-control.md`, the cap variable, and `off` while any demotion issue is open.
- **Cap variable.** `CLAUDE_LANES_MERGE_RUNG_CAP` (`off`, `C2` or `C3`) is a repository variable
  only a human sets, and it can only lower the rung. The wrapper never writes it, and the identity
  can read variables but not write them. A 404 after the variables listing proved readable means no
  cap; any other failure means `off`.
- **Kill switches.** The org variable `CLAUDE_LANES_DISABLED` and the repository variable
  `CLAUDE_LANES_REPO_DISABLED` must each read exactly `false`. A read error, or a repository-level
  variable named `CLAUDE_LANES_DISABLED` that shadows the org one, refuses.
- **Demotion issue.** A failed post-merge check files an issue whose body starts with
  `<!-- babysit-merge-demotion sha=<S> signal=<name> -->` and that carries the `needs-human` label.
  It holds the rung at `off` until a human closes it directly. A close through a pull request's or
  commit's `Closes #N` does not count, and an issue that a non-human edited at any time stays in
  force. The wrapper finds these issues by author (the agent identity or `github-actions[bot]`), so
  removing the marker or the label does not clear one.
- **Opt-in label.** `merge: agent-allowed` makes a pull request eligible; it does not make it safe,
  and the diff risk score still decides. It counts only when a human added it last and the pull
  request body was not edited afterwards.
- **HIGH path floor.** A fixed set of paths in the wrapper's code, joined with
  `merge.diff-check.denied-paths` and matched case-insensitively. A diff that touches any of them
  scores HIGH and is never merged unattended.
- **One merge in flight.** The wrapper refuses while the identity has an entry in the merge queue,
  or while an earlier unattended merge has not passed its post-merge check.
- **Dependabot.** A dependency-manager author is never eligible for an unattended merge. Those pull
  requests stay with `pr-automerge-dependabot.yml`.

A human here is a GitHub user, not the agent identity and not an automation login, with write or
admin permission on the repository.

## Trust-root paths

A lane's token grant and the rules it is judged by come from these default-branch paths, so a
change to any of them is a change to every lane's powers:

- `docs/conventions/pr-pipeline.yaml` and `docs/conventions/pr-pipeline/**` (config and schema);
- `.github/actions/**`, which holds `resolve-config/effect-grants.json`,
  `resolve-config/lane-rules.json`, `resolve-config/activity-rules.json` and every action a lane
  job runs from its base checkout;
- `.github/standards/**`, which holds the trusted-actor list and the runner-policy script;
- `.github/workflows/**`;
- `.github/CODEOWNERS`.

Code-owner review is off on the default branch by owner decision: the `trust-root` and `base`
rulesets require no code-owner review and no approvals
([github-iac ADR 0007](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0007-no-required-approving-reviews.md),
amendment 2026-10-09; only azure-iac, which holds the broker, keeps it). `.github/CODEOWNERS`
still lists the trust-root paths, owned or not, and only requests review. The controls on a
trust-root change are:

- base-SHA config: every lane reads its config, grants, actions and trusted-actor list from the
  default branch, so a PR's own edit to them never governs its own run;
- the trusted-actor filter: the trigger gate and the broker refuse an untrusted actor, PR author
  or re-runner, and the lanes bot never starts a write run;
- the broker's workflow-path rule: it mints only for a lane caller listed in the default-branch
  config, calling a `pr-run-activity-write.yml` byte-equal to the tip, and the App token never
  holds `workflows`, so no lane can push `.github/workflows/`;
- the merge queue and the required `ci-status` check, which no lane can write;
- required review-thread resolution;
- the kill switch;
- broker scoping: one mint per job, this repository only, the effect's grant, at most an hour,
  revoked when the job ends;
- the lane session: `--setting-sources user`, an explicit `--permission-mode dontAsk`, and never
  `bypassPermissions`.

A write lane can change and commit any file in the repository its token reaches, trust-root and
instruction paths included; no tool rule limits which files it touches. The PR is the review step:
the review lanes, `ci-status`, review-thread resolution and the merge gate see every lane commit
before it reaches the default branch. Residuals, accepted by the owner:

- a trust-root change merges with no human approval; what stands between it and the default
  branch is the list above and whoever merges it;
- the model can read its token (`GH_TOKEN`, `GITHUB_TOKEN`, `.git/config`) until the job revokes
  it;
- a skill's `Bash` grant can be wider than its job: `ai-slop:audit`, which `fix-docs` runs,
  allows `Bash(git:*)` with no subcommand bound, and claude-code-action puts the token in the
  origin URL. A run, including one steered by untrusted text it reads, can then push to any branch
  no ruleset protects (the token is scoped to the repository, not the PR branch; rulesets cover
  the default branch and `release/plugins`), run any shell command through `git -c
  core.hooksPath=<dir>` or `git -c alias.<name>='!<command>'`, and push unsigned commits that skip
  the signed-commit tool and the lane-branch freshness check. Unsigned commits on the PR branch
  fail the check run's signed-commit step; a push to another branch is not checked;
- a lane commit can change instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/`, skills) that
  the PR author's local session loads once it checks out the branch.

The paths `.github/CODEOWNERS` lists with no owner are the eight synced data files (the
vocabulary, pyright and runner-policy data files) and the three synced hosted caller workflows
(`pr-check-managed-files-hosted.yml`, `pr-review-hosted.yml`, `pr-review-security-hosted.yml`).
The required `check-managed-files` job in `ci-status` fails any hand edit or deletion of them.
`pr-merge` never merges a PR that
touches a trust-root path, whatever its rung, and leaves it for a human. That refusal is recorded
here and in `pr-merge`'s `never` rule in `lane-rules.json`; the merge activity enforces it when
`pr-merge` is built.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
escalates.

## Changing this config

The config file is a lane-power file: a human merges every change to it, and no lane does. The
same holds for the trusted-actor list and any change to a lane's permissions, tokens or triggers.
Everything downstream of that human merge may propagate on its own.

## Outside this repository

The lanes depend on pieces other repositories own. Each row names where that piece is documented;
read it there, since this doc does not restate it. azure-iac, github-iac and architecture are
private. As of 2026-10-12; recheck when a row's owner moves the doc or a new external piece joins
the lanes.

| Piece | Owner and doc |
|---|---|
| Org architecture: why each trust link exists, glossary | `melodic-software/architecture`, `docs/trust-links.md` and `docs/glossary.md` |
| Token broker: the Function app, its Key Vault signing key, identities and roles, deploy | `melodic-software/azure-iac`: `README.md`, ADR 0001 (stack, who can mint), `src/lanes-token-broker/` |
| Broker operations: health check, taking it down, key disable, key rotation, fallback to a runner key | Not yet tracked; [azure-iac#17](https://github.com/melodic-software/azure-iac/issues/17) adds the runbook to azure-iac |
| Lanes App `melodic-automation-lanes`: identity and grant model | architecture `docs/trust-links.md` ("Lanes App"); github-iac ADR 0015 |
| Org variables `CLAUDE_LANES_DISABLED`, `LANES_BROKER_URL`, `LANES_BROKER_AUDIENCE`; repository variable `CLAUDE_LANES_REPO_DISABLED` | github-iac `OrgCiRouting.cs`; README "Claude lane kill-switches" (how to flip either switch); [ADR 0015](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md) |
| Agent identity (`merge.agent-identity`): the GitHub App the local babysit lane acts as, installed on this repository only, with variables read only | Not yet provisioned; [github-iac#691](https://github.com/melodic-software/github-iac/issues/691) |
| Repository variable `AUTOMATION_LANES_APP_SENDER_ID` | Set by hand on this repository and the sandbox, declared nowhere; [github-iac#677](https://github.com/melodic-software/github-iac/issues/677) |
| `trust-root` ruleset, merge queues, code-owner review settings | github-iac `OrgRulesets.cs`; ADR 0015 Decision 5; [ADR 0007](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0007-no-required-approving-reviews.md). Its rollback is not yet tracked: [github-iac#677](https://github.com/melodic-software/github-iac/issues/677) |
| Test repository | [`melodic-software/pr-pipeline-sandbox`](https://github.com/melodic-software/pr-pipeline-sandbox), whose README states its purpose |
| Trusted actors, runner policy, Actions naming vocabulary | `melodic-software/standards` components [`trusted-actors`](https://github.com/melodic-software/standards/tree/main/components/trusted-actors), [`runner-policy`](https://github.com/melodic-software/standards/tree/main/components/runner-policy) and [`github-actions-conventions`](https://github.com/melodic-software/standards/tree/main/components/github-actions-conventions), synced into `.github/standards/` |
| Review and intake reusable workflows | [`melodic-software/ci-workflows`](https://github.com/melodic-software/ci-workflows) `.github/workflows/pr-review.yml`, `pr-review-security.yml` and `intake-triage.yml`, called by this repository's synced `*-hosted.yml` callers and `intake-triage.yml` |

In this repository, the lane runners and their contract are in [Lanes](#lanes), the config is
`docs/conventions/pr-pipeline.yaml`, and the decisions are ADRs 0049 to 0051, 0053 to 0055 and 0058 in `docs/adr/`.

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
