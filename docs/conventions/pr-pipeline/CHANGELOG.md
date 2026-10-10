# Changelog for the PR pipeline convention

## 1.4.0 - 2026-10-10

Write activities get a narrower grant, the tools their skill needs and computed targets. `version`
stays 1.

- `effect-grants.json`: `mutate-branch` grants `contents: write` with `pull-requests: read` and
  `issues: read`. The broker reads the same file at the tip, so a job resolved from an older base
  fails `effect-mismatch` until the PR's base moves past this change.
- A skill with any effect but `read` gets `Edit`, `Write`, `Agent` and the signed-commit tool, and
  its own `allowed-tools` Bash; `WebFetch` and `WebSearch` stay off. No rule limits which files it
  changes; the PR is the review step. `collect-base-activity` takes a required `effect` input and
  drops its `reads-untrusted` and `trusted-context-path` inputs.
- The `changed-paths` input is now passed: `resolve-config` writes it to the resolved file from the
  PR's file list, and the prompt carries it after `args`. It selects what the skill is asked to
  fix and is not a control. For a write effect it leaves out instruction surfaces and every path
  the base `.github/CODEOWNERS` lists, and it drops a name with a leading `@`; an empty result
  skips the activity with `not-applicable-paths`.
- The trusted PR context reaches a `reads-untrusted` skill only as `TRUSTED_CONTEXT_FILE`; the
  prompt no longer carries a `Trusted PR context:` line.
- The write runner cuts the lane token string out of the skill's reply before showing or uploading
  it.
- `reads-untrusted` also covers PR head files, which can quote untrusted text.
- The trust-root section states the hardening in force now that code-owner review is off by owner
  decision, that a write lane can change any file, and the residuals, including what a skill's
  unbounded `Bash(git:*)` grant allows with the token in the origin URL.
- A skill that can commit commits to a lane branch made at the gated head SHA; the write runner
  fast-forwards the PR branch to it only while the PR branch is still at that SHA, so a push
  during the run is never overwritten, and fails the activity otherwise.

## 1.3.0 - 2026-10-10

The write runner gets its token from the lanes token broker. `version` stays 1; callers of the
write file must change.

- `pr-run-activity-write.yml` drops the `app-private-key` secret and the
  `create-github-app-token` mint. Its run job holds `id-token: write` and, before
  `select-trusted-text` and any head checkout, calls the new `request-lane-token` action, which
  sends the job's OIDC token to `LANES_BROKER_URL` for audience `LANES_BROKER_AUDIENCE` once,
  never retrying. Either variable empty fails red.
- The step fails red on any answer but 200 (`lane-token-denied` with the broker's reason, or
  `broker-unreachable`), and, after revoking the token, on a 200 whose effect, permissions, lane,
  activity or repository differ from the job's own (`effect-mismatch`). The contract lists the
  broker's reasons, `default-branch-not-main` included.
- A final `if: always()` step, `actions/github-script` pinned by SHA, revokes the token and fails
  red unless `DELETE /installation/token` returns 204 and a later
  `GET /installation/repositories` with the token returns 401.
- Callers of the write file pass no App key and grant `id-token: write` on the calling job.
  `AUTOMATION_LANES_APP_CLIENT_ID` is no longer read.
- With no App key in either runner, one lane may call both files.
- `scripts/check-app-key-references.sh` fails `lint-repo` on `AUTOMATION_LANES_APP_PRIVATE_KEY`,
  `app-private-key` or `AUTOMATION_LANES_APP_CLIENT_ID` anywhere under `.github/workflows/` or
  `.github/actions/`.

## 1.2.0 - 2026-10-04

The runner splits in two. `version` stays 1; callers of the old file must move.

- `pr-run-activity.yml` becomes `pr-run-activity-write.yml`, for every effect but `read`. It keeps
  the App key and its mint, fails red with `effect-read` on a `read` activity, and stops with
  `bot-actor` when the lanes App bot is the sender or a `workflow_run` actor. A `bot-actor` stop
  posts neutral `untrusted-trigger`, like the other trust stops.
- New `pr-run-activity-read.yml` runs `read` activities with no App key secret and no `id-token`
  permission, and fails red with `effect-not-read` before the head checkout on any other effect.
- Both pass the run attempt's `triggering_actor` to `check-trusted-trigger`. A re-run by an
  account not on the trusted-actor list, by a denied account, or with no triggering actor stops
  with `untrusted-rerunner`, which has no skip mapping, so the check posts failure rather than
  turning an earlier red check on the same SHA neutral.
- Until the token broker lands, a lane runs head-code read activities only when no file of its run
  references the App key; `scripts/check-read-caller-keys.sh` checks it.
- The README lists the trust-root paths, and `pr-merge` refuses any PR that touches one. The
  refusal is recorded now and enforced when `pr-merge` is built.

## 1.1.1 - 2026-10-04

Fixes to the runner and reader. `version` stays 1.

- A `no-pr` trigger stop on `pull_request` posts neutral `untrusted-trigger` on the event's head
  SHA instead of no check. Three runs post no check: a fork PR, a `pull_request` event sent by the
  lanes App, and a run on any other event whose run job gated no head SHA.
- With an activity requested, `resolve-config` decides only that slot's `applies-when`, so another
  slot's undecidable predicate no longer fails the run; the other slots carry `applies` null.
- A requested lane the config lacks is rejected as `undefined-lane`, not `undefined-activity`.
- The run job's unused `applies` output is removed.
- `select-trusted-text` takes the job's `GITHUB_TOKEN` for a `read` activity, as the runner already
  passed it; that token has no `issues` grant.

## 1.1.0 - 2026-10-04

Additive, except one tightening: the activity names `run` and `report` are now rejected.
`version` stays 1.

- Activities take optional `model` and `max-turns` (skill activities only); `args` now applies to
  `script` activities too.
- Skip reasons gain `untrusted-trigger` and `not-applicable`; the schema's `$defs/skip-reason`
  holds the full set. Fork PRs, `pull_request` events sent by the lanes App, a `no-pr` run with no
  head SHA, and a run on any other event whose run job gated no head SHA post no check.
- A lane is one workflow with one model job; scripted jobs beside it report its check runs.
- Mechanical and judgment `verify` lanes start together; a failed mechanical gate cancels the
  judgment lanes.
- The config path is the reader's `config-path` input, read at the base SHA, with its basename and
  location constrained; the vocabulary is read from the base SHA's synced copy.
- Each lane's stage, forbidden effects and gating, and "never" rule move to
  `.github/actions/resolve-config/lane-rules.json`, and each effect's App token grant is in
  `effect-grants.json` beside it.
- The reader rejects any `extends:` value and the activity names `run` and `report`.
- `resolve-config` outputs the selected activity's `gating`.
- An activity that runs head code (tests, linters, builds) takes effect `read`; a write-effect
  activity must not execute head code.
- A `gate` skill activity must not execute head code; gating tests, linters and builds run as a
  `script` activity.
- The example config drops the `format` slot (`toolchain:lint --fix`, `mutate-branch`), which ran
  head code with a write token, and disables the `fix-ci` slot for the same reason until a split
  design exists.

## 1.0.0 - 2026-10-03

Initial contract: pipeline stages and their order, lane boundaries, the activity contract, slot
ordering, outputs and skip reasons, merge rungs, loop caps, and the config schema.
