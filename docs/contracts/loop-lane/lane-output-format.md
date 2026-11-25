# Lane output format

The **lane output format** is the one shape for what a lane posts: a short part a person reads,
plus the lane-outcome record where the surface carries it. The **lane-outcome record** is only the
structured part, a JSON object after the `lane-outcome` marker and a space
(`.github/scripts/lib/lane-outcome.mjs:1`), defined by ci-workflows `docs/lane-outcome.md` and
adopted for every lane by
[ADR 0087](../../adr/0087-keep-one-public-safe-lane-record-for-every-lane.md).

Which lanes post, and what stops two runs from posting twice, is in
[`posting-lanes.md`](posting-lanes.md).

## Adoption

A lane adopts this format the next time its posting code changes for any reason. No change
rewrites every lane at once. A reviewer holds a changed posting path to this file, by the review
rule in [`docs/review/lane-output.md`](../../review/lane-output.md), and leaves
untouched paths alone.

## The shared shape

Every surface below uses the same order:

1. **Heading**: the lane and activity, as `<lane> / <activity>`, the name the check run already
   carries (`.github/scripts/pr-unblock/limit-stop.mjs:9`).
2. **Verdict line**: the first line under the heading says the result in plain words, a verb
   first: `Passed: no findings.`, `Stopped: usage limit, resets at 14:00 UTC.`,
   `Fixed: 2 failing tests, pushed abc1234.` A reader who stops here knows what happened.
3. **Bullets**: at most five, one line each, only what a person acts on or checks. Anything longer
   goes behind a link to the run, or in a collapsed `<details>` block where the surface renders
   Markdown.
4. **Record**: the lane-outcome record, on the surfaces that carry it, after the human part or in
   the field set aside for it.

Rules for the human part on every surface:

- No step-by-step narration of what the lane did. State the result and what it means.
- No repeated text: the verdict appears once per surface.
- Public-safe: no secret value, token prefix, email, hostname or machine path
  ([ADR 0087](../../adr/0087-keep-one-public-safe-lane-record-for-every-lane.md), decision 1,
  covers annotations, summaries, artifacts and comments).
- Plain American English, no emoji.

The limits below are our decisions, set well under GitHub's own limits so the text stays readable.
GitHub's hard limits are on the pages linked in each section.

## PR comment

**Holds**: a result a person on the pull request needs to see: a finding, a stop, a hold, an
answer to a question.

**Limit**: 15 visible lines and 1,500 characters, `<details>` content excluded.

**Structure**:

- First line: the HTML marker that names the writer, such as `<!-- post-merge-test-mutation -->`
  (`posting-lanes.md:38`) or `<!-- check-contract:linkage -->` (`posting-lanes.md:28`). A lane
  finds and edits its own comment by that marker.
- Then the heading, the verdict line and the bullets.
- Long lists (every finding, every file) go in one `<details>` block at the end.

**Record**: a comment does not carry the lane-outcome record. The record stays on the check run;
the comment is found by its marker.

GitHub limits: [REST API, issue comments](https://docs.github.com/en/rest/issues/comments).

## Check run

**Holds**: the lane's result on the head it ran against, the surface agents and dispatchers read.

**Limit**: `output.title` 72 characters; `output.summary` 10 lines.

**Structure**:

- `name`: `<lane> / <activity>`.
- `output.title`: the verdict line.
- `output.summary`: the verdict line again only if the title had to cut it, then the bullets.
- `output.text`: the records first, then a blank line, then any detail, as
  `.github/actions/report-check-run/report-check-run.mjs:117-120` writes it today.

**Record**: the first line of `output.text`, after the `lane-outcome` marker and a space, written by
`report-check-run` (`.github/actions/report-check-run/action.yml:80-89`) and read by
`.github/scripts/pr-unblock/limit-stop.mjs:7-13`. Readers read that line, not annotation text
([ADR 0087](../../adr/0087-keep-one-public-safe-lane-record-for-every-lane.md), Consequences).

GitHub limits: [REST API, check runs](https://docs.github.com/en/rest/checks/runs).

## Step summary

**Holds**: the run's result for a person who opens the run page. It repeats no comment or check
run text beyond the verdict.

**Limit**: 40 lines per job.

**Structure**:

- One `###` heading per job, naming the lane and activity. A job that appends several blocks
  writes the heading once (`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:1834`
  writes one `###` heading per run).
- The verdict line, then the bullets.
- A table only for rows a person compares (one row per item); a long list in `<details>`.

**Record**: a step summary does not carry the record.

GitHub limits: [workflow commands, adding a job summary](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands).

## Live step log

**Holds**: what a person reading a running or failed job needs to find the failing step.

**Limit**: 20 ungrouped lines per step.

**Structure**:

- One line per decision or result, not per call made.
- Command output, API responses and long listings go inside `::group::<title>` and `::endgroup::`,
  the title stating the result, as `.github/workflows/pr-merge.yml:199` does
  (`post-merge check: exit <code>`).
- An error or warning a person must act on is one `::error::` or `::warning::` line, so it also
  shows as an annotation. One per distinct problem, never one per retry.

**Record**: the log does not carry the record.

GitHub limits: [workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands).
