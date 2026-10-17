# Review venue (`review-venue`)

A change gets one AI review venue per lane. When the repository's CI review lane covers that lane
and is healthy, CI reviews the pull request and no local review runs for it. When the lane is
absent or unhealthy, the local review runs and the report names it as the stand-in for that lane.
This file is the one statement of that rule; [prep.md](prep.md) §1.2,
[ready-for-review.md](ready-for-review.md) §2.5.3 and any other skill that reviews before or at
the ready flip read the venue through it, never through a copy of its test.

## Read the venue

Run the bundled script, which changes nothing
([GitHub](../../../reference/providers/github/pull-request/review-venue.md)):

```bash
"<skill-dir>/scripts/review-venue.sh" [--repo <owner/repo>] [--max-age-days <n>]
```

Refuse a `--repo` value holding a character outside `A-Za-z0-9._/-`. It prints one line per lane,
`code-review` first, then `security-review`:

- **`<lane> ci healthy: <detail>`**: the lane's newest run that reached a verdict (finished, and
  neither skipped nor cancelled) succeeded within the window. CI covers this lane.
- **`<lane> local absent: <detail>`**: no recent pull request run in the repository calls the
  lane.
- **`<lane> local failing: <detail>`**: that newest run failed, timed out or did not start. A
  usage-limit stop is a failed run, so it lands here.
- **`<lane> local stale: <detail>`**: no run with a verdict inside the window.

The window defaults to 7 days (`--max-age-days`). Basis: judgment, long enough to span a weekend
of no pull requests, short enough that a lane broken for a week stops counting.

**Exit codes.** 0 read; 1 bad argument; 2 a forge read failed; 5 a prerequisite is missing. On any
exit but 0, treat every lane as `local` and report `review venue unread: <the script's message>`.
An unread venue never skips a review.

## Apply it

| Lane | Local step it decides |
|---|---|
| `code-review` | prep's one fresh-context review (§1.2) and the ready step's `code-review` |
| `security-review` | the ready step's `security-review` |

- **`ci`**: skip the local step. Report it as `skipped, the CI <lane> lane covers it: <detail>`.
- **`local`**: run the local step. Report it as `ran locally in place of the CI <lane> lane
  (<absent|failing|stale>)`, or `ran locally, no CI <lane> lane` for `absent`.

Read the venue once per phase, just before the first review it decides: prep reads it at §1.2, and
the ready step reads it again at §2.5.3, since a lane can fail between the two. The venue is a
built-in skip like the docs-only skip: `pre_ready` and `--skip` still only remove steps, and a
person may run a local review anyway.

## What the venue does not settle

- **Merge evidence.** A local review is never merge evidence. Only the lane's own records on the
  pull request's head count, read by [readiness.md](readiness.md) and the merge gate.
- **One pull request's coverage.** The venue is read per repository, often before the pull request
  exists, so it cannot see that a lane skips this one (a fork head, a bot author the lane does not
  admit). The backstop is per pull request: monitor's B2 step and readiness Gate 5 substitute a
  local review for a lane that produced nothing on the head, and name it on `Review lanes:`.
- **Findings.** The venue picks who reviews, never what a review found. Findings from either venue
  go through the same verification (prep.md §1.3) and the same reply discipline.
