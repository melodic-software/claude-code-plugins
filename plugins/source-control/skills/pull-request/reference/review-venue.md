# Review venue (`review-venue`)

A change gets one AI review venue per lane. When the repository's CI review lane covers that lane
and is healthy, CI reviews the pull request and no local review runs for it. When the lane is
absent or unhealthy, the local review runs and the report names it as that lane's stand-in. The
`review_venue` setting can fix the venue instead. This file is the one statement of that rule;
[prep.md](prep.md) §1.2, [ready-for-review.md](ready-for-review.md) §2.5.3 and any other skill
that reviews before or at the ready flip read the venue through it, never through a copy of its
test.

## Read the setting

Read `review_venue` first, once per phase, with the bundled reader, which changes nothing:

```bash
bash "<skill-dir>/scripts/read-review-venue.sh" --user '<SKILL.md "Review venue" value>' \
  [--base <base> --default-branch <default> (- | --http-response)]
```

Pass the repository's `docs/conventions/source-control.yaml` as the PR's base branch holds it,
never the working tree's or the head's copy, since `ci` turns local reviews off
([GitHub](../../../reference/providers/github/pull-request/review-venue.md#read-the-setting-at-the-base)).
Before the PR exists (prep), the base is the branch the PR will target. When
`<plugin-root>/lib/config-root.sh classify` does not print `repo`, pass `--user` alone. The reader
prints `review_venue<TAB><value><TAB><level>`; levels and fallbacks are in
[config-resolution.md](../../../reference/config-resolution.md#yaml-keys-docsconventionssource-controlyaml).
Relay any notice it prints on stderr, such as an unknown value falling back to `auto`. A non-zero
exit reads as `auto`.

| Value | What runs | Read the venue? |
|---|---|---|
| `auto` (default) | each lane's local step runs only when its line below reads `local` | yes |
| `local` | every local review step, and the `tests` suites | no |
| `ci` | no local review step, whatever the script prints | yes, for the report only |
| `both` | every local review step, and the CI lanes still count | yes |

Below, a lane that "reads `ci`" or "reads `local`" means the lane's venue after the setting:
`local` and `both` make every review lane read `local`, and `ci` makes every review lane read
`ci`. The `tests` line follows the script under `auto`, `ci` and `both`, and reads `local` under
`local`.

## Read the venue

Run the bundled script, which changes nothing
([GitHub](../../../reference/providers/github/pull-request/review-venue.md)):

```bash
"<skill-dir>/scripts/review-venue.sh" [--repo <owner/repo>] [--max-age-days <n>] [--head <sha>]
```

Refuse a `--repo` value holding a character outside `A-Za-z0-9._/-`. It prints one line per lane,
`code-review` first, then `security-review`, then `tests` when `--head` names a full commit sha:

- **`<lane> ci healthy: <detail>`**: the lane's workflow is enabled and its newest pull request
  run that reached a verdict succeeded within the window. CI covers this lane. A run reaches no
  verdict when it was skipped, cancelled, or failed only because its pull request edits the
  lane's caller workflow (`skipped-validation`): that red says something about one pull request,
  not the lane.
- **`<lane> local absent: <detail>`**: no recent pull request run in the repository calls the
  lane, or the caller workflow is disabled.
- **`<lane> local failing: <detail>`**: that newest run failed, timed out or did not start. A
  usage-limit stop is a failed run, so it lands here.
- **`<lane> local stale: <detail>`**: no run with a verdict inside the window.
- **`<lane> local unreadable: <detail>`**: a page of the run listing the lane depends on was still
  incomplete after three reads, so the script cannot tell whether CI covers the lane.

The `tests` line reads that one commit, not the repository's recent runs. Its lanes are CI's test
jobs, the GitHub Actions check runs on the head whose name is `test` or starts with `test` followed
by `-`, `(` or a space. Per name, the newest run that did not skip is the lane's result, so the
skipped copy a label or body edit posts never hides a failure:

- **`tests ci healthy: <detail>`**: every test-lane check run on the head finished as success,
  skipped (a lane the change gave no work) or neutral, and at least one succeeded.
- **`tests local absent: <detail>`**: the head has no test-lane check run, every one skipped, or
  the head has more check runs than the script reads. A draft skips them, so a head pushed while
  the PR is a draft reads `absent`; a PR moved back to draft keeps its ready head's results.
- **`tests local pending: <detail>`**: a test-lane check run on the head has not finished.
- **`tests local failing: <detail>`**: one concluded otherwise, such as failure, cancelled or timed
  out.

The window defaults to 7 days (`--max-age-days`). Basis: judgment, long enough to span a weekend
of no pull requests, short enough that a lane broken for a week stops counting.

**Exit codes.** 0 read; 1 bad argument; 2 a forge read failed; 5 a prerequisite is missing. On any
exit but 0, treat every lane as `local` and report `review venue unread: <the script's message>`.
An unread venue never skips a review; only `review_venue: ci` does.

## Apply it

| Lane | Local step it decides |
|---|---|
| `code-review` | prep's one fresh-context review (§1.2) and the ready step's `code-review` |
| `security-review` | the ready step's `security-review` |
| `tests` | the ready step's `verify` suites ([ready-for-review.md](ready-for-review.md) §2.5.3) |

Under `auto`:

- **`ci`**, for a review lane: skip the local step. Report it as `skipped, the CI <lane> lane
  covers it: <detail>`.
- **`local`**, for a review lane: run the local step. Report it as `ran locally in place of the CI <lane> lane
  (<absent|failing|stale|unreadable>)`, or `ran locally, no CI <lane> lane` for `absent`.
- **`tests`**: [ready-for-review.md](ready-for-review.md) §2.5.3 owns the skip, its
  `--verify-local` and `review_venue: local` overrides and its report line.

Under the other values, every review lane gets one report line, naming the setting's level:

- **`local`**: `ran locally, review_venue local (<level>)`. The script does not run, so the
  `tests` suites run too.
- **`ci`**: `skipped, review_venue ci (<level>); the CI <lane> lane reads <the script's line>`. A
  lane line that is not `ci healthy`, or a script that exits non-zero, still skips the step: name
  the line so a person sees that no healthy lane covers it.
- **`both`**: `ran locally beside the CI <lane> lane, review_venue both (<level>): <the script's
  line>`. Findings from both venues go through the same verification.

Read the venue once per phase, just before the first review it decides: prep at §1.2, and the
ready step again at §2.5.3, since a lane can fail between the two. The ready step reads the
`tests` line once more, with `--head`, after its commit and before the verify gate. The venue is a
built-in skip like the docs-only skip: `pre_ready` and `--skip` still only remove steps, and a
person may run a local review anyway.

## What the venue does not settle

- **Merge evidence.** A local review is never merge evidence. Only the lane's own records on the
  pull request's head count, read by [readiness.md](readiness.md) and the merge gate.
- **One pull request's coverage.** The review lanes are read per repository, often before the pull
  request exists, so the venue cannot see that a lane skips this one (a fork head, a bot author the
  lane does not admit). The backstop is per pull request: monitor's B2 step and readiness Gate 5
  substitute a local review for a lane that produced nothing on the head, and name it on
  `Review lanes:`.
- **Findings.** The venue picks who reviews, never what a review found. Findings from either venue
  go through the same verification (prep.md §1.3) and the same reply discipline.
