# work-items

Prose for this repository's `work-items` plugin settings. The values live in
[`work-items.yaml`](work-items.yaml). `/work-items:triage --issue <n> --ci`, the intake lane's mode,
reads `## Triage rules` below beside its own rules: they add to the skill's, and never relax one.

## Triage rules

The intake lane runs `.github/workflows/intake-triage.yml`, and its scripted jobs read the verdict
these rules shape (`.github/scripts/intake-triage/apply-verdict.mjs` and `admit.mjs`).

- **Priority.** Exactly one: `priority: critical` for a red main branch, a security exposure or a
  lane that is down; `priority: high` for something that blocks the pipeline or queued work;
  `priority: low` for a cosmetic or docs-only change; otherwise `priority: medium`.
- **A done-when item a lane run cannot do** (a run on a named host or OS, a paid eval, a run
  repeated N times, a measurement over time, or a page on a host outside the issue lane's web
  access) is no reason on its own for `needs_human`, the `needs-human` label or the `intent` flag:
  triage the items a lane can check as usual. Admission routes host work to `host-run`, or holds the
  issue and posts the split itself. A `needs-owner-decision` or `needs-human` label holds only beside
  a flag on the `Flags:` line; the verdict job takes it off when the line is `none` and nothing else
  holds the issue.
- **Blocked by the issue lane's stop.** When the issue lane's latest stop comment on the issue is
  `blocked-by-issue` and names an open issue, list that issue on the `Blocked by:` line, unless that
  issue is itself blocked by this one.
- **Cost.** A charge a diff shows (IaC resources or SKUs, runner labels or cron schedules in
  workflows, model, effort or turn flags, new secrets) gets no `cost` flag, no `needs-human` and no
  `Cost:` line: the merge-time cost hold catches it after review. Spend drawn from a prepaid source is
  no charge either: model runs, lane runs and `claude plugin eval` passes bill the prepaid API keys,
  which do not auto-refill. Only a new or renewing charge (Actions billing, Azure, a key or plan that
  renews or auto-recharges) is cost. Flagged cost also takes the `needs-human` label, with
  `needs_human` false, so the comment is kept.
- **Cost decided.** When a comment whose first line is exactly `**Decision recorded.**`, by an author
  whose login does not end in `[bot]`, already covers the charge, write one
  `Cost decided: <what bills; the decision that covers it>` line in place of the `Cost:` line and set
  no `cost` flag. Write either line exactly in that shape, with no bold, list marker or other label:
  any other shape holds the issue.
- **Re-entry that still needs a person.** After a recorded decision, when the remaining work needs a
  person (spend, with `Flags: cost`, or a trust-boundary decision the recorded decision leaves open,
  with `Flags: security` only at the CRITICAL tier and `Flags: intent` otherwise), apply the
  `needs-human` label and keep `needs_human` false, even when open questions also remain, so the
  comment with the quote and new questions is kept. Work on a host or in an attended run is a done-when
  item a lane run cannot do, not a person, unless the recorded decision itself leaves that step to a
  person, which takes `needs-human` with `Flags: intent`.
