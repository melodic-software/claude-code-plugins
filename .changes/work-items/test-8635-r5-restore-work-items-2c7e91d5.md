---
bump: patch
---

### Changed

- Fifteen eval cases held from the `evals.json` retirement ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)) are restored, with the owner's approval of graders widened after a failing smoke. Each widening accepts the reply the original regex wrongly failed (now a pass sample), and every near-miss fail sample still fails.
  - work-loop: `wl-stale-in-flight-pr-escalates`, `wl-pause-entry-latches-tripping-account`, `wl-bot-reply-not-objection` and `wl-single-pass-ends-at-cap`. Report lines may render as a bold label with a code-span value; the no-objection check counts only a row of its own; and "does not call `ScheduleWakeup`" is accepted.
  - work: `wk-merge-hold-passed-to-create` and `wk-ci-tidy-small-change-skip-shared-path`. A `--hold '<line ...>'` placeholder and "`--turns` is set to 18" are accepted.
  - attend-queue: `aq-flip-needs-no-class-label`. A denial phrased with "until" no longer fails.
  - decompose: `decompose-one-slice-per-behavior` (two numbered slices count as two) and `decompose-expand-contract-when-batches-land-green` (rejects the act of putting every migrate batch on the integration branch, not a mention of skipping expand-contract).
  - setup: `su-seed-schedule-infers-and-interviews`, `su-first-bind-skeleton-only-on-skip`, `su-check-populated-schedule-label-fails`, `su-check-zero-rows-label-info`, `su-apply-backfills-frontier-stamps` and `su-check-override-ignore-rule-before-file`. Verdicts on the next line, "skip marked RECOMMENDED", a `recurring` label row and a bare "backfill `apply`" are accepted.
  - Review fixes, each with the reviewer's example as a sample. `decompose-expand-contract-when-batches-land-green` drops its reject-the-act lookahead and keeps only the ordered expand, migrate, contract match, so replies that restate the request or premise pass; the complying near miss that uses all three words moves to the judge's samples. `aq-flip-needs-no-class-label` also treats won't, will not, stays, remains, keeps, gated and doesn't flip before "until reclassified" as a gate. `wl-bot-reply-not-objection` rejects the objection line anywhere, numbered, in a table or mid-line, unless no, not or without comes right before it. `su-check-override-ignore-rule-before-file` accepts FAIL on the next line only when neither line says INFO or PASS, so a FAIL on another probe's row no longer counts.
