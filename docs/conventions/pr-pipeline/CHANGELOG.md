# Changelog for the PR pipeline convention

## [8.27.5] - 2026-11-01

### Fixed

- The `address-feedback`, `review-dependency` and `fix-ci` activities pass `--unattended` to `source-control:pull-request` (`comments --ci --unattended`, `dependency --ci --unattended`, `ci --ci --unattended`), and the README example's `simplify` and `check-intent` activities pass it to `code-tidying:batch-simplify` and `verification:confirm`. A skill treats a run as unattended only when its caller passes the flag, and a lane run has nobody to answer an ask. The patch and mutate-branch runners' system prompt names `/discovery:research --unattended`. A live-config test fails when a lane activity calls a skill whose argument hint lists `--unattended` without passing it ([#11546](https://github.com/melodic-software/claude-code-plugins/issues/11546)).

## [8.27.4] - 2026-10-31

### Fixed

- `pr-feedback-dispatch.yml`'s `rerun-ci-status` job also re-runs a head's `ci-status` when a `pr-unblock.yml` run completes after setting or clearing a `pr-unblock/*` status on it, and when a person on the trusted-actor list approves it. Before, both changes waited for a hand re-run: the status is written with a `GITHUB_TOKEN`, whose events start no workflow, and no `pull_request` event fires on a review.
- The new `pr-review-approved.yml` relays an approving review of a same-repository pull request, with no permission, as a `workflow_run` upstream, so the re-run it causes is recorded for pr-verify's trigger gate.

- A thread a `review-threads.reviewer-ids` bot opened, with no trusted person's direction on it, is
  worked only when a trusted actor asked for that bot's review. Anyone can comment `@codex` on a
  public repository.
  - **An explicit request** is a `@codex` comment in an issue comment, a review comment or a review
    body, posted since the same bot's previous review. It must come from a person on the
    trusted-actor list. The bot's own text does not count.
  - **An automatic review** has no `@codex` comment and counts as asked for by whoever triggered it.
    That is the pull request's author on opening, or the actor of a ready-for-review event. Every
    such event in the window must be a trusted person's or the lanes App's.
  - Any untrusted request or event in the window leaves the thread for a person, and so does none
    that can be read. So do these, since each may have held a request:
    - an untrusted comment or review edited since the window opened, whatever it says now (review
      edit times come from GraphQL);
    - an untrusted comment that was deleted (GraphQL `CommentDeletedEvent`). The skip is logged as `codex-request-untrusted` or `codex-request-not-found`.
  - The select job, the reply job's re-read, `fix-ci-context.mjs` and `pr-feedback-dispatch.yml`
    apply the same check. `chatgpt-codex-connector[bot]` stays on `reviewer-ids`, and the
    trusted-actor list is unchanged.

## [8.27.3] - 2026-10-31

### Fixed

- Both review lanes (`review-code`, `review-security`) run on the `pr-review` profile at `opus`, effort `high`, in place of `sonnet`: they judge work the Opus profiles write, and no objective failure signal is on the head when their model is chosen (`docs/plugin-philosophy.md`, "Model tiers", rules 3 and 4). A test fails when either review route resolves to a model weaker than a route that writes code.

## [8.27.2] - 2026-10-31

### Fixed

- pr-merge's `clear-escalations` sweep now also removes `needs-session` after a push that mends the stop. That holds when the head is no longer any stop's head, the newest `pr-unblock/*` status for each stop's activity at the new head, if any, is a success, and its checks pass, not counting `ci-status`, which the label keeps red. Before, only a same-head retry lifted the label, and a session had to remove it by hand after a new head. A `dependency-workflow-unpinned` stop still comes off only on its own head. If the cause still holds, the lane stops again on the new head and labels it again ([#11200](https://github.com/melodic-software/claude-code-plugins/issues/11200)).

- check-wip-cap reads the queued `agent-ready` issues from the repository issues listing
  (`GET /repos/{repo}/issues`, open, oldest first) in place of the search API, whose results carry
  no recency guarantee, so parallel apply-verdict admissions count against a fresh queued count.
  Pull requests and the hold labels (`needs-human`, `needs-owner-decision`,
  `status: needs-decision`, `status: needs-info`, in any case) are left out client-side. A failed
  page, or one that is not a list, leaves the queued count unread (`admission_basis`
  `fail-open`), so intake admission admits nothing, as before. Past 10 pages one more issue
  counts as unlisted and admissions pause. The pull request searches are unchanged.
- Intake admission reads the racing admissions' `admission-deferred` listing before the
  `agent-ready` one. A run that adds `agent-ready` and then drops its claim between the two
  reads was missing from both, so a parallel admission could take one place past the room.
  The claim order is unchanged.
- Intake admission tests run `Promise.all` bursts of 2, 4 and 5 concurrent `admit()` runs
  against one shared fake GitHub with room 1, 2 and 3: no burst admits past its room, every
  shuffled burst admits, and a burst whose runs all read the room before any claim admits
  exactly the room.

## [8.27.1] - 2026-10-31

### Fixed

- `pr-merge`'s candidate listing no longer sleeps a fixed 15 s and 30 s or ends red on an outage.
  It runs through the new `.github/scripts/pr-merge/retry-call.bash`: at most three tries, waiting
  out a recorded rate stop or a capped, fully jittered backoff, within 60 s of waits in all. Each
  try also reads the open pull request count and fails when the listing does not match it, so a
  200 with items missing no longer reaches the gate. A listing still unknown ends the step green
  with a `::notice::` hold: the job gates, merges, re-fires and clears nothing, and the next
  scheduled run lists again. A listing that reaches its limit of 1000 ends the job red at once with
  no retry. The re-fire and escalation-clear steps skip on a red listing too.
- A held `pr-merge` run still writes the `pr-merge-summary` artifact, with `listing_held` and
  `listing_held_reason`, and its sweep cost line. It files, dequeues and merges nothing: the next
  run that lists records a failed lane merge and dequeues the lane's entries.
- `retry_call` repeats only a call passed `--read`; without it the command runs once, so a write
  is never repeated.
- `maintenance-monitor-signals` has a new signal, `12 listing held`: 4 scheduled or hand-started
  `pr-merge` sweeps in a row whose listing held raise a rolling issue. Signals 5 and 8 read the
  newest sweep that listed, and one over 70 minutes old for any reason is a gap for them, read as
  no sweep. Signal 3 counts a rate-limited hold still unbroken at the monitoring run.

## [8.27.0] - 2026-10-31

### Added

- `merge.dependabot.trusted-action-owners` lists action owners whose Dependabot bumps skip
  ci-status's trust-gate hold: a Dependabot pull request passes when every changed file is a
  modified workflow or `action.yml` and every change block only swaps the SHA ref of one `uses:`
  line of an action by a listed owner, to a commit a tag of that action's repository points to.
  Any other line, file, owner or ref keeps the hold, and an unreadable list fails closed. This repository lists `anthropics` (owner decision Q-ANTHROPIC-DEPS).

### Fixed

- `fix-ci-context.mjs` writes two more fields to fix-ci's context file. `spec` holds the linked issues' trusted spec text, read by pr-verify's `linkedIssues`. `feedback_lines` holds the non-blank lines the pull request's last address-feedback commit added. Before, fix-ci could cut a line that met a criterion just to get under a size cap, and pr-verify then failed the head on that criterion. On #10919 the two lanes undid each other until the verify-fail cap left the PR unarmed. Each field has its own byte budget so the file stays under the read job's 1 MiB limit. A field the runner cannot read whole, or that does not fit its budget, is `null`, never a partial list.

## [8.26.2] - 2026-10-31

### Fixed

- An issue parked at `status: confirmed` no longer gets `agent-ready` from work-unblock when its last blocker closes: that path never checked for `status: ready`, so a parked issue skipped admission. When a blocker closes after admission parked the issue, the lanes App now removes `status: confirmed`, once per close, and `intake-reenter` adds `needs-triage` and dispatches intake. An issue whose milestone is in the new `cordoned-milestones` list in `admission-rules.json` (`After zero`), whose author intake does not admit, that carries a refuse label, or that admission did not park stays where it is. Until a trusted `status: ready` follows that removal, work-unblock does not label the issue. `intake-reenter` ignores every other App removal of that label.
- A hold now replaces a parked `status: confirmed` instead of landing beside it. A refinement with open questions, a held verdict and a refusal for a person each take `status: confirmed` off after adding the hold, so one status stands and a listed human lifting `needs-human` re-enters the issue.

- `pr-verify` hands the final judge each chunk's output whole, in as many files as it takes, so a
  cut can no longer hide a delivered done-when item and fail a head on size. `notes_left_out` is
  gone from a chunk's result.
- `pr-verify` folds a diff line over 1800 bytes onto lines that start `\ continued:`, so a verifier
  reads every byte of it and no head passes on a line Read cut short.
- A `pr-verify` `fail` that hit a permission denial or holds credential-shaped text, a `pass` or
  `pass-notes` that holds a credential format, and any verdict from a judge step `run-claude-cli` failed
  on its own credential scan, is now written instead of leaving no verdict and a second sample of the
  head. A `pass` or `pass-notes` of that kind becomes a `fail` that counts toward the repeated-fail cap;
  one holding only a secret assignment, which may be a fixture, still leaves no verdict. Each publishes a fixed text and
  none of the model's, logs the credential's kind alone as a warning, and holds the pull request for a person with the
  human-gated label, a dequeue and a `security` stop reason, since a later clean commit rotates nothing. The verdict
  records `withheld: true` in code, so a fail quoting that text gets no hold and no model can claim one. The comment
  posts once per head and the label goes on in any pull request state, so a closed pull request that reopens stays
  held, whatever else the label stands for, and the comment keeps the label through
  `clear-escalations`, `enable-auto-merge`'s lift and `ci-status`'s cost-hold clear until a person removes it. A failed
  hold skips no notes, no fix round works past it, and a withheld fail stands on a short read with no
  notes or a scan stop that left no log. A denial alone still voids a `pass` or `pass-notes`. The scan
  reads through the
  `\ continued:` fold, with any white space before it, and across two quoted diff lines, and the prompts forbid quoting
  a credential.
- On a `refs` entry, a `pr-verify` final judge's `pass` or `pass-notes` needs the context read
  whole, in parts one Read returns, since the delivered part is named there. Chunk results over
  300000 bytes stop with no verdict before the final judge runs.

- A `pr-unblock.yml` or `pr-refine.yml` run sent by a dispatcher on an older copy of its file ends green before any model turn, with no check and no stop, and the next dispatcher sends the head again. The broker refused such a run's write tokens as `workflow-modified` only after the model had spent its turns.
- `fix-ci-dispatch.mjs` retries a head whose `pr-unblock / apply-patch` failed on a `lane-token-denied` refusal, under the same caps as a stopped run, in place of skipping it as handled.
- `report-escalation.sh clear` annotates a refused statuses read with `::error::` and gh's message and fails, in place of dying in jq at exit code 5 with no annotation.

## [8.26.1] - 2026-10-31

### Security

- `resolve-conflicts-select`, `address-feedback-select`, `review-dependency-select` and `fix-ci-context` in `pr-unblock.yml` fail on a PR whose head is in another repository, before it writes any head output, so a hand dispatch of a fork's PR posts no status on that head.

## [8.26.0] - 2026-10-31

### Added

- `mark-lanes`, `lint-repo`, `lint-shell`, `check-plugins` and `check-skills` now report their job
  token requests: `gh` runs through the api-budget wrapper in their steps, in the hygiene aggregator
  and in the Dependabot signature check, and each job ends with `api-budget` and `api-calls` notices.
  zizmor's online audits spend the token through their own client and stay uncounted.

### Changed

- `api_budget_emit` prints the last reading of each resource and reset, so a notice shows each core
  counter a job touched, not only the one its last call landed on. The job's latest core reading
  stays the last line.

## [8.25.1] - 2026-10-31

### Fixed

- The entry-hold check on a capped lane pull request and a queued lane entry counts a member's newest comment saying "do not merge", not any comment with blocking text, matching the arm path.

## [8.25.0] - 2026-10-31

### Changed

- `resolve-issue` lists `plugins/planning/scripts/repin-digests.sh` as a `verify-script`, so the
  issue lane can re-pin a planning interview digest without a host session. The script runs
  nothing from the checkout: it reads the test file and the files the test pins as data and
  computes each digest with its own base copy's helpers. `tests/repin.sh` also runs the test, so it
  stays off the list, and the pull request's CI still runs the test.

### Fixed

- `pr-verify` judges a diff of any realistic size. It splits a diff into as many chunks of at most
  300000 bytes as it takes, up to 12 (`MAX_CHUNKS` in `chunk-diff.sh`, which holds a 3 MB diff), each
  with its own judge step, and the head still passes only when every chunk and the final judge do. A
  file over 300000 bytes, or a diff that needs more than 12 chunks, still ends the run with no
  verdict and an error naming the file, or the diff's size and the chunk count.

- `pr-run-activity-read.yml` passes turns, max turns, models and profile to `report-check-run`, as
  the write runner does. A read activity that ended well has no failure class, so it posted no lane
  record at all, and its check run could not be read for turns or models.

## [8.24.0] - 2026-10-31

### Added

- pr-verify now gives the verifier `upstream-jobs.json`: the jobs of the pr-require-checks run it
  was started by, each with its name and conclusion, read with each judging job's own token. The
  verifier judges from it whether the suites that cover the changed files ran, as part of its rule
  on tests that do not cover the change, and runs no test or eval itself. The model's tool rules,
  `ci-status` and the verdict path do not change.

## [8.23.0] - 2026-10-31

### Added

- The half-hourly tick now picks up a fix request on a lanes App pull request. The
  `pr-feedback-dispatch` sweep sends a head with an unresolved thread the reviewer bot opened whose
  newest fix request, by a trusted person with write access, is newer than the head's newest
  `pr-unblock / address-feedback` check run; check runs that started before it stop counting for
  that dispatch, and a limit stop keeps its reset hold. `SWEEP_HEAD_CAP` still bounds the head, and
  no trigger, workflow or trust check changes.

### Changed

- The informational Windows and macOS test workflow is now `pr-test-platforms.yml` (was `pr-test-windows.yml`); the pipeline docs name it so.

- `merge.max-in-flight` is computed: `merge.in-flight-sizing` records the measured peak merge rate,
  time in flight and lanes App spend beside the formula, `scripts/compute-max-in-flight.py` prints
  the value, and a test fails any other. The measured day computes 11.

### Fixed

- A `security-risk` hold the issue lane reads from a run's words names the matched word in its comment, as inert text in a code span, so a person can dismiss a false hit in one read. Every hold, route and word in the list is unchanged.

## [8.22.1] - 2026-10-31

### Fixed

- The README's `verify:repeated-fail` rule now matches the reader. A merged pull request's FAILs,
  and a lanes App pull request's once it is closed unmerged, whoever closed it, no longer add to
  another pull request's count. Closing any other pull request resets nothing. Of the FAILs that
  remain, only ones uploaded after the newest capped-close record on at least one linked issue
  they are for count, and no other close moves that floor.

- A red-main run that posts no report, because its red is unconfirmed or the log already reports it, notes every unreported red full run on the log, so a report the repository-wide concurrency group cancelled while pending is named before the next confirmed red. The note counts as neither a report nor a cap decision and never creates the log issue.

## [8.22.0] - 2026-10-31

### Added

- The `skip-reason` enum gains `stop-resolved`. An address-feedback or fix-ci select job posts it
  where it finds the stop gone on its head, in place of `not-applicable`; `fix-ci-dispatch` reads
  it as a run with nothing to fix.

### Fixed

- The `stalled lane stop` signal now counts only a `stop-resolved` skip as ending a stop, so a stop
  a person clears by hand drops off at the same head, while an owner's untaken threads or a fix-ci
  skip before checks settled no longer read as resolved. It no longer lists the head's checks.

- `pr-verify` no longer fails a pull request on the size of its diff. It splits a diff at file
  boundaries into up to 4 chunks of at most 300000 bytes, each file whole, and each chunk gets its
  own judgment against the same spec, reading every part of its chunk whole. The head passes only
  when every chunk does. A chunk's `fail` stops the later chunks and is written at once, so nothing
  after it can lose it to a re-run. A judge reads another chunk's part when its change references a
  file there. A head of two chunks or more also needs a final judge with no diff, which reads the
  spec and every chunk's result and fails a done-when item no chunk delivers; without its output
  there is no verdict. A chunk
  that fails, leaves no verdict, skips a part or hits a permission denial leaves no verdict for the
  head, so a `pr-verify-failed` label stays. A file over 300000 bytes, or a diff that needs more
  than 4 chunks, ends the run with no verdict and an error naming the file or the chunk count.

## [8.21.0] - 2026-10-31

### Changed

- `merge.diff-check.floor-paths` returns with a new shape: class-tagged rows (`glob`, `class`, and on a `gate` row an optional `author-lift: false`), joined to the built-in path floor. The plain-string list the key held until it was removed fails validation, and a row the loader cannot use turns the rung off. This repository's own floor paths move there, and its effective floor is unchanged.

### Fixed

- A `pr-verify` run the lanes kill switch stopped now gets its re-run on the first reconciler pass
  after the switch lifts. `maintenance-reconcile-lost-runs` placed every pull request's CI set
  before any lane run and took lane runs oldest first, so flake re-runs used the three places and
  the few left went to runs of pull requests that had already moved on. A green lanes App pull
  request sat on `verify:missing` until someone re-ran `ci-status` by hand. Lane runs now go after
  every set except a flake-only one, newest first. The deferral note no longer says
  `3 re-runs in flight` when this pass's own placements took the places.

- The lost-run reconciler now re-runs a hosted review run a kill switch stopped, recorded, once
  neither the lanes switch, the lane's own switch nor the upstream gate would stop it again. Its
  completion re-runs ci-status, so a head a review switch left red clears without a person. One
  lane per head per half-hourly pass, up to GitHub's 30-day re-run window.

## [8.20.0] - 2026-10-31

### Added

- The monitoring lane reads the lanes App's own REST quota from lane runs. `request-lane-token`
  reads an optional `rate_limit` object (`remaining`, `limit` and `reset` in epoch seconds) from
  the broker's token 200 and writes an `api-budget` notice,
  `mint lanes-app core remaining=R used=U limit=L reset=<ISO>`, and a job summary line. With no
  `rate_limit` it writes nothing more; a malformed one warns `lane-token-quota-unread` and the
  step still passes. The monitor's new `lane api budget` source reads that notice from up to 10
  completed lane runs in the window and up to 10 jobs whose mint step succeeded. It reads only
  runs of this repository's own head on an event that runs the default branch's workflow code (a
  push or dispatch only on `main`), skips the test-suite runs, and leaves a trusted pr-merge run's
  merge job to the pr-merge source. Signal 2's `ceiling:lanes-app-rest` flags a reading over 90%. The
  broker half is tracked in melodic-software/azure-iac#103.

### Changed

- `pr-merge.yml` no longer wakes on a pull request's `edited` or `ready_for_review` event, which over a day started 200 runs that enqueued, merged and disarmed nothing. A person's ready or rename restarts their pull request's idle clock, an event run never arms, and `ci-status` already fails on a body hold; the 15-minute schedule picks up each such change. `unlabeled` stays, because `pr-feedback-dispatch.yml` starts on that run's completion.

### Fixed

- work-unblock closes a split parent as completed only when every sub-issue closed as completed
  and the parent's done-when is covered. A sub-issue closed as not planned, as a duplicate or with
  no reason leaves the parent open, and so does a split record that leaves an item out, a split by
  hand with no task list, or an open task item in a listed human's comment on the parent.
- The lanes App's close of a split parent counts as done for what it blocks only under that same
  rule (`admit.mjs` `splitLeftOpen`).
- work-unblock's sweep sends a parent with no open sub-issue through admission even when GitHub's
  sub-issue summary still shows a wait, so a parent with a duplicate sub-issue gets its one
  admission note instead of a stale wait.

- The dispatchers' FAIL-cap reads take the run records, run heads and head refs pr-merge carried,
  fetched with its listing on the job's first read. Without them each read asked GitHub about
  every FAIL in the repository (458 on 2026-10-31, 1,252 reads), was killed at its 120 s
  limit with no answer after spending 119 to 188 calls, and let the fix round run. Those reads
  were 92% of the heaviest `pr-unblock-dispatch` run's calls. Reads now finish, so a pull request past
  the FAIL cap gets no round from these reads.

## [8.19.1] - 2026-10-31

### Fixed

- pr-merge's `clear-escalations` sweep removes `needs-session`, with no comment, once a same-head
  retry cleared the lane stop that added it: the lanes App added the label last, and each stop
  routed to it since then has a `success` status newer than the stop on that stop's head. A person's
  label, a stop whose failure still stands, or an unread status keeps it. The sweep reads at most
  five pull requests a run, from a rotating offset. The `merge` job gains `statuses: read` for this.

- The lost-run reconciler now records each hosted review run it re-runs after an upstream stop, as
  `reconcile-rerun-<run id>-2-<head>`, before it re-runs it. A pass uploads at most three records,
  so a PR or lane run whose records would pass that waits for a later pass.
- ci-status's upstream-stop message now says the review's dispatch re-runs ci-status under that
  record, and a person re-runs it only if that re-run does not come.

- `test-python`'s suite step prints a per-run nonce, repeats it in each suite's call line, and
  prints an exit line carrying it after each suite. The post-merge demotion judge reads only those
  lines, so a suite's captured output cannot move a failure onto another suite. The nonce sits in
  a variable no suite inherits.
- The quarantine rule in the convention README states what excuses a repeat failure, how a
  quarantine restarts, what an edited issue does, and that a token without `Actions` read cannot
  name a suite, so the failure demotes.

## [8.19.0] - 2026-10-31

### Changed

- **The issue lane's `research-first` and `probe-first` skips reach no person.** They take a new `park` route in `stop-routes.json`: the lanes App writes admission's comment naming the next step, adds `status: confirmed`, and removes `agent-ready`, `status: ready` and `admission-deferred`, as admission parks the same refusal, so a listed human's `**Decision recorded.**` comment sends the issue back through intake. The lane comment carries an `outcome=parked` marker. `split-required` keeps its `intake` route to intake's size split (owner Q93). Admission's comment helpers moved to `.github/scripts/lib/admission-comment.mjs`, which admission and report-outcome share; the hold floor lists it as an enforcement path.
- **Only a credential-shaped patch holds for a person.** apply-patch escalates a credential shape in an issue patch or a patched blob as the new `patch-credential` reason, ahead of every `-invalid` refusal (a SHA-256 mismatch, an extra file beside the patch, a symlink, the path count, a blob's size; a patch made on another commit; each blob is read whole before its size is refused), with the token shapes of the read runner's scan job (`lib/publish-gate.mjs` `CREDENTIAL_SHAPES`, which apply-patch copies under a test that fails when they differ; a blob too large to read counts as carrying one), and the issue lane holds it as `security-risk`. Any other `patch-invalid` now retries like `patch-apply-failed`. Rows other than `issue` keep escalating their `-invalid` reason for a credential shape.
- **A patch not proven clear of a credential holds; a scan fault retries.** An issue patch refused or unapplied with a `GIT binary patch` line escalates `patch-credential`, since no scan read its blobs, and a text-only one stays `patch-invalid` or `patch-not-applied`, on the moved-head branch too. The read runner's carry step runs `lib/publish-gate.mjs` `scanLeak` on a patch over its cap before removing the copy, and only a clean result is refused `patch`, which retries; a block, a binary hunk or a failed scan is refused `output`, which holds. `report-outcome` holds on `patch-credential` and `scan-refused-output` on any exit and ahead of any funding, limit or turn-cap record. A patch that does not apply to the scanned head and an unfinished scan write the new `fault` marker, which routes `scan-refused-fault` to retry under `limits.stop-retries`, only once the patch's text was judged with no binary hunk's bytes unread, or when the run left no patch; a throw before the judge holds, the scan step retries a 5xx from its gate calls so a blip does not, and a credential hit stays a hit when a later scan step throws.

### Fixed

- pr-unblock's address-feedback: a `claude[bot]` review finding with no review lane footer is ruled as a code-review finding. A disputed one (`INCORRECT`, `UNCERTAIN` or `VALID-defer`) goes to the adjudicator instead of `feedback-disputed` or `feedback-uncertain`. Past the round cap it gets the fresh fixer's round and then fails the head as `feedback-not-converging`, with no `needs-human` label. A footer in its body is model text, so it still names no lane. A `claude[bot]` finding whose own text names the security-review lane or holds a rating-shaped line, rated `CRITICAL` or with no rating the lane reads, keeps that lane's hold (`claimsSecurity`). A disputed finding with a `CRITICAL` rating line goes to a person, as a code-review one does, and that line now counts in any rating shape, bold or with trailing text. At the round cap, a `claude[bot]` finding a person directed gets the fresh fixer's round, as a code-review finding does, unless `claimsSecurity` holds it. Before, any `claude[bot]` finding held there.

- pr-feedback-dispatch's tick now recovers a run whose `dispatch` job failed after it started, as it
  already recovered a cancelled, timed-out or never-started one: runs 41151634518 and 41151650975
  failed on `fetch failed` for #11344 and nothing sent their round again. Each failed or lost run
  sends at most one round per pull request: a finished `pr-unblock` address-feedback run for the
  pull request created after it holds that pull request, read from every run created since. A
  failed run is retried for 2 hours, since a dispatch the API rejects starts no round to end it.
- A pass-only address-feedback round is no longer stranded when pr-verify's FAIL cap cannot be read
  (`verify:unreadable`, as on #11354). It skips only on a cap the reader found; the deadline
  warning is still logged. A FAIL or review round still skips on an unreadable cap.

- **A trusted size-split child admission takes at Size large is no longer skipped as `split-required`.** `trustedSplitChild`, which feeds the issue lane's `split-child` fact, applies `splitChildBody` exactly as admission does; it no longer also refuses a child whose parent body someone else last edited when the child's lines come from a listed human's comment.

- pr-feedback-dispatch.yml's rerun-ci-status records the ci-status re-run that a review run's
  attempt 2 causes when github-actions[bot] started that attempt and the lost-run reconciler's
  `reconcile-rerun-<run id>-2-<head>` record passes check-trusted-trigger's own reconciler check
  (`reconcilerRecordVouches`, run through `reconciler-record.mjs`), so pr-verify's trigger check
  accepts that ci-status attempt. Attempt 3, another re-runner, or a missing or refused record
  still records nothing.

## [8.18.5] - 2026-10-31

### Changed

- **`pr-merge-dispatched-*` artifacts now expire after 30 days instead of 90.** The post-merge check reads these records only back to its floor, and its run listing goes unreadable at 1000 dispatch runs, about 19 days at the current rate, so the rest of the 90 days was dead weight: over half of the repository's artifacts, paid for on every full listing. The other 11 days cover a stopped check. A record that expires early fails closed: it can hold the lane or demote, never verify a merge. Artifacts already uploaded keep their 90-day expiry.

## [8.18.4] - 2026-10-31

### Fixed

- The dispatchers' FAIL-cap read waits and reads a carried artifact listing again when it misses
  GitHub's live count, instead of going straight to a whole listing that no longer fits in
  `verify-cap.mjs`'s 120 s limit. A miss of 2 on #11354 otherwise ended a round in
  `verify:unreadable`. The reader's waits stop at the caller's limit, and a miss that outlasts
  them still refuses, after which the job's later FAIL-cap reads skip the waits, so one job spends
  them once instead of about 50 s per pull request.

- The upstream-status gate skips a lane run only while GitHub Actions or npm Package installation
  lists `partial_outage` or `major_outage`. `degraded_performance` and `under_maintenance` now run.
- A hosted review run the gate skips now fails its `kill-switch` job at `Stop on upstream status`,
  and pr-review-main's legs fail the same way, so each is a failed first attempt. The lost-run
  reconciler re-runs a hosted review run's failed jobs once, only for that stop and only while
  the gate would let it run; any other failed or lost review run is still left alone, and a
  main-run review's re-run also waits while the gate would skip it.
- ci-status names a review the upstream gate stopped, and an older run's gate-skip notice, instead
  of reporting a fork or an unlisted bot. For the stop, it asks a person to re-run ci-status once
  the reconciler's review re-run passes, so pr-verify accepts that attempt.

## [8.18.3] - 2026-10-31

### Fixed

- A post-merge demotion or failure record now says why it lists no range: main's runs could not be
  read, no green full run came first, the compare could not be listed, the range passes 300
  commits, the first-parent walk missed the base, or the last green run is at the failing commit,
  which implicates no merge. A failed read also emits a `::warning::`. Compare is paged, so a range
  past GitHub's 250-commit limit is walked, and the record lists 100 commits with an "and N more"
  compare link. A direct push is called one, its subject is quoted without backticks and cut to 100
  characters with its backslashes intact, and a commit with no GitHub login reads `unknown`.

### Security

- The write runner's skill step sets `GH_TOKEN` and `GITHUB_TOKEN` to empty in its settings' `env`, so no Bash process holds the effect-scoped App token in its `/proc/<pid>/environ`, the sandbox's pid 1 and the Bash shell above a `verify-scripts` wrapper included. claude-code-action's MCP servers, commit signing among them, still get the token from their own config `env`. Under run-claude-cli, code a listed script runs can still read the job's read-only token from an ancestor ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#skill-activities)).

## [8.18.2] - 2026-10-31

### Changed

- pr-feedback-dispatch.yml and pr-unblock-dispatch.yml no longer run a step that fetches pr-merge's
  carried artifact listing on every run. `verify-cap.mjs` runs `listing-carry.mjs` (provenance
  checks unchanged, the same 2-minute limit and its own api-calls notice) on the job's first
  FAIL-cap read only, so a run that skips before any FAIL-cap read spends none of the carry's
  calls. A failed fetch warns, and the reader lists every page as before.

### Fixed

- `ci-status` no longer tries to turn off an armed pull request's auto-merge on a push: turning
  it off needs `contents: write`, which the lanes App's arming token holds and `ci-status`'s
  `GITHUB_TOKEN` deliberately lacks, so the mutation could not succeed. The merge queue's check for
  a pr-verify pass at the exact head it merges is what holds a new head.

## [8.18.1] - 2026-10-31

### Fixed

- Only a `CRITICAL` security finding holds a pull request for a person, as the owner decided on
  #11020. In pr-unblock's address-feedback, a disputed `IMPORTANT` security-review finding goes to
  the adjudicator instead of `feedback-disputed`, and one the fresh fixer's round leaves open fails
  the head as `feedback-not-converging` instead of `feedback-round-cap`. A `dependencies` flag
  rated below `CRITICAL` that `hardRequire` does not settle ends `feedback-unadjudicated`, a
  failing status. pr-merge's `clear-escalations` no longer keeps `feedback-not-landed` for an open
  `IMPORTANT` thread; a `CRITICAL` or unreadable one still keeps it.

## [8.18.0] - 2026-10-31

### Added

- `merge.verify-capture` configures pr-verify's evidence capture: `app`, the app it drives (unset: no capture runs), and `retention-days` (default 30, at most 90) for each capture artifact.
- Every verdict file records an `evidence` block: the capture's outcome (`no-app` when no capture summary exists, `blocked` when one cannot be read) with its reason, capture count and features, and `local_loop`, the author's count from an `Evidence loop: k/3` line in the trusted pull request body, read as data and `null` without one. A capture never fails the verdict.

## [8.17.0] - 2026-10-31

### Added

- **A push to main that reverts a pull request the lanes App put in the merge queue now demotes that lane.** `post-merge-demotion-alert.yml` reads every commit each canary push run brings (up to 20), whatever the run concluded, for a `Reverts #N` line, a revert-button subject, `This reverts commit <sha>` or the red-main bot's culprit marker, and files a `babysit-merge-demotion` record with signal `revert`; babysit makes no unattended merge while it is open, and only a person closing it re-enables the lane. A revert of a pull request a person queued files nothing, and a revert commit an existing record lists is never filed again.

### Fixed

- The dispatchers' FAIL-cap reader (verify-cap.mjs) now runs as an async child process, so it no
  longer blocks the event loop. While it blocked for a minute or more, a reset on the job's idle
  connection to GitHub went unread. The address-feedback dispatch POST then went out on the dead
  socket and failed with `fetch failed` (ECONNRESET), so no round was sent or recorded. A reader
  past its 2-minute limit is still killed and read as not the cap.
- feedback-dispatch.mjs sends the dispatch POST once more when its connection broke before any
  answer (ECONNRESET, UND_ERR_SOCKET), unless a run that POST started is already listed for the
  pull request. An HTTP error answer is never sent again. A failed run's error line now names the
  cause code.

## [8.16.0] - 2026-10-31

### Added

- pr-merge's re-fire step (`refire-refused.mjs`) now also pushes an empty commit for a pr-unblock `address-feedback` run whose "Request the lane token" step failed transiently: `broker-unreachable`, or `lane-token-denied` with a 5xx status. The `pr-unblock-dispatch` tick does not dispatch that activity, and its failed check run holds the head, so such a run stranded the pull request until a person re-fired it. The activities that tick dispatches (resolve-conflicts, review-dependency, fix-ci) are left to it, and a token 403 is re-fired only for `workflow-modified`, as before. Each transient re-fire is recorded in a `<!-- pr-lane-refire transient run <id> tree <tree> head <head> -->` marker and capped at one per failed run and two per head tree, so a broker outage cannot chain empty commits on one change.

- The monitoring lane has signal 11, post-merge unreadable: when the newest 4 post-merge reports that `pr-merge`'s `post-merge-dispatch` kept all exited 3 (the check could not read lane merges, so merges hold with only a warning), it files or reopens one rolling issue naming the newest report's reason, and each monitoring run prints it as an `::error` while it holds. It only notifies, and the next readable report closes it. No report within 70 minutes leaves the signal unread rather than clearing it.

### Changed

- The cost hold section names the infrastructure-as-code files the merge gate now holds:
  - Pulumi project and stack files in their `.yml` and `.json` forms.
  - `*.tf.json` and `*.tfvars.json`.
  - The ARM template names `azuredeploy.json`, `azuredeploy.*.json`, `*.azuredeploy.json` and `*.azuredeploy.*.json`.
  - Any file under a directory that holds a Pulumi project file.

  It also says why a `secrets` reference moved within one file is accepted: the move adds no
  charge, and where it moved is the review lanes' call.

## [8.15.5] - 2026-10-31

### Changed

- "Dependabot pull requests" and the review-dependency activity no longer list the `[dependabot skip]` version-bump commit as an allowed commit: every commit must be Dependabot's or, after a review, the lanes App's fix commit, and a `github-actions[bot]` push is refused (`pushed-by:github-actions[bot]`).

## [8.15.4] - 2026-10-30

### Fixed

- `clear-escalations.mjs` lifts a stale review-lane hold when an unresolved review thread is at
  IMPORTANT: only a CRITICAL thread, or a strict lane's thread with no one readable `severity:`
  line, keeps the hold, as the merge gate already reads a review finding. A high path refused by
  pr-merge's risk score gets the lanes' comment and no `needs-human` label (owner decision
  2026-10-30, #11020). The README's `stale-review-hold` row and its lists of the reasons only a
  person clears say so.

- In the merge queue, `ci-status` reads the counted pass's `verdict.json` again after 5, 15 and 30 s
  when GitHub answers a 5xx or the request gets no response; any other failure still fails at once.
  Three 503s over 26 s failed merge-group run
  [41063238235](https://github.com/melodic-software/claude-code-plugins/actions/runs/41063238235)
  under the old 5 and 10 s waits.
- The cold-read headroom check works out a cold read's cost from the live artifact listing, its
  `total_count` and the FAILs it lists, plus that listing's own pages, in place of a fixed 1,546 sized for 77 pages and 793 FAIL
  reads. A listing that does not read holds the pull request.
- `enable-auto-merge.mjs` (verifier reads and `capped-close`) and `verify-cap.mjs` tell the verdict
  reader the limit they kill it at (240 s, 30 s for a kept-answer lookup, 120 s), so a listing that
  cannot finish in that time refuses with the pages, the budget and the caller named rather than
  ending as a bare `verify:unreadable`.
- `verify-cap.mjs` skips the address-feedback or fix-ci round, for that run only, when the
  reader's listing does not fit in its 120 s, as it does when a sibling FAIL run cannot be read:
  either may hide the FAIL cap. Any other refusal still lets the round run, now with a warning
  naming the refusal and its detail instead of none, except `verify:fail` on an address-feedback
  round sent for that FAIL, which expects it.
- `verify-cap.mjs` logs one line per read summarizing the reader's stderr, its
  `babysit-listing-miss` lines first, so a listing that missed GitHub's live count shows in the
  dispatch job's log.
- The address-feedback and fix-ci dispatchers annotate a skip for a listing that does not fit in
  `verify-cap.mjs`'s limit as `::warning title=verify-deadline-skip::`, with the reader's detail,
  since that skip recurs every run while pr-merge's carried listing is missing or stale.

## [8.15.3] - 2026-10-30

### Removed

- ci-workflows' `pr-require-checks-trust-paths` hold no longer runs here, by owner direction (trust-path holds come off): its caller workflow and its JSON config are gone, and `scripts/sync-hold-floor.py` no longer writes the config. `merge.trust-path-hold-apps` still feeds ci-status's inline hold.

## [8.15.2] - 2026-10-30

### Changed

- pr-verify's `check-intent` hands its resolved pull request, spec and trusted PR text to
  `check-intent-subscription` in one `reads` job output, written before the model runs, so a
  handoff no longer repeats the resolver's and select-trusted-text's reads. The subscription job
  still runs the trigger gate, whose head must match the carried one, and reads everything again
  when the output is missing, malformed, too large, or from another run attempt.

### Fixed

- The issue lane holds a `pushback` only for a hold code (`security-risk`, `cost-risk`,
  `design-change`, `intent-change`) that opens its reason or names its cause, or for
  `"cause": "intent"` or `intent-change`, a cause read in any case, full-width letters included,
  with spaces, underscores or hyphens between its words and a trailing `.`, `:` or `;`. A reason
  that only mentions a security word no longer holds as `security-risk` on the first pushback; a
  reason opening with a `host-run` or `attended` code takes that row, or the `security-risk` hold
  when it names a security risk after the code. The rest are `pushback-means`, which goes back
  through intake triage once, where intake's own intent, security and cost rules still apply; one
  whose reason, summary, not-done item or cause names a security risk gets an intake comment with
  no means framing, marked `security`, which holds as `security-risk` once that intake round is
  spent; the mark does not carry over to later runs, since intake triage re-judged it first.

## [8.15.1] - 2026-10-30

### Fixed

- **The README now says how a held Dependabot pull request is released.** ci-status's trust-path hold on a Dependabot pull request clears when a person on the trusted-actor `human` list approves the current head; a new push needs a new approval, and `ci-status` is then re-run, since a review does not re-run it. The README no longer calls the admin bypass a break-glass, since the ruleset requires ci-status and the merge queue even for an admin merge.

- A Size Large issue whose sub-issues are all closed but which is still open is refused at admission (`status: confirmed`) instead of parked as "split pending" on every hourly sweep. work-unblock now closes finished split parents before it re-runs admission, so a parent whose last sub-issue just closed is closed rather than refused.
- A split parent's admission comment no longer keeps saying the split is pending once sub-issues exist. When a sub-issue closes, work-unblock rewrites that comment to name the open sub-issues. The hourly sweep also rewrites it for one twenty-fourth of the waiting parents, chosen by issue number, so each is checked once a day.
- A parent split by hand now closes as completed once its sub-issues are done, when each unticked task-list item in its body cites one of its sub-issues as `#N`. An uncited item still keeps it open.

## [8.15.0] - 2026-10-30

### Changed

- **pr-verify PASS and PASS-NOTES artifacts now expire after 7 days instead of 30, unless the pull request's body or issue links changed since its head commit.** Such a pass is read only at an open pull request's current head, so outliving that head is dead weight in the repository-wide artifact listing; a pass that expires on a held head fails closed as `verify:missing` and the next push, edit or label has pr-verify judge it again. A pass judged after a body edit or link change may supersede a FAIL at its head, which the merge gate still reads at a later merge-only head, so it keeps 90 days like the FAIL. FAIL verdicts keep 90 days for the 80-day look-back. The `pr-review-main-*` row records why its 90 days stay for now.

- The read runner's `broker-check` job holds `issues: write`. In issue mode, after the broker's allow, it claims the issue with a lease comment held by the lanes App identity before any model turn; a live older lease makes the run exit `already-leased` with no model turn. A new `lease-release` job releases the lease once every other job of the run ends, unless the caller passes `caller-releases-lease: true`. `work-resolve-issue.yml` does, and its `release-lease` job releases the lease after the PR opens and the outcome is reported, so no local loop takes the issue in between.

## [8.14.0] - 2026-10-30

### Added

- `merge.refire-skip-branches` (default `[]`): head branches a workflow owns and rebuilds. pr-merge's re-fire step never comments on or pushes an empty commit to a pull request from one of them. This repository lists `release/plugins`, which `release-publish-plugins.yml` rebuilds. Skipping another owned branch takes only a config edit.

### Fixed

- pr-merge's re-fire step (`refire-refused.mjs`) now reports a pull request that changed since the listing, or whose branch a fresh read shows moved or deleted after a 409 or 422 on the ref update, as a `::warning::` for that pull request, and the other pull requests still re-fire. A pull request whose push has not landed an hour after its marker is a `::warning::` too, so a person looks. Before, one 422 on `release/plugins` failed the whole merge job (run 41065454536). Any other failure still fails the step: any error on the new commit, a 409 or 422 on a ref update whose branch is still at the head it was read at or whose tip cannot be read again, an auth refusal or server error on a write, a failed run, comment or blob read, a setup error, or a failed run listing. The step ends with a `refire-refused: outcome re-fired=N failed=N skipped-owned=N deferred=N` line in its log and step summary.

## [8.13.0] - 2026-10-30

### Added

- The log-api-budget action has a `calls` output, `<name>-calls=N` for each named token, taken from
  its api-calls line: the job's own requests.
- These jobs now end with the log-api-budget step and name `API_BUDGET_TOKEN: github-token`, so each
  run carries an api-calls line:
  - pr-unblock.yml: the not-run jobs, `conflict-scan-refusal`, `fix-ci-unreported` and
    `report-stop-status`.
  - pr-review-hosted.yml and pr-review-security-hosted.yml: `resolve-model` and `kill-switch`.
  - pr-run-activity-read.yml: `broker-check`, `issue-fields`, `summary` and `report`.
  - pr-run-activity-write.yml: `report`.

### Changed

- pr-merge's sweep line reports the job's own request counts,
  `sweep-calls=N github-token-calls=M candidates=… reached=… skipped=…`, in place of
  `sweep-cost=… github-token-cost=…`. That was the rise in a counter every concurrent job shares,
  which the action documents as not the job's cost.

- pr-feedback-dispatch.yml and pr-unblock-dispatch.yml restore the artifact listing pr-merge's last
  scheduled or hand-started run on main saved (`listing-carry.mjs`, its provenance checks unchanged)
  and set `BABYSIT_VERIFY_LISTING` and `BABYSIT_VERIFY_LISTING_CARRY` for the FAIL-cap reader, as
  pr-merge.yml's gate does. The first pull request's read lists only the pages since the carried
  listing, and later ones reuse or extend the job's saved listing, instead of each read listing every
  artifact of the repository. A listing that does not hold GitHub's live artifact count is still
  dropped for a full read.

### Fixed

- verify-cap.mjs runs the FAIL-cap reader with `BABYSIT_VERIFY_NO_INCREMENTAL_WAITS=1`. Before this,
  the 15 s and 30 s waits after a missed incremental read, plus the whole listing after them, could
  run past the reader's 2-minute kill. verify-cap reads a killed reader as not the cap, so a round
  could start on a pull request that was already at `verify:repeated-fail`.
- The log-api-budget action's `calls` output reports `unknown` in place of an empty count when the
  job has no api-calls line to read (no `RUNNER_TEMP`).

## [8.12.0] - 2026-10-30

### Added

- The report jobs of `pr-run-activity-read.yml` and `pr-run-activity-write.yml` post one comment
  per lane run on the PR, edited in place on a re-run, listing the activity, its outcome, the
  commits pushed and each GitHub API call the run job's scripts saw fail, by path and status.

## [8.11.0] - 2026-10-30

### Changed

- **A red-main demotion record clears once main is green at a later commit.** The Demotion issue section now states that a `schedule` or `dispatch` record no non-human edited stops holding the rung once a newer attempt-1 green `pr-require-checks` run on main sits at a commit ahead of its SHA and on main's history; canary and read-back records stay human-close (#11262).

- pr-unblock holds a pull request for a person only for the owner's three reasons, and queues the rest for a session builder

  `escalation-routes.json` now routes `hold` (`needs-human`) only for an intent or design question, a person's own thread or hold, and a HIGH or CRITICAL security risk: `feedback-question-*`, `feedback-uncertain`, `feedback-disputed`, `feedback-round-cap`, `dependency-security-close`, `dependency-escalate` and `dependency-fix-refused`. The protected-path stops (`protected-path-conflict`, `conflict-patch-protected-path`, `feedback-protected-path`, `ci-fix-protected-path`), `ci-fix-weaken-required` after its fresh fixer round, `ci-fix-escalated` (a check the `fix-ci` rung-up retry could not fix), and the other review-dependency stops route `fail` with `"label": "needs-session"`: `report-escalation.sh` adds that label before its lane-stopped comment and posts the failing status, and no merge gate reads the label. `review-dependency` and `apply-dependency-patch` do not apply while `needs-session` is on, so a dependency stop gets no same-head model re-run and no fresh round budget on a rebased head until a session removes the label. A well-formed reason the table does not list now holds for a person instead of failing the job.

- pr-unblock's adjudicator settles an intent or design question for the reviewer from the work item contract

  The adjudicate-feedback job stages the linked issues' spec text that pr-verify reads (`resolve-pr.mjs` `linkedIssues`, now exported) as `contract.json`. A reviewer verdict on an intent or design question must carry a `quote`; the script keeps it only when it is an exact substring of that text, at least 20 characters, and the reply quotes it with the issue's URL, so the finding stands for the next fix round. A quote never dismisses a finding: a lane verdict on such a question goes to a person. Any other quote, or no spec text, leaves `feedback-question-intent` or `feedback-question-design` a person's. A security question, a CRITICAL finding and a security-review finding rated `IMPORTANT` or above never settle by quote. The job gains `issues: read` and `pull-requests: read`.

### Fixed

- `collect-patch.sh` writes an exact rename (100% similarity) as a rename header, so a moved file
  no longer counts its whole content twice against the 256 KiB patch cap; a rename with edits is
  still a deletion and an addition. `apply-patch.mjs` already checks the tree the patch builds with
  rename detection off, so a rename's old and new path each meet every refusal, the path
  predicates, `max-files` and the blob size and credential checks.

## [8.10.0] - 2026-10-30

### Added

- A chunked pr-review-main diff writes `manifest.txt` in the review's data directory, every file of the whole diff one line each with its chunk, its status (added, modified, deleted, or renamed with its old and new path) and its path, up to what one Read returns whole with the rest counted. Each chunk's prompt names that file for the reviewer to read as untrusted data, so the paths the pull request's author chose never enter the prompt, and asks for a finding naming both paths when a change references a file another chunk holds, so a dependency across chunks reaches the summed verdict. A one-chunk prompt is unchanged, byte for byte. The `pr-review-main chunks` notice adds `manifest_paths=<n>`, the files the manifest names (0 for one chunk).

### Fixed

- A work-resolve-issue run now deletes the issue's leftover lane branches from earlier stopped runs: a branch whose run posted an outcome marker, whose commits are all the lanes App's, and that has no pull request in any state. `issue-prior` names them from the reads it already makes, sparing the branch the run reuses, resumes or starts fresh past and every branch of the run itself, the issue-fields job publishes only the names its own re-derived check also names, and a new `prune-lane-branches` job, the lane's only `contents: write`, re-checks every named branch (pull requests from it in any state, open ones into it) in one GraphQL read and deletes each with one `updateRefs` at the tip it read. The stale-branch comment now says the next run deletes the branch instead of promising no lane does.

## [8.9.0] - 2026-10-30

### Added

- `security-outside-actor.yml` flags an issue or pull request when someone outside the
  organization opens or edits it, comments, or reviews on it: it adds `security: outside-actor` and
  `needs-human` and posts one comment per outside actor naming the login, without a mention, and the
  event, quoting none of their text. Members, owners and Bot senders start no job, except a Bot on a
  fork pull request, which is checked on any action; everyone else is trusted only by numeric id on
  the default branch's trusted-actor list, and an unreadable list flags. The labels are written on
  every flagged event, whatever the payload shows. No model, secret or kill switch; the job token holds `contents: read`, `issues: write` and
  `pull-requests: write`.
- `security: outside-actor` is a hold of its own, defined in `merge-holds.mjs`: the merge queue,
  auto-merge arming, intake triage, the work-unblock sweep, ci-status on a pull request and
  every pull request activity (including the write runner) skip it. Only a person on the
  trusted-actor list removes it: any other removal, a Bot's or a member's not on the list included,
  puts it and `needs-human` back and posts one comment naming the remover without a mention.

## [8.8.0] - 2026-10-30

### Added

- A target-subset size split: sub-issues hold every trusted line plus a `Scope:` line naming verbatim targets. `admission-rules.json` `size-split` sets `on-decline` (`subset` or `park`) and `max-parts`.
- `models.issue-dimensions.split-child-size` (`medium`): a trusted size-split sub-issue rated Large runs at that size instead of skipping with `split-required`.

### Changed

- A size split that cannot be made posts its reason on the issue (codes `not-human`, `few-lines`, `no-split`, `bad-split`, `bad-subset`, `no-type`) instead of only a step summary, with no hold label. An issue with fewer than 2 trusted task-list lines gets the thin refinement first.

## [8.7.1] - 2026-10-30

### Fixed

- A work-resolve-issue stop whose code ends the lane's work (close, host-run or attended) and whose reason names a secret only as a capability the run needs, such as "a host with model credentials", "needs an API key" or "tokens per task", now keeps its route instead of holding for a person, when the rest of the reason holds only listed capability words. Any other word beside a credential, secret, token, password or key after such a code still holds as `security-risk`, so an exposure in any wording does, as do takeover, stolen, attacker, stranger and outsider wording.

## [8.7.0] - 2026-10-30

### Changed

- pr-review-main reviews a diff over its 300000-byte cap in chunks instead of stopping. The diff
  splits into at most 4 chunks of at most 300000 bytes, cut at file boundaries with each file
  whole, and each chunk is reviewed by its own run. The lane's one verdict sums the chunks'
  findings, takes the most CRITICAL ones any one chunk found, and binds as a single-pass verdict
  does. A `pr-review-main chunks` notice gives the chunk count and each chunk's bytes, and a
  `pr-review-main chunk` notice per chunk its bytes, findings and CRITICAL ones. A diff that holds
  a single file over 300000 bytes, or needs more than 4 chunks (a multi-file diff over about
  1.2 MB), still stops as `too-large`; lifting that needs a dynamic chunk count
  ([#11000](https://github.com/melodic-software/claude-code-plugins/issues/11000)). Each listed
  finding names its chunk, so the listed CRITICAL findings can outnumber the `critical` count. A
  chunk that fails, leaves no result or skips a part writes no verdict: the record job posts
  `verdict=none reason=chunk-failed` on the head and the leg fails.

## [8.6.2] - 2026-10-30

### Fixed

- The fix-docs dispatcher no longer dispatches a PR again after a `pr-refine fix-docs #<n>` run for it completed without posting a check. Before, a run that stopped at its trigger gate, emitted an empty head or failed before its report was dispatched again on every push to main, and a same-repository PR stopped at the trigger gate took a dispatch slot each time. A PR whose only run was lost (`cancelled`, `timed_out` or `startup_failure`) gets one more dispatch, and none after a second lost run. The dispatcher reads this from the run listing it already reads for its in-flight guard, so it makes no new call (`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`). ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890))

- A `ci-fix-escalated` stop now queues the pull request for a session builder, so it no longer
  has no next actor once the dispatcher's same-head retry is spent. The label goes on at each such
  stop while that retry still runs, and the session that finds the head green or lands the fix
  removes it; no lane removes it. `escalation-routes.json` gives the reason
  `"label": "needs-session"`, and `report-escalation.sh` adds that label, on a fail route only and
  only a well-formed label name, before the lane-stopped comment that names it. It puts the label
  back when a session removed it and the lane stops again on the same head.

## [8.6.1] - 2026-10-30

### Changed

- The agent App trust-path hold is off (owner decision Q21, 2026-10-29: path holds stay off until
  open issues and pull requests reach zero). `merge.trust-path-hold-apps` names only
  `trust-path-hold-off[bot]`, a login no App holds, in place of `melodic-agent[bot]`, so neither
  ci-status's inline hold nor ci-workflows' `pr-require-checks-trust-paths` (through the regenerated
  `.github/trust-path-hold.json`) holds an agent App pull request for a person, except that both
  still fail closed on a read they cannot finish: a pull request past 250 commits or 3000 files, or
  a branch history past 2000 entries. The list keeps one entry because the shared workflow fails on
  an empty one. Restoring both holds takes three steps: list `melodic-agent[bot]` again, set
  `merge.diff-check.path-holds` true and run `scripts/sync-hold-floor.py`. Listing the App alone
  restores only ci-workflows' hold, since ci-status's inline hold runs only while `path-holds` is
  true.
- ci-status no longer holds a release-App or standards-sync-App pull request for changing a
  trust-gate path, and still holds a Dependabot one, whose action-pin bumps bring in third-party
  code (owner decisions Q21 and Q24). While `merge.diff-check.path-holds` is false, as this
  repository sets the new key, `scripts/sync-hold-floor.py` writes a guard after ci-status's
  exempt-author `hold_patterns` that empties the list for every author but Dependabot. Setting
  it true holds all three again. These authors still get no review lane.

### Fixed

- ci-status and the auto-merge arming step no longer read a member writing "the `do-not-merge` label" as a veto. Any other `do-not-merge`, a comma list included, and a sentence that says not to merge still hold the merge.

## [8.6.0] - 2026-10-30

### Added

- A Node step that sets `API_BUDGET_SCRIPT` ends with its own api-calls notice,
  `::notice title=api-calls::script=<name> github-token=N lanes-app=N not-modified=M graphql=K`, counted
  from the readings the rate guard appends for the job-end notice, so a job's total splits by step.
  pr-merge's enable-auto-merge job names its eight counting steps (who, superseded, head-ref-map,
  listing-carry, carry-run-cache, verify-answers, lane-records, enable-auto-merge). No request
  changes.

### Fixed

- `address-feedback` now works a review thread a trusted person with write access opened when
  that person's own `PR-fix lane: please fix this finding` line is in it. Before, a fix request
  counted only as a reply on a thread a review bot opened, so a maintainer could not ask the lane
  to fix a failing check on a PR no review bot commented on, and the lane stopped with
  `feedback-untaken-threads`. A thread an account off the trusted-actor list opened, one a person
  without write access opened, or one with no fix request is still left alone.

## [8.5.1] - 2026-10-30

### Fixed

- A file the files API sends no patch for no longer holds for a person when its blob ids show no unread content: a rename, mode change or modification that keeps its blob and does not gain execute, or an empty file added or removed, scores the mergeable `no-patch:<path>`. Changed bytes, a copy, a mode that gains execute or an unread blob id still hold as `unreviewed-patch:<path>`. ([#10873](https://github.com/melodic-software/claude-code-plugins/issues/10873))

- A lanes App pull request at `merge.max-verify-fails` (`verify:repeated-fail`) or too old to judge
  (`verify:too-old`) no longer sits unarmed with no signal, and gets no person's label. The pr-merge
  lane (`enable-auto-merge.mjs` through the reader's `capped-close` command, or the gate under
  `merge.lane-prs: gate`) closes it for a fresh attempt at its issue. It posts a
  `<!-- verify-capped-close -->` record quoting each FAILed head's verdict findings on the pull
  request and its issue, then takes `agent-ready` off and puts it back, which starts the fresh
  attempt, before the close; an issue that did not carry `agent-ready` is recorded and not
  restarted. It leaves open a pull request whose issue link the arm path refuses
  or whose issue carries an issue hold label. New `merge.verify-cap-attempts` (default 1) bounds the fresh attempts per issue; past
  it the issue is parked at `status: confirmed`.
- The cross-pull-request FAIL cap leaves out a pull request the lanes App's capped-close record
  names once it is closed, so a fresh attempt starts its own count; only the oldest
  `merge.verify-cap-attempts` attempt records per issue count. A record anyone else wrote or edited
  excuses nothing, and a pull request the close leaves open keeps the lane's refusal note and
  `pr-merge/unarmed` status.
- A pull request reopened after its capped-close record stays open, a rerun after a failed close
  toggles no issue label again unless the run that wrote the record stopped before taking
  `agent-ready` off, the gate path leaves open a pull request a hold label, body hold, member's
  blocking comment or failed read holds (read as never enqueued) or whose human-gated label is
  unreadable, and findings come only from runs of verified origin.
- `label-unblocked.mjs` hands no issue to triage for a lane pull request closed at the cap whose
  record names an attempt, and
  `write-issue.mjs` passes the capped-close record to the next attempt as
  `author_kind: verify-findings`, the only other lanes App comment it keeps.
- `pr-feedback-dispatch.yml` and `pr-unblock-dispatch.yml` start no address-feedback or fix-ci
  round, and post nothing, on a lanes App pull request the gate's reader refuses `verify:repeated-fail`
  (`.github/scripts/pr-unblock/verify-cap.mjs`, with each dispatcher job's existing read token).
  The same goes for `verify:unreadable` from another pull request's unreadable FAIL run for the same
  issue, which may hide the cap; that one is read again next run.

## [8.5.0] - 2026-10-30

### Added

- **`blocked-by-pr` stop code and `wait` route.** A run that waits on an open pull request names it; the lane keeps `agent-ready` with an `outcome=wait pr=<n>` marker, and the work-unblock sweep restarts the issue once that pull request merges or closes, its waits counted against `limits.stop-retries` apart from its retries. A pull request that is not open retries instead.
- **`already-done` and `report-delivered` stop codes and `close` route.** The lane closes the issue as completed: `already-done` only once a cited merged pull request or commit is on the default branch and its commit message closes the issue, and `report-delivered` only on a `work-class: read-only` issue the run committed nothing for, posting the run's summary as the report. Either retries otherwise. A dependent or split parent counts the lanes App's `already-done` close as trusted only while its evidence re-checks true at read time; a `report-delivered` close, or a failed read, counts for nothing. The evidence check now lives in `.github/scripts/lib/done-evidence.mjs`, shared by report-outcome and check-trusted-trigger.
- **Stop-reason marker on every comment that reaches a person.** The issue lane's hand-back and dimension-skip comments carry `<!-- stop-reason lane=work-resolve-issue reason=<code> -->` and a visible ``Reason: `<code>` `` line, the code one of `intent`, `design`, `security` or `cost`. The shared module `.github/scripts/lib/stop-reason.mjs` writes and validates both and refuses `none` on a comment that reaches a person; collect-base-activity copies `.github/scripts/lib/` beside a script's base copy. A stop reason the route table does not list now fails instead of holding.

### Changed

- Intake admission refuses an issue whose body has a line opening with `Hold:`, and holds it at `status: needs-decision` for a person.
- Intake admission admits a lanes App issue only as a trusted size-split sub-issue (`splitChildBody`). Any other issue the App filed holds at `status: needs-decision` for a listed human to file as their own, even when a listed human's comment carries the criteria.
- Intake admission under a room claims the issue's place with a fresh `admission-deferred` before it adds `agent-ready`. It adds `agent-ready` only while fewer issues than the room count ahead of it: issues the issues listing shows with either label, placed by their newest claim (else first `agent-ready` add) since 10 minutes before its status read, with a tie or an unread add counted ahead. Parallel apply-verdict runs for different issues no longer each take the same room. A loser, or a run whose read fails, stays deferred for work-unblock's sweep.
- intake-reenter no longer removes `needs-human`: a decision on an issue that carries it changes nothing. A listed human's removal of `needs-human` now re-enters an issue at `status: needs-decision` as well as one with no `status:` label.

- **The issue lane sends only intent, design, security and cost stops to a person.** Every `hold` row in `stop-routes.json` now names its `class`, and a test fails any hold row whose class is not one of those four. A stop with no code retries at most once, its cap counting every retry the issue has had since a listed human last added `agent-ready`, and then fails; `split-required` takes a new `intake` route that removes `agent-ready`, `status: ready` and `admission-deferred`, so the triage sweep sends the issue back through intake, whose split files its sub-issues (owner Q93). A security mention always reaches a person: a reason with no code, or one whose code closes the issue or sends it to a host run or an attended step, that names `security`, `vuln`, `inject`, `credential`, `secret`, `token`, `exfiltrat`, `malicious`, a password, an API or private key, a backdoor, an exploit, branch protection, XSS, RCE, a CVE or an ignore-instructions phrase holds as `security-risk`. The triage sweep counts the lane's `outcome=intake` comment as a hand-back that starts a new dispatch cycle.

### Fixed

- The write runner's apply-patch push reads a lane escalation again right before it pushes past
  the human-gated label. Callers pass `patch-human-gate` (`fix-request` or `lane-escalation`) in
  place of `patch-fix-requested`; on `lane-escalation` the hold step runs `gate-recheck.mjs`, which
  re-runs for `patch-activity` the check its select job ran, on the same reads (`prHold`, or
  `gateSource` for address-feedback on a PR no owner opened), so a review-lane hold, a person's
  comment, review or label, or a new escalation posted during the model turn stops the push
  ([#9419](https://github.com/melodic-software/claude-code-plugins/issues/9419)).
- `gateSource` and clear-escalations read a review-lane hold as ci-status does: only a removal of
  the label by a person on `trusted-actors.json`, not through an App, lifts it, and a `labeled`
  event by `github-actions[bot]` or `claude[bot]` is a hold. `labelHistory` picks the newest label
  event by its time, not its place in the list, and GraphQL label events carry REST's `[bot]`
  login.
- A malformed review-lane hold marker that a trusted person lifted and that names an older head no
  longer stops address-feedback, fix-ci, resolve-conflicts and fix-docs on that PR for good; one
  that is open or names the current head still does.
- clear-escalations accepts address-feedback's round record and model-run line as pr-unblock's
  own, so a lane escalation's label comes off after an address-feedback round.

- A review finding whose only ask is to run tests CI runs no longer stops the address-feedback
  round. The adjudicator gains a `tests-only` verdict. On an `UNCERTAIN` reply to a non-security finding in a round that
  pushed no fix, the reply job settles it from the head's CI, which the select job records in
  `run.json`'s `ci`. The select job runs `scripts/plan-test-lanes.sh` over the pull request's
  files and reads the latest real run of each covering check: every planned `test-bash` and
  `test-python` leg, `test-node` and each `pr-test-windows` job. If every one passed and no
  unplanned test lane ran, a fixed reply says every check the plan selected passed and resolves the
  thread. If any test run on the head failed, the thread stays open with no escalation, and fix-ci
  takes the red head. If a check is pending, cancelled, missing or skipped, the round
  ends `feedback-unadjudicated` as before. No job gains a permission.

## [8.4.0] - 2026-10-30

### Added

- `limits.api` github-token `pace` (default 0.2, in rate-limits.json; set it in pr-pipeline.yaml,
  0 turns pacing off): the lost-run reconciler
  and pr-unblock-dispatch skip every other scheduled tick (the even run numbers) while the
  GITHUB_TOKEN pool's remaining at its reset, projected from the window's burn rate so far, is
  under that share of the header's limit, so the timer lanes slow to half cadence before the
  breaker stops every lane. Any other event, or a failed read, runs as before.

### Changed

- pr-verify runs its read-only resolver before its trigger gate, so a run the resolver skips (a
  head already judged or moved past, a draft, a run red for anything an approval does not lift,
  an author it does not judge) no longer spends the gate's reads. A judged run makes the same
  reads as before.

### Fixed

- enable-auto-merge's refusal comment wraps each reason line to 100 columns at a space, its
  continuations indented two spaces, and folds more than 20 lines into a `<details>` block, so
  GitHub no longer scrolls a long reason sideways. The marker lines and the line naming the head
  are unchanged. Every reader joins a wrapped reason back into one line and still reads a comment
  posted before the change, and a refusal whose reason is unchanged writes nothing new, so a
  person-removed label stays off. clear-escalations reads the whole reason, so a person's code
  after a wrapped "; " still keeps the label.
- `quote` and `wrapLine` move from verify-notes.mjs into address-feedback.mjs; verify-notes'
  comments are unchanged.

## [8.3.0] - 2026-10-30

### Changed

- enable-auto-merge leaves an unarmed lanes App pull request on its lane refusal (a risk-score hold
  or a pr-unblock stop) with no read when nothing it reads has changed since the last reader run:
  head, `updatedAt`, labels, check and status rollup, reviews, comments, review threads, rung and
  main's code and config. It reuses `merge.skip-unchanged` (max-minutes, max-skips), never skips
  past the refusal's escalation to a failing status, never skips an armed one, and logs
  `enable-auto-merge: skip-unchanged skipped=N recorded=M keyed=K of L`. The records ride in the
  `pr-merge-verify-answers` artifact.
- enable-auto-merge's discussion read lists the changed files, so a head with no rename reads no
  REST files page.
- A `pull_request_target` run of pr-merge handles only the pull request its event names; the
  15-minute schedule keeps the full sweep. A pending event run no longer supersedes another one.
- The merge job lists its candidates with one `gh pr list` and a jq author filter in place of one
  `gh pr list --author` call per author.

## [8.2.0] - 2026-10-30

### Added

- pr-merge's scheduled `clear-escalations` removes a human-gated label a review lane added when every hold comment since the label was last removed names an earlier head, as `stale-review-hold`. At the current head it needs a trusted move (every push since the one that landed the newest held head is by a `human` of the base trusted-actor list, never the lanes App), a whole review from both lanes that passed (each caller's newest run's status job succeeded with a review-complete notice and no hold notice for the head, on a head that changes neither review caller), no HIGH or CRITICAL finding: `critical-findings: 0` from the security lane, every finding inline for the security lane and any lane a hold names, and no unresolved lane thread at `CRITICAL` or `IMPORTANT` (for those strict lanes, none with no readable severity either), one of the pull request's own commits since each held head (not reachable from `main`) that is not a merge, and for a `critical-security` hold at least one `CRITICAL` inline finding of its lane at the held head, each in a file one of those commits changed. A label it keeps on the re-read gets no clear comment. It reads the head and the hold comments again just before the removal. A lane that still finds the cause holds the new head again.
- `ci-status`'s review-lane lift check counts the lanes App's removal only after its own newest `stale-review-hold` comment since the hold names a head no hold comment since the label's last removal names, while none names the event's head, and only when the base commit's `clear-escalations.mjs` `recheckStaleHold`, the same predicate, passes again with the job's own token at the head that comment names, as it was when the App removed the label, including the check-signed-commits hold, other lanes App markers and a person speaking up to the removal. A later head is judged by its own review lanes, so a clean push after the clear stays green before they run. The App's comment only points at the hold; ci-status does not take its judgment on trust.

### Fixed

- A hand dispatch of `pr-unblock.yml` with `activity: resolve-conflicts` on a mergeable pull
  request now merges the default branch tip into its head when the head is behind, through the
  same no-model clean-merge push a conflicting pull request gets, instead of skipping it as
  `not-applicable`. A head that already holds the tip is skipped as `up-to-date` and gets no
  check run. The draft, hold, protected-path, repeat-cap and lanes App identity gates are
  unchanged, and the dispatcher still sends only conflicting pull requests.
- `resolve-conflicts` skips a pull request whose base is not the default branch, such as a stacked
  layer, as `not-applicable`, so a hand dispatch never merges the default branch into it.

### Security

- The issue lane no longer works from an outsider's issue text once a listed human applies
  `agent-ready`: the admit job's `check-blockers.mjs` stops the run for good, through the existing
  `Stop on untrusted provenance` step, when the issue's author is neither a listed human nor the
  lanes App. `report-skip` then runs `report-outcome` with `dimension-skip: outside-author`, which
  removes `agent-ready` and comments that a listed human re-files the work as a new issue, adding
  no label. `write-issue.mjs` also fails the run on such an issue. Admission, intake refinement and
  verdicts, the issue lane and intake re-entry now share one author check, `admit.mjs`
  `authorAdmitted`, which also refuses an issue with no author.

## [8.1.1] - 2026-10-30

### Fixed

- address-feedback can now revert an executable bit the pull request itself added, so such a
  finding no longer escalates `feedback-uncertain`. The review-threads skill may run `chmod -x`,
  and its patch carries the mode. apply-patch's `review-threads` row refuses any new file at
  mode `100755` or a change to that mode (the new optional `new-exec-bit` refusal). Its new
  `pr-mode-revert` content rule admits a mode change only back to the mode the path has at the
  merge base of the PR head and its base, or to `100644` for a file the PR added, read through
  the GitHub API, with no workflow change.
  The refusal stays off the other rows, so `ci-context` and the `issue` row's `script-exec-bit`
  still set script bits, and `babysit_risk.py` still rates a mode change `high-path`.

## [8.1.0] - 2026-10-29

### Added

- A work-resolve-issue run that starts fresh because the earlier run's lane branch is behind the
  default branch now gives the model that branch's work. `report-outcome --find-prior` outputs
  `stale-branch` and `stale-tip` (the tip it checked every commit of), and `write-issue.mjs` adds
  `stale_branch` to `issue.json`: the branch, the tip, each commit's subject and the files it
  changed, from the same capped `GET /compare` a resume uses, as data. report-outcome names the
  branch on the issue once, in a comment opening with
  `<!-- work-resolve-issue stale-branch=<branch> -->`, and deletes no branch
  ([#9468](https://github.com/melodic-software/claude-code-plugins/issues/9468)).

### Changed

- pr-review-main records a designed stop instead of failing. A diff that holds a binary file, is
  over the 300000-byte cap, or has a line over 1800 bytes leaves the leg green with no verdict.
  The record job then posts the check run `pr-review-main: <lane>` on the head, titled
  `verdict=none reason=<too-large|binary|long-line>` with conclusion neutral, and logs a
  `pr-review-main stop` notice. Each stop is one countable record, and a real failure (a failed
  fetch or diff write, an empty diff) still fails the run.

### Fixed

- A `work-resolve-issue` reuse PR whose runner check failed no longer carries `Hold: a human merges
  this` or the `human-merge-hold` label. A failed check is not a reason for a person: the PR opens,
  its Verification section lists the failure, and `ci-status` reruns the check on the head, where
  the fix lanes take it. A `done` run with a failed runner check still opens no PR and retries
  (`check-failed`). `merge: human`, untrusted provenance, an unreadable denied-path or changed-file
  list, path holds and a reuse leak scan that is not `clean` still hold (`mustHold` in
  `report-outcome.mjs`).

- `clear-escalations.mjs` takes off a `needs-human` the lanes App set for `feedback-not-landed` once the head is none of that escalation's resume keys and no unresolved review thread carries a lanes App comment. It pages the PR's review threads over GraphQL, and a listing that may be cut short keeps the label. A person who commented or reviewed since the label went on still keeps it. The monitor's stalled-stop signal does not count that clear as a stop standing on the head.

## [8.0.0] - 2026-10-29

### Changed

- `merge.diff-check.path-holds` turns off every path-based merge hold with one switch. Absent or
  false (the default, and this repository's setting by owner decision Q15), a changed path no
  longer holds a pull request for its path alone. This covers the risk scorer's path floor,
  denied-paths and `review-path:` holds, enable-auto-merge's hold paths and ci-status's
  merge-holds step. A standing refusal that names only hold paths comes off without an approval.
  Set it to true to bring every one back. Cost paths, unsafe or aliasing paths, the manifest
  review, the trusted-actor widening, body holds, vetoes and `do-not-merge` still hold. The gate
  report (`risk.pathHoldsSkipped`), enable-auto-merge's log and merge-holds.mjs name each hold
  the switch skipped.
- Breaking: a config that lists `denied-paths` or `review-path:` globs and has no `path-holds` key
  no longer holds on them. Set `merge.diff-check.path-holds: true` to keep the old behavior.

## [7.7.0] - 2026-10-29

### Added

- A lanes App pull request that holds for a person carries the `human-merge-hold` label as well as
  the `Hold: a human merges this` body line, which the App can edit
  ([#9437](https://github.com/melodic-software/claude-code-plugins/issues/9437)). report-outcome
  adds the label right after it opens the pull request, or when it reuses its open one; a pull
  request the label cannot reach is closed and the issue retried (`hold-label-failed`). ci-status's
  new `Fail a human-merge hold a listed person has not lifted` step fails while the label is on,
  and once it is off unless the first removal at or after its newest add was by a `human` of the
  base's trusted-actor list acting directly, not through an App. `enable-auto-merge.mjs`
  (`HOLD_LABELS`) never arms a pull request carrying it, and merge-holds.mjs `labelHolds` holds it
  in the merge queue, so deleting the hold line or rewriting `Refs: #N` to `Closes #N` no longer
  lets a held pull request merge.

## [7.6.2] - 2026-10-29

### Fixed

- The cost decision's push-history check reads the head branch's whole activity, not one page
  of 100. The activity API keeps a branch name's history across deletions, so a branch recreated
  for each sync filled the page for good, and the full-page refusal held its pull request with no
  way to clear. pr-merge (`merge-holds.mjs`), the babysit merge policy and ci-status's cost-hold
  step follow the Link header's `rel="next"` cursor until a page of fewer than 100 entries. The
  hold stays on a read that fails on any page, an empty or non-list page, a full page with no
  next link, more than 20 pages (2000 entries; the busiest reused name had 564) or, in pr-merge,
  a next link with no new cursor.

## [7.6.1] - 2026-10-29

### Fixed

- At the address-feedback round cap, a finding from a review bot listed in
  `review-threads.reviewer-ids` (such as `chatgpt-codex-connector[bot]`) is a bot finding: it goes
  to the fresh fixer round instead of a person. It still goes to a person when a trusted person
  directed it, or when the security-review lane held its head as `CRITICAL`.
- A security-review finding rated `IMPORTANT` at the round cap is a code fix first: it gets the
  fresh fixer round, and goes to a person only when that round was given it and left it open. A
  `CRITICAL` or unrated security finding still goes to a person at once.
- The fresh fixer round's thread file carries a fixed `retry.brief` (fix each finding in code;
  never weaken a test or check to close one), which the read runner adds to the skill's preamble.

## [7.6.0] - 2026-10-29

### Changed

- pr-unblock settles a security-review `manifest dependencies: flag` rated below `CRITICAL` without a person when the lane's `INCORRECT` reply holds up. `hardRequire` in `adjudicate-feedback.mjs` reads the flagged `plugins/<p>/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` at the PR head. It checks that the plugin is a marketplace entry, that each `dependencies` entry is a bare name of another entry with a `./` source in this repository, that the dependency adds nothing Claude Code runs at the PR's base and head (a manifest of metadata and `userConfig` only, a marketplace entry of listing fields only, and no `hooks/`, `.mcp.json`, `.lsp.json`, `monitors/`, `bin/`, `workflows/` or `settings.json`), and that the lane cited a line of the plugin's skills, agents or commands, outside a `## Next` section, where `/<entry>:` starts a token with no gate, condition, fallback or negation word within two lines, in a file that already holds such an unguarded call at the PR's base, so the call-site evidence is read at both the base and the head. The reply job then posts a fixed reply naming those lines and resolves the thread. Such a flag takes no adjudicator slot, and one the check does not settle escalates `feedback-disputed`: a cross-marketplace, object-form (versioned) or externally sourced entry, a dependency that ships hooks, servers, monitors, executables or dependencies of its own, an optional collaborator or a failed read. A `CRITICAL` or unrated flag, an `UNCERTAIN` or `VALID-defer` reply and every other security-review finding route as before.

### Fixed

- A pr-review-main run whose first attempt failed before any lane's verdict write started (every
  credential leg stopped) is now re-run once, recorded, by the lost-run reconciler, as a lost
  pr-verify run is, so a lane-source pull request no longer waits for its next push to be
  reviewed from main.

## [7.5.3] - 2026-10-29

### Added

- A "Write identities" section lists which workflows write as `GITHUB_TOKEN`, the lanes App, the
  release App or the owner token, and why each split exists.

### Fixed

- The pr-verify fail note no longer scrolls sideways. Each line of the verifier's quoted summary
  and notes is wrapped at a space within 100 columns, continuations indented two spaces, with a
  word longer than that (a URL or path) kept whole; a quote over 20 lines folds into a
  `<details>` block. The text stays in its `text` fence, so a mention, reference, link or HTML in
  it stays inert.

## [7.5.2] - 2026-10-29

### Fixed

- work-unblock's hourly sweep no longer re-admits an `admission-deferred` issue on fewer checks than intake's admission. A deferred issue that now carries `do-not-merge`, or whose `work-class: untrusted-provenance` label someone unlisted removed, stays deferred, as one with `needs-human` or the untrusted-provenance label already did. One that lost `status: ready` loses `admission-deferred`. One that gained `area: security`, or whose body was edited, after its newest `admission-deferred` add gets the admission comment and loses `status: ready` and `admission-deferred`. It parks at `status: needs-decision` for the security area, else at `status: confirmed`. Before, the sweep added `agent-ready` to any of these issues once its blockers were closed. `decide()`, which judges a person's mark on a deferred issue, refuses an issue that carries `do-not-merge` or `needs-human`, or that changed in the same ways, whatever `admission-rules.json` lists. A mark refused that way parks at `status: needs-decision`, as any refused mark does ([#10733](https://github.com/melodic-software/claude-code-plugins/issues/10733)).

## [7.5.1] - 2026-10-29

### Fixed

- The main-run review (`pr-review-main.yml`) runs on the review lanes' credential chain instead of the API key alone: a lane whose key leg credit-stops, is refused with a 401 or 402, or has no key is reviewed on the reviews role's subscription token, and a lane that leg hands off (a limit stop, a credit stop, a 401 or 402, or no token) on `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`. Each leg is its own job holding one credential, writes the same verdict, and stays green when it hands off, so an exhausted key no longer leaves every lane-source pull request unbound.
- When the main-run review's whole-file diff is over its size cap, a file moved unchanged shows as its rename lines alone, so a pull request of pure moves fits. A move into or out of a lane source, a mode change, a moved symlink or submodule, a move that may run or load (an executable, a skills, agents, commands or hooks path, or a file a tool reads by name), and a move an added line names still show whole, and the reviewer is told a rename-only entry is unseen.

## [7.5.0] - 2026-10-29

### Added

- A base-branch trust-path hold: `pr-require-checks-trust-paths.yml` runs ci-workflows' shared hold from `pull_request_target`, which posts a failing `ci-status` status when an agent App touched a pull request that changes a path in `.github/trust-path-hold.json`. `scripts/sync-hold-floor.py` generates that file from the same floor and `merge.trust-path-hold-apps` as the inline hold, which stays.

### Fixed

- Intake admission no longer parks host work at `status: needs-decision`. An issue whose done-when items are all ones an unattended lane run cannot perform now parks at `status: confirmed`, with `host-run` added, the host queue's label, when nothing else refuses or waits, and an issue that already carries `host-run` parks at `status: confirmed` whatever its items. A `host-run` label counts only when a listed human or the lanes App added it last. Only an issue without such a label that mixes such items with items the lane can do still holds at needs-decision, where refine.mjs splits it, and so does any issue with a paid-eval item, since a paid eval can bill the owner; the admission comment now names the host queue, or the owner for a paid eval, instead of a person. An issue held for a person, or with any other refusal, wait or pending split, gets no `host-run`, since that label starts an unattended host run. Before, the owner's release of [#9293](https://github.com/melodic-software/claude-code-plugins/issues/9293) with `host-run` added was re-held for a person.
- The issue lane's `issue.json` carries `split_parent`, the body of the native parent a size split filed the issue from, when the issue counts as that parent's text (admit.mjs `splitChildBody`) and a listed human wrote, and last edited before the label if ever, that body. The split copies only the parent's task-list lines, so a part lost the parent's notes and plan, and the lane pushed back on missing text ([#10176](https://github.com/melodic-software/claude-code-plugins/issues/10176), [#10205](https://github.com/melodic-software/claude-code-plugins/issues/10205)). The split-child trust rule is unchanged: the part's body still holds only copied task-list lines.

## [7.4.1] - 2026-10-29

### Fixed

- The post-merge mutation lane comments on the merged pull request only when the result has a
  surviving or uncovered mutant. A refused, scope-empty, stopped, errored or all-killed run no
  longer notifies the author; the job summary still has every outcome, and a refusal or an
  all-not-run result is a `::warning::` annotation. A refused run that still reports a survivor
  both comments and warns. A comment from an earlier run of the same head stays in place.

- On an adopted owner PR, the `address-feedback` select job skips `awaiting-human` when the body gained a `Hold:` line after the round was dispatched, so a hold the owner adds while the round is queued stops it before any model turn. Lanes App PRs, whose `Hold: a human merges this` holds only the merge, are unchanged.
- On an adopted owner PR, a lane escalation's human-gated label lets an `address-feedback` round dispatch and run only as it lets fix-ci work the PR (`gate-source.mjs` `prHold`): it holds after an `address-feedback` escalation, or once a person commented or reviewed after the label went on, and then only a thread a trusted person with write access asked the lane to fix is worked. On a lanes App PR a lane escalation's label still lets the round work, as before.

## [7.4.0] - 2026-10-29

### Added

- central lane grant file, and a refusal that keeps lane patches off it and the trusted-actor list

  `.github/actions/resolve-config/lane-grants.json` holds one row per repository the lanes token broker admits, keyed by repository id ([ADR 0085](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md) Decision 2): the lanes and activities it may run with each activity's effect, its trusted-actor additions and the ci-workflows commits whose reusables may mint. The rows for claude-code-plugins and pr-pipeline-sandbox reproduce what each repository's own configuration grants today. Nothing reads the file yet; the broker reads it after its one-time change (Decision 7). Every `patch-rules.json` row must now refuse the new `lane-grants` class, which covers that file and `.github/standards/trusted-actors/trusted-actors.json` in any case and through any `..` segment, a rename into either included, so no lane patch can change who may start a lane or what it may mint (Decision 6). The issue lane's model is denied `Edit` on both paths. A patch-rules row without the class fails `checkPatchRules`. ([#7656](https://github.com/melodic-software/claude-code-plugins/issues/7656))

- `address-feedback` also serves an adopted owner PR: one a `kind: human` account on the base's trusted-actors list opened, under an `adoption` section, with no `Hold:` body line, once the PR and its head commit are `adoption.idle-hours` old, the rule fix-ci adopts by. Its replies post as the lanes App, so the owner's babysit worker tier can tell a lane answer from the person's and resolve the outdated threads the lane answered ([#10763](https://github.com/melodic-software/claude-code-plugins/issues/10763)). The half-hourly sweep sends one such idle PR per tick whose reviewed head has no round yet, since its review usually finishes while the session is still active; it decides such a head only within two hours of the PR turning idle, and clears a failing address-feedback stop once the owner has resolved every thread. Lanes App PRs, and every other author's PRs, are dispatched as before.
- On an owner PR, `publish-feedback` posts each answer and leaves the thread open, since the lanes App cannot resolve a thread on a PR it did not open, and the select job skips a thread the person wrote or answered with no stop instead of escalating `feedback-untaken-threads`.

- `pr-review-main.yml` runs both review lanes from main, through `workflow_run` on `pr-require-checks`, for a pull request that changes a lane source (a workflow, Claude Code configuration or the review criteria). It reviews the head's diff as data with each lane's criteria copied from main, on a read-only token and a Read-only model leg, posts only its counts as a check run, and uploads each lane's verdict as `pr-review-main-<lane>-<pr>-<tree>`. The merge gate binds such a pull request's lanes only on that verdict, authenticated by its run's record (the file, event `workflow_run`, the default branch, completed success), never on a comment; with none they stay unbound as before.
- A workflow change that gains a write scope (or leaves a job on the repository-default token) holds for a person as `permission-widening-review`, and one that adds a `pull_request_target`, `workflow_run`, issue, comment, review, discussion or `repository_dispatch` trigger as `privileged-trigger-review`.
- A file the files API sends no patch for holds for a person as `unreviewed-patch:<path>` unless it is an image, font or PDF. The main-run review diffs with `--text` and writes no verdict for a binary or over-size patch.
- The main-run review records each lane's counts as a `pr-review-main: <lane>` check run, which no token can delete; the gate holds on the most CRITICAL findings any head of the pull request recorded, so a whitespace push cannot re-roll one away.

### Changed

- A new `skip-reason`, `kill-switch`: a lanes kill switch stopped the run. Every lane's gate stop by
  its own kill-switch step now posts neutral `kill-switch` instead of `prerequisite-missing`
  (`report-check-run`'s `gate-skip-reasons.json`), in every lane check it posts.

- The cost hold section says cost means only what can bill: a `--model` or `--max-turns` flag, and on a public repository a `cron:` key, a raised timeout or a raised `retention-days`, report nothing. A `pr-pipeline.yaml` change is still the reported `cost-finding`.

- This repository's `merge.max-in-flight` rises from 5 to 10. One full run of main's tip verifies every lane merge it contains, so the lane arms up to twice as many pull requests per verification cycle with no extra full runs. A red run now charges up to 10 unverified lane merges, and any charge still demotes the rung.

- Every workflow that holds a credential beyond its job's `GITHUB_TOKEN` (a secret other than `GITHUB_TOKEN`, a lane token, an OIDC token), and the review workflows with the main-run review's scripts, is a `gate` floor path, held for a person; `scripts/sync-hold-floor.py` derives the workflow rows from the files. Claude Code settings, `.mcp.json`, `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` and `docs/standards/**` are `gate` too. `pr-merge.yml` and `pr-unblock.yml` move from `enforcement`. `review-path-unbindable` is gone: an enforcement path beside a lane source waits for the main-run security review.
- `pr-require-checks.yml` (ci-status, which posts the required status and runs the hold step) moves from `enforcement` to a `gate` floor path, named by file, and so is every workflow whose job token has `actions: write` (or `write-all`), since it can dispatch a gated credentialed workflow: `intake-reenter.yml`, `pr-feedback-dispatch.yml`, `pr-unblock-dispatch.yml`, `maintenance-reconcile-lost-runs.yml` and `post-merge-demotion-alert.yml` join. Each holds for a person outside the author lift; 23 workflows are gated.
- Those review-surface `gate` rows (the gated workflows, the main-run review's scripts, the agent settings and instruction files) never take a trusted author's gate-path lift; a person approves them.
- The main-run review reads its diff in parts one Read returns whole, and writes a verdict only when every part was read whole.
- Without PyYAML, a mapping-form `issues:` trigger under `on:` holds as `privileged-trigger-review`.
- `**/.claude/hooks/**` is a `gate` floor path outside the author lift: a hook that settings already registers changes what lanes run.
- `**/.claude/*.sh`, `**/.claude/skills/**`, `**/.claude/agents/**`, `**/.claude/commands/**` and the instruction-exception register and untrusted-content conventions are `gate` floor paths outside the author lift too.
- The pull-request merge gate reads every `pr-review-main: <lane>` check run on a head (`filter=all`), so a newer clean run hides no recorded CRITICAL.
- A pull request only the main-run review binds (`needs_main_review`, as the binder decides) whose patch holds a line over 1800 bytes holds for a person as `long-line-review:<path>`; a read-only workflow, which the pull_request lanes bind on the whole diff, does not; the main-run review writes no verdict for it, and the binder counts no verdict past that line length.
- `**/.claude/rules/**`, `**/.claude/*.json`, `**/.claude/*.md` and `.claude-lane/**` are `gate` floor paths outside the author lift (owner decision Q11: agent settings and instruction files stay gated).
- A main-run verdict binds only beside the record job's matching check run on the head; the review diff uses `--no-renames`.
- A workflow that reads the secrets context in any form (`secrets.*`, `toJSON(secrets)`) or sets `permissions: write-all` is a credentialed `gate` workflow, and an added object-form reference holds as `secret-exposure-review`.
- `**/.claude/**` and `**/.claude-lane/**` are held whole in place of the per-file globs, and the merge gate's, merge-holds.mjs's and ci-status's matchers are tested to hold the same paths. The record check run counts only when the github-actions app posted it.

- The cost hold's documentation names the billed timeout, composite-action model-leg, secret and runner-expression shapes it now catches, the accepted move of a `secrets` reference within one file, and the shapes left to the review lanes' cost hold: new triggers, removed guards, matrix growth, a non-Claude model action and paths outside the ones it reads (#9241).

### Fixed

- A pr-unblock or pr-refine write job that the token broker refuses with reason `kill-switch` (a
  switch turned on after the run's own kill-switch step read it) no longer ends red.
  `pr-run-activity-write.yml` now passes `kill-switch-ok` on a pull request run, so the token step
  ends green with no token, every later step skips, and the check is neutral `kill-switch`. An
  issue run (work-resolve-issue) stays red, since work-unblock re-fires its issue from the failed
  mint step, and so does pr-unblock's `report-escalation`, which nothing re-fires. Before, a reply job stopped this way ended `feedback-publish-failed`, routed to a
  failing status.

- The pr-unblock dispatchers dispatch a head again once the kill switch lifts. A `kill-switch`
  check never handles a head (`limit-stop.mjs` `killSwitchStop`), and on a push, reply or verdict
  job's check it releases the head's earlier activity checks as a lane stop does: in
  `stopRelease` (resolve-conflicts), the address-feedback reply releases and half-hourly sweep,
  the review-dependency verdict release, and fix-ci, where it spends no restart. Such stops count
  toward `limits.limit-stops-per-head` (`SWEEP_HEAD_CAP` for address-feedback), so a switch that
  keeps flipping mid-run still ends the head. Before, a head whose activity check had run stayed
  handled until a new push.

- A fix-ci run whose only fix weakened a test no longer hands the pull request to a person on the
  head's first fix-ci attempt. apply-patch stops it as `ci-fix-weaken-retry`, a failing status,
  and the fix-ci dispatcher retries the head once at `model-rung` 1. That fresh fixer round's
  `context.json` carries a fixed `retry` brief (fix the code under test and keep every test's
  assertions and expected values). `fix-ci-context` decides the round
  (`weaken-retry`: no finished fix-ci check and no lane stop on the head) and finds it again from
  the head's `Lane stopped: ci-fix-weaken-retry` status. A `weaken-required` in that round, or
  after any earlier attempt on the head, still goes to a person as `ci-fix-weaken-required`, and a
  `protected-path` escalation beside it still wins.

- intake-triage's split of a held issue no longer edits the issue body. The lanes App's refinement comment now records the done-when items a person runs and the body they number (`<!-- split items=N -->` beside the body hash), and admission and pr-verify read that record (admit.mjs `personChecks`): admission leaves those items out of its unrunnable and unpushable checks while they are exactly the items the lane cannot perform, a size split leaves them out of its parts, pr-verify passes them to the verifier as `person_checks` beside the body, which stays as its author wrote it, and the issue lane's `issue.json` carries them the same way. Each reader honors the record only under admission's guards (the refinement counts as spec, names the body's hash, and lists exactly the items the lane cannot perform under the issue lane's configured web hosts); a split refinement whose record does not stand reaches neither the verifier nor the lane, so its prose excuses nothing. Before, the App's body edit made it the body's last editor, so pr-verify no longer trusted the body and the issue lost its spec ([#9372](https://github.com/melodic-software/claude-code-plugins/issues/9372)). pr-verify's trust rule is unchanged.

## [7.3.1] - 2026-10-29

### Fixed

- pr-verify judges a pull request whose `ci-status` fails only on the `do-not-merge` label, alone or beside a hold an approving review of the head lifts, so a session holding the pull request gets a verdict on each head it pushes. resolve-pr's `heldOnly` accepts a failed `Check the pull-request contract` step when its only error is check-contract's `do-not-merge` line. `ci-status` still fails while the label is on, and the merge queue still removes the labeled pull request ([#10819](https://github.com/melodic-software/claude-code-plugins/issues/10819)).

## [7.3.0] - 2026-10-29

### Added

- `merge.full-run-cap-bypass` (default `true`): pr-merge's `post-merge-dispatch` starts a full run of main inside its 30-minute cap when the post-merge check that judged (exit 0 or 5) lists an unverified lane merge with no dispatch run under way and main's run listing holds no non-cancelled run created at or after the merge on a commit that contains it. One run of main's tip covers the whole batch, and the next tick finds it in the listing, so the same batch never starts a second run. A run at a commit the job's checkout lacks counts as cover; a merge the checkout lacks, or one older than every listed run, is skipped. The lane arms nothing past `merge.max-in-flight` until a full run verifies the merges in flight, so a batch that landed inside the cap no longer waits it out. `false` keeps the cap for every merge, as before. `dispatch-full-run` (the push path) keeps the cap: it has no post-merge report and no history to judge coverage. The step reads files and the checkout only, so it makes no API call.

### Changed

- The pr-merge gate lets a pull request a person on the trusted-actor list opened clear a `gate` floor path that only their own commits touched on a clean security review of a head pr-verify passed, as an `enforcement` path clears; lanes App and bot pull requests, a lane fix on a gate path and every `trust` path still wait for a person; `.github/actions/resolve-config/**` and `docs/conventions/pr-pipeline.yaml`, which scope lane tokens, and `babysit_merge.py`, `babysit_merge_policy.py`, `babysit_risk.py`, `babysit_review_evidence.py`, `merge-holds.mjs` and `scripts/sync-hold-floor.py`, which compute the lift and the hold tables, and `enable-auto-merge.mjs`, `superseded.mjs`, `clear-escalations.mjs`, `gate-check.mjs` and `head-ref-map.mjs`, which apply and enforce the holds, are now `trust`, so it never takes the lift.

- pr-merge's `post-merge-dispatch` carries the completed run attempts its post-merge check read from one tick to the next, as `attempts.json` in the `pr-merge-post-merge-report` artifact it already keeps. The check step copies the last trusted run's file (read by `last-report.mjs`) to the path it names in `BABYSIT_POSTMERGE_ATTEMPTS`, and keeps the file the check leaves, whether the check runs or an idle tick reuses the report. On the 2026-10-28 ticks this spares the 8 attempt reads each check made, of the job's 50 to 57 GITHUB_TOKEN calls. The `merge` job's check names no file and reads as before. Permissions are unchanged.

### Fixed

- The job-end `api-calls` notice counts every GitHub request the lane scripts' Node clients send. Before, the clients built by address-feedback (its select and context mains, fix-ci-context and review-dependency), pr-verify's job-log read, and three steps that named no bucket sent requests the notice never saw. A client on a second token now counts under `API_BUDGET_OVERRIDE_TOKEN` when the request's token is not the step's own `GH_TOKEN` (else `GITHUB_TOKEN`), the rule babysit's gh calls already follow. Before, the job token's calls in a lanes App step were counted as lanes-app. No request changes, with one side effect: the rate guard plans each pool's read floor to the entry its token names, so pr-merge's Re-fire step, which now names `lanes-app`, planned its job-token client to lanes-app's uncapped entry instead of github-token's 1000 `limit-cap`. That client is now pinned to github-token, so its readings and its read-floor warning are the job token's again.
- The notice adds `graphql=K`, the GraphQL requests among the count, which spend GraphQL's own pool: `<token>=N not-modified=M graphql=K`.

- `review-dependency` no longer hands a pull request to a person when its verdict or context fails validation. `escalation-routes.json` routes `dependency-invalid` to a failing `pr-unblock/review-dependency` status with no label, and `apply-dependency-verdict.mjs` posts its verdict check as `lane-stopped`. `dependency-dispatch.mjs` then dispatches the same head again, through the `stopRelease` and `releasedBy` helpers `dispatch.mjs` uses, until `limits.limit-stops-per-head` such stops stand on it; at the cap it records the head and logs a warning. Every other `dependency-*` reason still holds for a person.

- The lane sweep's file job no longer drops a workflow-level finding (duplicate runs, reruns) from a slice D unit with green samples. A D unit's green samples do not list every job that ran, so `file-findings.mjs` now binds a D finding to its workflow only; slice A still binds the job to its runs' failed jobs.

- hold trust-gate path changes the agent App authored or pushed

  ci-status's trust-gate path hold covered only the exempt authors (Dependabot, the release App, the standards-sync App). A pull request the agent App opened, or one it wrote a commit of or pushed to, went to the review lanes, whose callers its head can rewrite. The new `merge.trust-path-hold-apps` key in `pr-pipeline.yaml` lists such Apps by `[bot]` login (this repository: `melodic-agent[bot]`), read at the base commit. A same-repository pull request that changes a trust-gate path now fails ci-status, and a person merges it, when a listed App is its author, the author or committer of one of its commits (account or noreply address), or a pusher to its head branch (the repository activity API). It still needs both review lanes otherwise. The App list, commits and push history are read only once a trust-gate path matched; an unreadable one, a commit list shorter than the pull request, or a full page of pushes fails closed.

- A disputed security-review finding rated `SUGGESTION` no longer hands the pull request to a
  person. address-feedback reads the lane's own `severity:` line (`severityOf` in
  `address-feedback.mjs`: the body's only such line, outside any fence, first or last above the
  footer) and holds for a person only at `IMPORTANT` or above, the rating this
  repository counts as HIGH (`SECURITY_PERSON_SEVERITY`). A `SUGGESTION` is adjudicated as a
  code-review finding is, and an adjudicator's `security` question on it ends the lane in a failing
  status as `feedback-unadjudicated`, not `feedback-question-security`. Past the round cap it gets
  the fresh fixer's round. An `IMPORTANT` or `CRITICAL` finding, one with no such line, an unknown
  rating, a second rating-shaped line or one quoted from the pull request, and a thread a person directed still go to a person as before.

- Intake admission and the work-unblock sweep no longer start the issue lane on an issue whose work a merged pull request may already have done. A pull request merged in this repository that names the issue on a `Refs:` line after its newest `**Decision recorded.**` or refinement comment parks the issue at `status: confirmed` with one admission comment naming the pull request, for an agent to close it or record what is left. Each admission pass reads its issues in one GraphQL call, and a failed read admits as before.

- A pull request no longer stays red on a stale `ci-status` after the pr-unblock lane that stopped on its head clears its own `pr-unblock/*` status. A status post starts no run, so the next `maintenance-reconcile-lost-runs` run re-runs, once and recorded so `pr-verify` trusts it, the failed `ci-status` of a newest `pr-require-checks` run whose first attempt failed only on pr-unblock stops, once no such status fails the head. A failed re-run is a warning, not a failed reconciler run.

## [7.2.2] - 2026-10-29

### Fixed

- A pr-merge or intake-triage run that the token broker refuses with reason `kill-switch` no longer
  ends red. The lane breaker turns the repository kill switch on after a queued run has read its
  variables, so the run's own kill-switch check passes and only the broker's live read stops it.
  `request-lane-token` takes a new `kill-switch-ok` input (`token` mode only): on that 403 it ends
  green with a `lane-token-stopped` notice, no token and `skip-reason` `kill-switch`. Every step in
  pr-merge's `merge` and `enable-auto-merge` jobs and intake-triage's `apply-verdict` and
  `apply-refinement` jobs that uses the token already runs only when the token is set, and
  intake-triage's `refine-select` now skips on apply-verdict's new `stopped` output. Any other
  denial, and every caller without the input, stays red; work-resolve-issue stays red because
  work-unblock re-fires its issue from the failed mint step. `version` stays 2.

- pr-merge's `enable-auto-merge` no longer queues a lanes App pull request whose head a pr-unblock
  lane stopped. ci-status's merge-queue run fails a head whose newest `pr-unblock/*` status by
  github-actions[bot] is `failure` or `error`, but only after every lane leg ran, and the queue then
  ejected it. The rule now lives in `merge-holds.mjs` (`unblockStops`, `readStatuses`): a stopped
  head, or one whose statuses do not read, is left unarmed (an armed one is disarmed), and each
  such skip gets a line in the run summary. The statuses are read on the job token, whose job now
  holds `statuses: read`, because the lanes App holds no commit-statuses permission.

- pr-merge's `enable-auto-merge` takes `needs-human` off a lanes App pull request itself when the
  lane's newest refusal at the head names only hold paths and a person on the trusted-actor list
  approved that head (merge-holds `pathLifters`, or `liftersOf` over base merges), the release the
  refusal and ci-status already name. Removing the label re-runs ci-status at the head. A cost,
  risk or verifier reason, a refusal at another head, an approval of another head, a dismissed
  approval, an untrusted reviewer or a report-only run lifts nothing. The same label also carries
  holds that live only in it, so the label stays unless it stands for that refusal alone: no
  review lane's hold names the head (or fails to parse); the newest `labeled` event is the lanes
  App's and comes within a minute of the refusal comment, so a label put back with no new comment
  stays; no review-lane or check-signed-commits hold stands since a person last removed the label
  (a bot's removal lifts nothing); the lanes App wrote no pr-unblock escalation or other marked
  comment since; no person commented, replied on a review thread, reviewed (an approval aside) or
  labeled since; and the head read again just before the delete is the one judged. A failed read
  keeps it. It never removes a label a person applied or one another escalation stands behind.

- A trusted person's approval of a hold-path head now also carries to a later head when the diff
  between the two touches no hold path and no file a hold path loads (the owner's decision Q10 of
  2026-10-28, #10759), in `merge-holds.mjs` `approvalCarry` and its twin
  `babysit_merge_policy.approval_carry`. The diff is read with the hold-path rules plus the
  enforcement floor and `CARRY_REFUSES` (workflows, actions, `.github/scripts`, `.github/standards`,
  the pipeline config's directory, `scripts/`, `lib/`, babysit-prs' scripts and every plugin
  script directory a hold-path workflow runs a script from). Any edit to such a file, a test-only
  or comment-only edit included, needs a new approval, and so do a compare not read whole and a
  head that is not ahead of the approved one. `test_merge_holds_sync.py` derives every file the
  hold paths load and fails on one outside the floor and `CARRY_REFUSES`. The control is still a
  person's approval.

- route workflow-staged to a failing status, not needs-human

  A resolve-conflicts stop on workflow-staged now ends in a failing pr-unblock/conflict status and the lane-stopped comment instead of needs-human. The merge carries the pull request's own .github/workflows/ changes together with the base's, which the lane token cannot push, and nothing in it is a person's decision, so a session merges main by hand. escalation-routes.json routes it fail, and the stopping check skips lane-stopped. clear-escalations.mjs still lifts a workflow-staged label an older lane run set, on the same evidence as before.

## [7.2.1] - 2026-10-29

### Fixed

- check-wip-cap closes new admissions when it cannot read the base config (a failed resolve-config import, as after a failed `npm ci` of its dependencies), whatever `wip.pause-from` says: `admission-open` is `false`, and `admission_reason` and `admission_basis` are `config-unreadable`, with a `check-wip-cap` warning. Before, the default limits applied with admissions open, so a broken dependency took the queued cap off. The run pause keeps the last known state as before, and a failed `npm ci` still continues, with a warning that says admissions close.

## [7.2.0] - 2026-10-29

### Added

- **`attended`, separate from `host-run` and `needs-human`.** Work that needs the owner present (a manual step on external state an agent cannot safely run or test) gets the `attended` label. Intake admission refuses it as it refuses `host-run`, parked at `status: confirmed` with no decision asked. While the newest `attended` event is a removal by anyone but a listed human, the lanes App included, admission refuses as if the label were on.
- **External state in refinements.** An exact intake refinement ends its criteria with one plain line, `External state: none`, `iac (<owner/repo>)` or `manual (<class>: <what>)`. Admission refuses a `manual` one and adds `attended`, until a listed human removes `attended` after that refinement; `iac` routes nothing. The classes are config: the new `attended.classes` section of `pr-pipeline.yaml`, which `refine.mjs --select` puts in the model's context and `--apply` checks.
- **`attended` holds downstream.** work-unblock never adds `agent-ready` to an issue carrying `attended`, or to an admission-deferred one whose newest `attended` event is a removal by anyone but a listed human; its re-admission paths park an attended refusal at `status: confirmed` with `attended`. resolve-issue and apply-issue-patch hold on `attended`.
- **`manual-external` stop code.** A resolve-issue run that reaches such a step stops with `manual-external`, whose new `attended` route adds the label and removes `agent-ready`; `host-only` now names a host run alone.

## [7.1.0] - 2026-10-28

### Added

- `limits.readmit-per-run` in `pr-pipeline.yaml` (default 20, at most 100): how many open `status: ready` issues with neither `agent-ready` nor `admission-deferred` one work-unblock sweep runs intake's admission rules on. An issue left out before the rules run does not count.

### Fixed

- work-unblock's hourly sweep now runs intake's admission (`admit.mjs` `decide`) on open `status: ready` issues that carry neither `agent-ready` nor `admission-deferred`, such as a deferral whose label was lost or a `status: ready` set by hand. Before, nothing revisited them. One listing per sweep, oldest updated first. An issue with a hold or refuse label, an open blocker or an open sub-issue is left out unread; one whose `status: ready` neither a listed human nor the lanes App added, or whose `agent-ready` removal still stands, is skipped after its events are read. The writes match intake's: `agent-ready` within the queued cap's room, `admission-deferred` past it or while an open pull request is for the issue, and a refusal parked at `status: confirmed`, or at `status: needs-decision` when it holds for a person.

## [7.0.1] - 2026-10-28

### Changed

- The lanes adopt a trusted person's pull request after 2 hours of no trusted-actor push, comment or label change (`adoption.idle-hours`), down from 24. A session waiting in the GITHUB_TOKEN gate is idle for up to 2 hours during a breaker trip, so a longer quiet period no longer shows the session is still working. Pull requests here open ready, so being non-draft does not show one is finished.

## [7.0.0] - 2026-10-28

### Changed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `default` for a profile's `model`, so a `pr-pipeline.yaml` that names it fails validation; name `opus` instead ([#8724](https://github.com/melodic-software/claude-code-plugins/issues/8724)). `default` passed no `--model`, which run-claude-cli cannot pass. `fable` and `best` stay refused for `model` and `subagent-model`. resolve-config now resolves a model profile's `model` and `subagent-model` outside `haiku`, `sonnet` and `opus` to `opus`, as it does for a role profile, so a config that skipped the schema check still never runs `default` or the frontier tier; `inherit` still sets no subagent model. The built-in `standard` profile, this repository's `standard` profile and the example config's now name `opus`.

### Fixed

- pr-verify judges a lanes App pull request whose `ci-status` fails only on a hold an approving review of the head lifts (a hold path, a trusted-actor list widening), so the person approves a head pr-verify has already judged. `ci-status` still fails until that approval, and any other failure still keeps pr-verify from judging the head.

- post-merge-demotion-alert.yml warns when the suite judge (`babysit_postmerge.py --judge-run`) exits 2 to 4, with the judge's `error` from its JSON output, and still files the demotion as before. Before, the record was filed with nothing saying the judge had failed.
- A dispatched red run is treated as recovered, and files nothing, only when the newer green run's head descends from the red SHA and is on the `main` branch's history. Both `compare <red SHA>...<newer SHA>` and `compare <newer SHA>...<main tip>` must read `ahead` or `identical`, with the main tip read from `git/ref/heads/main`. Any other status, or a failed read, files as if no newer run had passed. A green run on a tag named `main` no longer suppresses the alert unless the tag points at a commit already on the branch.
- `scripts/run-plugin-tests.sh` prints `Advisory nonce: <16 hex>` before any suite block when advisory suites are on, and repeats the nonce in each advisory warning. The nonce is never exported to suites.

- The `wip.pause-from` docs state that leaving it empty removes intake admission's queued cap: over that cap check-wip-cap leaves admissions open with no room limit, so intake still adds `agent-ready`. An incomplete or failed queued read still defers. An intake admission test covers the empty case.

## [6.5.5] - 2026-10-28

### Fixed

- `work-resolve-issue` no longer writes `Hold: a human merges this` only because the runner's checks did not report (missing or for another tip). That line also failed `ci-status`, so pr-verify never ran and the PR waited on a person for checks `ci-status` reruns anyway. On a reused branch, a leak scan that is anything but `clean` (found, failed or missing) still holds it, since `lint-repo`'s gitleaks scan does not cover what the lane scan flags. A failed runner check, `merge: human`, untrusted provenance and every denied-path or unreadable-listing reason still hold it too (`mustHold` in `report-outcome.mjs`).

- A pass-only `address-feedback` round (sent with `verify-pass-head`) that finds no stale pr-verify fail-note thread now runs the full thread select and reports `stop-resolved`, so `report-stop-status` can clear a failing `pr-unblock/address-feedback` status an earlier attempt of the round left on the head, as on a rerun after the notes were resolved by hand. It still starts no model or reply job.

- `work-resolve-issue` no longer opens a second PR for an issue that another open PR already closes. A PR can gain its closing keyword while the model runs, after the `issue-prior` check read none, as happened with [#10698](https://github.com/melodic-software/claude-code-plugins/pull/10698) and [#10686](https://github.com/melodic-software/claude-code-plugins/pull/10686). `report-outcome` now reads the issue's open closing PRs again just before it opens a PR, applying the same trust rule as `issue-prior` (opened by the lanes App or a listed human). When one closes the issue, it opens no PR, logs that PR's number and stops `closed-by-open-pr`, a new `retry` route in `stop-routes.json`.

- The address-feedback lane no longer stops on `feedback-untaken-threads` when the only unresolved threads are pr-verify fail notes from an older head. It clears its status instead, so ci-status can pass, pr-verify can run, and its pass resolves those notes. Before, the failing status kept pr-verify from ever running, so no pass could arrive to resolve the notes. The notes still hold the merge until they are resolved.

- An `address-feedback` fix commit now names the review threads it fixes. `apply-patch.mjs` adds a `Lane-Thread: <thread id>` line after the `Lane-Activity` trailer for each kept thread that a `VALID` reply in the scanned replies names, under the `review-threads` row's new `thread-trailer` key. A reply that names a thread the select job did not keep adds no line. The push job downloads those replies before the mint (the write workflow's new `patch-replies-attempt` and `patch-replies-sha256` inputs) and fails red unless their SHA-256 is the scan job's. `publish-feedback` credits a fix commit to a thread only when the commit's `Lane-Thread` lines name it, in the same round and on a retry's earlier fix alike. A `VALID` thread that no trailer names ends the round `feedback-not-landed`. Before this change, a sibling commit that fixed another finding in the same file could be credited, and the thread resolved, while its own finding stood. Lane fix commits made before this change carry no `Lane-Thread` lines, so a retry no longer credits them.

## [6.5.4] - 2026-10-28

### Changed

- The merge queue's cold-read headroom is 1,546 requests per queue entry (7,830 with the queue building 5), up from 1,520. It now counts the verdict reader's three incremental reads of at most 13 pages each, where it counted one, so a cold reader starts only with the headroom its listing caps can spend.

## [6.5.3] - 2026-10-28

### Fixed

- pr-verify's resolver judges a head again (reason `relinked`) when the pull request's own plain-named FAIL there is followed by a relink to issues a FAIL name carries that only trusted humans made, read in one GraphQL query on that path only; the "Verifier verdict" section of the pr-pipeline convention states the supersede rule the gate applies to the resulting pass.

- A pr-verify fail on a pull request a person opened no longer holds it with review threads the lanes App cannot resolve (GitHub lets only the author or a writer resolve one, and every conversation must be resolved to merge). `verify-notes.mjs` now posts the fail as one pull request comment, edited in place on a later fail, and adds the `pr-verify-failed` label; a pass at the pull request's head removes the label. ci-status's merge-queue run fails while the label is on, as it does for `do-not-merge`. `feedback-dispatch.mjs` no longer sends a pass-only round to such a pull request. Lanes App pull requests keep their fail-note threads and pass-only round.

### Security

- The `address-feedback` reply job (`publish-feedback`) and its `report-escalation` now accept a PR head past the reviewed one only when it is the exact commit `apply-feedback-patch` pushed, passed on as the write workflow's new `pushed-commit` output and the trigger gate's new `pushed-commit` input. A GitHub-verified lanes App commit made during the run, but not by that push, no longer passes the gate. The token broker still checks the old rule until it takes the pushed commit too.

## [6.5.2] - 2026-10-28

### Fixed

- Every lane check run `report-check-run` posts now carries `external_id` `<lane>:<activity>:<run id>:<run attempt>`, not only one with a lane record. GitHub returns these check runs with `details_url` set to the check run's own page, so pr-merge's re-fire of a run the broker refused as `workflow-modified` never found the PR, and fix-ci-dispatch never paired a fix-ci check with its run's lane-stopped stop. Both now read the posting run from `external_id`.

- pr-unblock's `publish-feedback` re-reads each thread against the reviewed heads `address-feedback-select` kept it on, which `run.json` now records as `reviewed_heads`, not against the reviewed-head markers as they are at publish. A review lane edits its one marker in place, so once it reviewed the round's fix push the marker named only the fix head, the re-read dropped the thread as changed, its reply never posted, and the next round escalated `feedback-untaken-threads`. The comment-id, resolved, comment-count and moved-head checks are unchanged; a `run.json` without `reviewed_heads` reads the markers as before.

## [6.5.1] - 2026-10-28

### Changed

- The review callers' `hold-paths`, ci-status's exempt-author `hold_patterns` and merge-holds.mjs `HOLD_PATH_CLASSES` and `COST_PATHS` are generated from `babysit_risk.FLOOR_CLASSES` and `COST_PATHS` by `scripts/sync-hold-floor.py` (`--check` fails on a stale copy); the floor holds the generator as `gate`.

### Fixed

- ci-status's exempt-author check matches the trust-gate paths case-insensitively, as the floor does elsewhere, so a Dependabot, release App or standards-sync pull request that changes `.github/codeowners` or `vendor/.GitModules` fails for a person instead of passing.

## [6.5.0] - 2026-10-28

### Added

- `review-threads.reviewer-ids` lists review bots, besides `claude[bot]` and the review lanes, whose review threads pr-unblock's `address-feedback` works exactly as the reviewer bot's (owner decision 2026-10-26): the select job, the reply job's re-read, `fix-ci-context.mjs` and `pr-feedback-dispatch.yml` all keep such a thread, a disputed one is adjudicated as a code-review lane finding is once the security-review lane has reviewed the bot's reviewed head and holds nothing; a critical-security hold on that head or a later one sends it to a person, and before the lane's review it waits for the next round (the bot's own severity badge decides nothing), and the trusted-person and human-gated rules apply unchanged. The list is matched on the account id GitHub records for each comment and its review, never a login; the bot's later comments count as the reviewer bot's, and anyone else's leaves the thread alone. This repository lists `chatgpt-codex-connector[bot]` (199175422). The resolved config carries the list as `review-threads`.

### Changed

- The issue lane skips an umbrella, an `agent-ready` issue with an open sub-issue, before any model run. It keeps `agent-ready`, logs a notice naming the open sub-issues, and work-unblock's sweep re-fires it once none is open. Neither path adds `needs-human`. An issue read with no sub-issue summary lists the sub-issues rather than assuming none is open.

## [6.4.1] - 2026-10-28

### Fixed

- `ci-status` and `enable-auto-merge` carry a trusted person's hold-path approval over a base merge in two more cases (`merge-holds.mjs` `liftersOf`). An approval GitHub dismissed as stale on the merge's push counts, bound to its own commit and only through the carry (`autoDismissed`: a `review_dismissed` timeline event with no message, a Bot actor and a dismissal commit the merges pushed); a dismissal with a message, by a person, or by a person's push revokes it. When the base changed a file the pull request also changes, the approval carries when the merges brought exactly the base's changes (`exactBaseCarry`, `approvalCarry`): the compare from the approved head to the current head equals, file for file, the compare between the two merge bases. A merge that writes anything of its own carries nothing, and a list of 300 files or more fails closed. The cost-decision carry is unchanged. The carry runs only into the repository's default branch, and the exact path also reads the recursive trees of the current head and of its merge base with the base's tip, so a merge that flips the mode of a file the base changed carries nothing; a truncated tree fails closed.

## [6.4.0] - 2026-10-28

### Changed

- A reuse PR from `work-resolve-issue` no longer carries `Hold: a human merges this` on every PR. It holds on the same conditions as a `done` run's PR, through one `mustHold` check in `report-outcome.mjs` that both paths call, and now reads `merge: human` on a reuse too. It also holds when the compare failed, when the runner's checks for the tip are missing or did not all pass, or when the new reuse leak scan is missing or not clean. This supersedes the fixed hold from [#7831](https://github.com/melodic-software/claude-code-plugins/pull/7831).
- `run-checks` scans a reused branch before its checks run. It uses the read runner's own leak scan on the diff from the branch's merge base with the default branch tip and on every file that diff makes. The result goes into the checks record as `scan`.
- The read runner's leak-scan passes now live in `lib/publish-gate.mjs` (`scanLeak`, `deeperLeak`, `changedBytes`): per-line classification, the UTF-16LE pass, the split-line pass and the scan of the files a patch makes. The scan job calls them from the gate it already loads at the default branch tip, so both scans run one copy of the code. Behavior is unchanged.

- A `pr-unblock` run that stops now ends on the route its reason has in [`escalation-routes.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-unblock/escalation-routes.json), the one routing table that `report-escalation.sh`, `gate-source.mjs` and `clear-escalations.mjs` read. Only a reason a person must settle keeps the `needs-human` label: a path the lane token may not push or a supply-chain refusal, an intent, design or security question, a person's own thread or hold, a finding no adjudicator may judge (security-review or CRITICAL), or any `review-dependency` stop, since a failing status is per head and the head-bound merge marker comes from the lane's own re-run, so only the label holds it for a person. Every other reason (for example `ci-fix-escalated`, `feedback-not-landed`, the resolve-conflicts, address-feedback and fix-ci round and repeat caps) ends with no label, a failing commit status on the head the activity gated (`pr-unblock/conflict` for `resolve-conflicts`, `pr-unblock/<activity>` otherwise, posted by the `report-stop-status` job that replaces `report-conflict-status`), and one lanes App comment per activity that the next stop edits in place. A new head carries no status. ci-status, the one required check, fails while the newest `pr-unblock/*` status on the head by `github-actions[bot]` is `failure` or `error`, naming each such context, on pull request runs and in the merge queue (the queued pull request's head); a later `success` on the same head supersedes it.
- An `UNCERTAIN` or `VALID-defer` reply on a non-CRITICAL `claude-review` finding now goes to the adjudicator as an `INCORRECT` one does, instead of to a person; a security-review, CRITICAL or unknown-lane finding still holds for a person (`feedback-uncertain`). A `lane` verdict (the finding does not hold) resolves only an `INCORRECT` thread, where the lane disputed the finding with evidence: on an `UNCERTAIN` or `VALID-defer` thread it posts nothing, the thread stays open (the ruleset's thread resolution still holds the merge) and the round ends `feedback-unadjudicated`. A `reviewer` verdict hands the finding to the next round to fix, and a `human` verdict holds for a person. A pr-verify note left open ends `feedback-verifier-open`, and a finding that stood at adjudication and was left open again ends `feedback-stood-open`; both route to a failing status. A round's reason held for a person now outranks any reason routed to a failing status.
- `clear-escalations` takes off a `needs-human` an older run set for a reason now routed to a failing status: a `ci-fix-*` reason once a lane check of a `pr-require-checks.yml` run on the current head reads failed. Any other fail-routed reason keeps the label for a person: a new head carries no `pr-unblock/*` status that shows the cause gone or fails that head in the label's place.
- A pr-unblock stop routed to a failing status now skips `lane-stopped` (a new `skip-reason`) instead of `awaiting-human`. On a select job's own check (a cap, or a conflict no model can resolve) it ends the head, so the dispatchers stop re-running a deterministic stop. On the push, reply or verdict job's check, the dispatcher retries the same head under the cap it already keeps:
  - `limit-stops-per-head` for resolve-conflicts
  - `fix-ci-restarts` and the per-head cap for fix-ci
  - `SWEEP_HEAD_CAP` for address-feedback

  The fix-ci dispatcher reads a fix-ci run and its in-run rung-up, which both post a `pr-unblock / fix-ci` check, as one attempt: a stop in either one's push job makes the attempt a failed one, and the pair counts once toward the caps.

  The fix-ci and address-feedback retries run one model rung up, read in the run from the head's own stop record. A retry that acts and does not stop posts success over the failing status; one that ends on a skip (a reply job with no model turn) leaves it. fix-ci's model escalations `protected-path` and `weaken-required` stay with a person, as `ci-fix-protected-path` and the new `ci-fix-weaken-required`.
- `fix-ci-context` and the fix-ci dispatcher read every check run on the head (`filter=all`) instead of the latest per name, so a contract-only run's later skip of a lane no longer hides that lane's failure, and a head with a hidden failure is not read as resolved.
- An address-feedback round that keeps no thread while a review thread is still unresolved (a reviewer the lane does not act on, such as Codex, a review of an older head, a thread it already answered) now ends `feedback-untaken-threads`, routed to a failing status, instead of a silent `not-applicable` skip. The dispatcher now dispatches an ungated head once for any unresolved thread, so that stop is reached; the select job's lane-stopped check ends the head, and the next tick does not dispatch it again. A reply job that fails with no escalation reason (a lane token it could not get) ends `feedback-publish-failed`, also routed to a failing status, instead of posting no stop.
- The monitoring lane gains signal 10, `stalled lane stop`. Each open pull request whose pr-unblock stop has had no new attempt on its head for over 2 hours is listed in one rolling issue. A skip is not an attempt, but a `not-applicable` skip after the stop ends it: for address-feedback on a non-draft pull request, and for fix-ci once a whole listing of the head's checks is settled with none failing. A stop includes a `needs-human` that `clear-escalations` took off for a reason now routed to a failing status. It reads the 40 most recently updated open pull requests and their newest comments in one GraphQL query, reading up to 200 older comments only for a pull request whose newest name no stop on its head; past 40 pull requests, or past those comments, it names what it left unread in the run's gaps.
- The merge path floor's `enforcement` class (`babysit_risk.REVIEW_FLOOR` and `merge-holds.mjs` `REVIEW_FLOOR`, from `FLOOR_CLASSES` and `HOLD_PATH_CLASSES`, and the review lanes' and ci-status's hold lists) also covers `.github/scripts/pr-unblock/escalation-routes.mjs`, which `clear-escalations.mjs` and `gate-source.mjs` now import, and `escalation-routes.json`, the routing table it reads, and the scripts that act on a route: `report-escalation.sh`, which labels a held reason, `adjudicate-feedback.mjs` and `publish-feedback.mjs`, which decide and resolve review threads, and `.github/scripts/apply-patch/apply-patch.mjs`, which holds fix-ci escalations, with every module they import (`request-budget.mjs`, `dependency-classify.mjs`, and `predicates.mjs`, `protected-paths.mjs` and `retry-fetch.mjs` in `apply-patch/`). So a change to any of them, such as one that moves a reason from `hold` to `fail`, stops a held reason from labeling or lets a model verdict resolve a thread a person must, does not merge until a clean security review binds to its head (`review-path:`); it does not hold for a person, which only the `trust` and `gate` classes (`HIGH_FLOOR`, `HOLD_PATH_FLOOR`) do. `test_merge_holds_sync.py` now also follows a module-relative file a floored module reads (`new URL("./…", import.meta.url)`), so the next such data file fails there until it is on the floor.
- A select job that finds a stop gone on its head clears that activity's failing status (`stop-resolved`): `address-feedback` once no hold and no unresolved review thread is left, `fix-ci` once a whole listing of the head's checks, every one completed, has none failing. fix-ci now reads the head's checks before its round cap, so a head re-run green after the cap clears too. A select that fails to read clears nothing.

### Fixed

- A pr-verify note left open past the address-feedback round cap no longer hands the pull request to a person as `feedback-round-cap` with `needs-human`. It gets the fresh fixer's round as a code-review finding does, and once that round has run the head fails: `feedback-verifier-open` when only pr-verify notes are open, `feedback-not-converging` when a code-review finding is open beside them. A pr-verify note a trusted person directed, a security-review finding, a `claude[bot]` finding and a person's `needs-human` hold still escalate `feedback-round-cap`.

## [6.3.5] - 2026-10-28

### Fixed

- A pr-verify pass now clears the fail-note threads from earlier heads on a PR a human on the trusted-actor list opened, not only on a lanes App PR. `verify-notes.mjs` posts fail notes on such an adopted PR, but `feedback-dispatch.mjs` skipped the pass-only round there (`#<n> was not opened by the lanes App`), so the threads stayed open and required thread resolution blocked a passing PR. The pass-only round alone takes that author; every other address-feedback round still goes only to lanes App PRs.

## [6.3.4] - 2026-10-28

### Changed

- A trusted person's approving review of a head that changes a hold path or widens the trusted-actor list carries over a later merge of the base when the merge changes nothing of its own, so the merge no longer sends the pull request back to them. Only an approving review lifts these holds: removing the human-gated label does not, and a dismissed approval never counts. The approval carries only when every commit since is a merge of commits the base branch holds and the whole net change against the base's tip commit is the same at both heads; the base is read once by its full ref. The owner's cost decision carries by the same rule. A carried approval does not lift the verifier, issue-link or pr-verify FAIL holds.

## [6.3.3] - 2026-10-28

### Changed

- pr-verify's resolver looks up only the verdict names `write-verdict.mjs` writes, so it no longer looks up the head-ref digest names no writer produces: an unjudged head whose pull request links an issue takes 7 API calls instead of 11 (one with no linked issue, 3 fewer), and each other pull request at the head one lookup instead of two. The change that moves the writer to digest names adds those lookups back.
- The lost-run reconciler's spec pre-filter looks up a candidate's pass by the same written names, 2 lookups instead of 4.

## [6.3.2] - 2026-10-28

### Fixed

- The pr-unblock verdict job's merge path checks who pushed each commit before it posts a merge marker ([#9006](https://github.com/melodic-software/claude-code-plugins/issues/9006)). `pushRefusal` in `dependency-classify.mjs` (the twin of pr-merge's `push_refusal`, with one-for-one `PUSH_VECTORS` in both test suites) reads the head branch's repository activity back to Dependabot's newest branch creation or force push. Each commit a push brought must be its pusher's own: Dependabot's in a `dependabot[bot]` push, the version-bump commit in a `github-actions[bot]` push, a lanes App commit in a lanes App push. Anything else escalates `dependency-fix-refused`, so a Dependabot-authored commit under a lanes App tip no longer gets a merge marker. The README's **Pushes** check states the rule for both lanes.

## [6.3.1] - 2026-10-28

### Changed

- The pr-merge lane's eligibility section documents the linked-issue hold ([#7783](https://github.com/melodic-software/claude-code-plugins/issues/7783)): at eligibility and again before the enqueue, a linked issue carrying a label from `activities.resolve-issue.applies-when.labels-absent` refuses with `closing-issue-held:<label>`, the tracker's human-gated role label holds when that list is absent, and an unreadable label set refuses. An edit to the issue after admission is the verifier's `verify:spec-changed`.

- pr-merge's gate keeps the run's shared post-merge answer for each candidate past the two-minute unverified age, up to 30 minutes, on the same evidence the lane room keeps it on (main's head, its config commit, the demotion records and the verifying runs of every lane merge it judged unchanged), and reads it again only when one of those moved or cannot be read (`postMergeShared: kept:unverified-stale`).

### Fixed

- `check-signed-commits`' escalation comment opens with `<!-- check-signed-commits hold -->` (`SIGNED_COMMITS_HOLD` in `gate-source.mjs`). A `github-actions[bot]` comment carrying it, written or edited since the human-gated label was last removed, now holds the PR: `gateSource` reads it as `signed-commits-hold`, so fix-ci, fix-docs and resolve-conflicts no longer work past the label when a lane escalation put it on first, address-feedback works only threads a trusted person asked it to fix, and `clear-escalations.mjs` keeps the label. The marker from any other account is not read, and an unmarked bot comment still holds nothing (#9578).

## [6.3.0] - 2026-10-28

### Added

- `clear-escalations.mjs` lifts more pr-unblock stops once their cause is gone: `workflow-staged` also clears once a trusted move took the head off the resume key and the head contains main as it was at the escalation; the `ci-fix-*` stops other than `ci-fix-protected-path` clear once a trusted move took the head off the resume key and, at the new head, no check but `ci-status` fails, runs or was cancelled and each check's latest run ended `success`, `neutral` or `skipped`. A trusted move is read with the job token from the branch's activity, never from comment text: every push since the label is by a `human` of the base `trusted-actors.json`, matched by id, never the lanes App. Security, intent, decision, protected-path and own-patch stops still wait for a person.

## [6.2.1] - 2026-10-28

### Changed

- `scripts/run-test-file.sh` runs a test with git reading a fixed test config (a test identity, commit and tag signing off, no system config) in place of the host's, so a host that signs every commit cannot fail a fixture commit.

## [6.2.0] - 2026-10-28

### Added

- A skill leaf's optional `tidy`: `entry` (the diff-scoped tidy skill), `passes` (the other quality skills it may call), `turn-share` (the percent of the run's turn cap tidy may spend) and `cutoffs` (`max-files`, `max-lines`, `max-areas`, `shared-paths`), the one value that decides whether a change is small and single-area enough to tidy in the run. The schema takes it only on a `read` skill whose `applied-by` sets `patch` with no `prepare`. `resolve-config` carries it on the selected activity. On the launcher, `collect-base-activity` stages the entry's and each pass's plugin read-only under `.lane/plugins`, allows `Skill(<plugin>:<skill>)` for each and no other skill, allows `code-tidying:tidy-diff`'s `change-shape.sh` and the `ai-slop:audit` script rules `fix-docs` already had, and names the cutoffs, the skills and the tidy turn budget in the preamble. `tidy` anywhere but an issue lane's patch skill with no prepare mode on the launcher fails the stage red.
- `resolve-issue` tidies its own change before its last check run and before its review, with `code-tidying:tidy-diff` as the entry and `docs-hygiene:write-for-agents`, `docs-hygiene:write-for-humans` and `ai-slop:audit` as the passes, 25% of its turns, and cutoffs of 10 files, 300 changed lines, one area and no change under `.github/`, `.claude/`, `.claude-plugin/`, `scripts/`, `lib/`, `docs/conventions/`, `docs/standards/`, `AGENTS.md` or `CLAUDE.md`. The PR then reaches review tidied with no extra push, review run or token mint; pr-refine's skip for lane PRs stays.

## [6.1.2] - 2026-10-28

### Fixed

- `resolve-conflicts`, `fix-ci` and `fix-docs` no longer work past another lane's escalation after a person replies inside an existing review thread. GitHub's timeline shows no event for such a reply, so the gate (`gate-source.mjs` `prHold`) now also reads the PR's review comments and reviews, and holds the PR when either read fails.

## [6.1.1] - 2026-10-28

### Fixed

- pr-unblock's `feedback-incomplete` escalation names each kept review thread with no recorded disposition, where it named none and the log gave only counts (#8257). `publish-feedback.mjs` logs each one's id and names at most 20, with their root comments and then how many more, in the round marker it posts; `report-escalation.sh` lists them with each root comment's URL from the newest lanes App round marker on the head it stops on. With no such marker it says so and points at the run's publish-feedback log. No reply is posted, as before.

## [6.1.0] - 2026-10-28

### Added

- `limits.stop-retries` in `pr-pipeline.yaml`: restarts after a retry-routed stop since a listed human last added `agent-ready`, 0 to 5.

### Changed

- The issue lane routes each stop by one table, `.github/scripts/work-resolve-issue/stop-routes.json`, instead of adding `needs-human` on every stop. `hold` (the human-gated label and escalation marker) is kept for a pushback, a run's `intent-change`, `design-change`, `security-risk` or `cost-risk` code, a stop with no code, an issue edited after `agent-ready`, a patch or output refusal that may be a credential shape, and a run whose patch collector refused a file left at a stub name such as `.npmrc` or `.env` (the new `collect-refused` input of the write file carries the read file's `scan-collect-refused` to report-outcome). A protected path or a run's `host-only` code adds `host-run` and removes `agent-ready`. A crash, an apply fault, a moved PR head and an unfinished or failed check keep `agent-ready` with an `outcome=retry` marker naming the branch, and work-unblock restarts the issue. A retry past the new `limits.stop-retries` (default 2), or a spent turn cap, removes `agent-ready` with no label and an `outcome=failed` marker, which the maintenance monitor reports as signal 9.

## [6.0.5] - 2026-10-28

### Changed

- check-wip-cap takes `reads: pause`, which makes only the open lane PR listing and the merged count, the two searches `capped` depends on, and leaves the admission fields unread (`admission_basis` `not-read`, `admission-open` `true`). work-resolve-issue's pick-slot and work-unblock's hourly state save pass it: neither reads anything but the pause, and each used to spend the admitted count, the queued listing, a pull request read per lane PR whose first body line names no issue, and up to 30 blocker reads (26 GITHUB_TOKEN calls in one pick-slot run with 19 issues queued; 5 now, whatever the queue: the two searches and resolve-config's three issue reads). Every other caller still reads all.
- pr-verify's resolve-pr looks up the FAIL names at a head before this pull request's pass names, and weighs a pass against the spec before looking up the FAIL named with the pull request's issues. Each path whose reads succeed resolves as before, and the new order makes a subset of the old lookups, so a failed lookup the old order would have reached can now be skipped; a FAIL named without issues now costs 5 calls instead of 9, and a pass whose spec is unchanged 11 instead of 13.

- The hold-path floor documentation lists `pr-merge.yml` and `pr-require-checks.yml` under `enforcement`, cleared by a clean head-bound security review, instead of `gate` (owner direction 2026-10-27).

- `pr-merge.yml`'s `merge` and `enable-auto-merge` jobs set up the repository's pinned Python and install only the hash-pinned PyYAML entry of `.github/requirements-ci.txt`, which the review-evidence binding needs to clear a read-only workflow-file change. A failed install warns and the job goes on, since the binding then holds every workflow change for a person. The hold-path floor documentation also states that a lane comment edited by anyone but its author unbinds the review as `comment-edited`.

- The hold-path floor documentation states which workflow files are lane sources: a changed workflow whose head copy cannot post as `github-actions[bot]` with a write token nor reach a secret no longer stops the security review from binding, while the review callers, `pr-merge.yml` and `pr-require-checks.yml` still do (owner direction 2026-10-27).

- The cost hold stops a pull request only for a real new charge. Subscription or prepaid spend, including a `pr-pipeline.yaml` spend line, is reported as the non-holding `cost-finding`. A new secrets reference or model leg in a workflow holds for a person as `secret-exposure-review` or `agent-surface-review`.

## [6.0.4] - 2026-10-28

### Changed

- pr-merge starts at most one full run of main per 30 minutes, of main's tip, covering every merge since the last. dispatch-full-run and post-merge-dispatch read the newest pr-require-checks.yml dispatches on main first (`Read main's full-run cover`): within the cap they start nothing, and post-merge-dispatch starts one on its next scheduled run for a tip no full run covers, whoever merged, while the lane is live (kill switch and report-only off). A read of the cover refused for a rate limit stops the job red and sends nothing more (`.github/workflows/pr-merge.yml`).
- dispatch-full-run ends once it dispatches, where it held a runner up to 39 minutes polling the run; its timeout drops from 45 to 10 minutes. post-merge-dispatch now sends a red full run to post-merge-demotion-alert.yml on its next scheduled run while the lane is live (kill switch and report-only off), up to 15 minutes after the run ends, once per run (`pr-merge-alerted-<id>`, counted only when its own run on main uploaded it, by `babysit_postmerge.py --lane-alerted`), and skips a run that never started.
- pr-require-checks.yml's dispatches on main (attempt 1) share one concurrency group with no `queue` key and `cancel-in-progress` false: one runs, one waits, and a newer one replaces the waiting one. A re-run and every other run keep their own group and cancel.
- post-merge-demotion-alert.yml files nothing for a cancelled full run with no job, one the concurrency group replaced before it started.

### Fixed

- work-unblock no longer adds `needs-human` when an issue's limit and funding stops reach `limits.limit-stops-per-issue`. That cap is a safety limit, so the issue takes the issue lane's `fail` route: the lanes App comments with an `<!-- work-resolve-issue outcome=failed run=<run id> -->` marker naming the stopped run, removes `agent-ready` and adds no label. The maintenance monitor's signal 9 now reports `outcome=failed` as `lane-stop:failed`, and a person's new `agent-ready` resumes the stopped run's branch. A sweep that finds a failed marker newest with `agent-ready` still on removes the label.
- A funding stop with no regain date (no credit or a disabled key) no longer waits for a person to restart it: work-unblock restarts it `limits.fallback-reset` hours after the stop, as it does a limit stop with no reset, counted toward `limits.limit-stops-per-issue`.

## [6.0.3] - 2026-10-27

### Changed

- pr-merge's merge job uploads its last saved artifact listing as `pr-merge-verify-listing` (scheduled and hand-started runs, one day), and the merge job, enable-auto-merge and ci-status's merge-queue reader fetch it from the newest such run on main (`.github/scripts/pr-merge/listing-carry.mjs`), so the verdict reader lists only the artifacts uploaded since instead of every page, one GITHUB_TOKEN request each (69 pages on 2026-10-27).

### Fixed

- In the pr-merge lane, adoption's idle rule reads a person's pull request's newest activity, not its raw `updatedAt` (#9136): the pull request's opening, the head's arrival, and each comment, review, inline review comment, label change, title edit, review request, ready for review, reopen or force push whose actor id is on the trusted-actor list. Another account's comments no longer keep an owner pull request from going idle there, unless one is a repository owner's, member's or collaborator's hold: a changes-requested review, or a person's comment or review saying "do not merge" or opening a line with `Hold:`, still refuses; a trusted person's request to wait still refuses. fix-ci still reads the last update.

## [6.0.2] - 2026-10-27

### Changed

- The merge-authority and verifier sections point at loop-lane's [When work stops for the owner](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md#when-work-stops-for-the-owner) instead of restating the owner's rule.

## [6.0.1] - 2026-10-27

### Changed

- `clear-escalations.mjs` `LANE_CAUSES.verdict` adds `verify:repeated-fail` and `verify:too-old`, so under `merge.lane-prs: native` a `needs-human` label `enable-auto-merge` placed for either comes off at its head (`refusal-cleared`) once the reader names only lane causes there. `lane-causes-person-codes.test.mjs` also pins `LANE_CAUSES.verdict` against `babysit_verify_evidence.NEEDS_HUMAN`.

- pr-merge's post-merge-dispatch job reads the post-merge report that the last scheduled or hand-started run kept. It reads only a run on main and finds it the way it finds the lane records (`.github/scripts/pr-merge/last-report.mjs`). On an idle tick it reuses that report and does not run "Check earlier lane merges". It keeps the report's `computedAt`, exit code and code commit, so a chain of reuses ends `SHARED_MAX_AGE` after the check that made the report. Any refusal or failed read runs the check as before. `last-report.mjs` is gate code on the risk floor.

### Fixed

- fix-docs's patch now pushes only markdown outside `skills/` ([#8956](https://github.com/melodic-software/claude-code-plugins/issues/8956)). `pr-refine.yml`'s `apply-docs-patch` job passes `patch-prepare: docs`, so apply-patch holds the patch to `patch-rules.json`'s `docs` row in place of the `default` row: a path not ending in `.md`, a path under a `skills/` directory or any `SKILL.md` refuses the whole patch as `patch-protected-path`, and the run posts its `pr-refine / apply-patch` check neutral. Before, the `default` row let a fix-docs patch push any path outside the universal refusals, a plugin hook or script included.

## [6.0.0] - 2026-10-27

### Changed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `best` or `fable` for a profile's `model` or `subagent-model`, so a `pr-pipeline.yaml` that names either fails validation; name `opus` instead. The two values stay out until the owner sets a Fable allowance for the lanes. Only a test kept them out of the live config before, and a pull request could edit that test with the config.

### Fixed

- Tests settle two open questions about fix-ci's rung-up retry ([#9022](https://github.com/melodic-software/claude-code-plugins/issues/9022)). A rung-up's check is named `pr-unblock / fix-ci`, the name the fix-ci dispatcher counts, so it spends one of the head's `limits.limit-stops-per-head` runs, and a head gets at most two rung-ups (`fix-ci-dispatch.test.mjs`). fix-docs's `default` patch row reads no report, so it never selects `rung-up`, for an empty or a written patch (`apply-patch.test.mjs`).

## [5.20.0] - 2026-10-27

### Added

- The skip reason `pass-only` in `$defs/skip-reason`: the reply check of a pass-only address-feedback round, which ran no model and only resolved fail-note threads a pr-verify pass superseded. `feedback-dispatch.mjs` leaves such a check out of its release reads, so it neither releases a head nor hides the `no-model-turn` or `finding-stands` skip of the round before it. `pr-unblock.yml` takes the new `verify-pass-head` input for that round.

### Fixed

- A pr-verify `pass` or `pass-notes` verdict now clears the fail-note threads pr-verify left open on earlier heads, which kept a passing PR blocked under required thread resolution ([#10113](https://github.com/melodic-software/claude-code-plugins/issues/10113)). `pr-feedback-dispatch.yml`'s `post-verify-notes` job now downloads a pass verdict too, by `write-verdict.mjs` `NAME`'s grammar (`-i` is a fail's alone), and still fails on a verdict-shaped name no reader takes. For a pass on an open PR still at the judged head it posts and resolves nothing: it reads the review threads, and when an unresolved `<!-- pr-verify:fail-note -->` thread by `github-actions[bot]` from another head is open (`address-feedback.mjs` `staleVerifyNotes`, by the first comment's original commit), it names the head in the new `pass-head-sha` output. The dispatch job then sends `pr-unblock.yml` a pass-only round with the new `verify-pass-head` input, through the newest completed review run at that head. In that round `address-feedback-select` lists the stale threads in `run.json`'s `stale_notes`, its `proceed` output stays empty so no model job and no neutral check runs, and `publish-feedback` resolves each one still open and stale while the PR head is the passing one, as the lanes App, posting no reply and no round marker, and skips `pass-only`; a failed resolve does not stop the others, then fails the job. A pass with no such thread dispatches nothing, and the fail path's dispatch gate is unchanged. No job's permissions change.

- report-outcome names why an issue run never started. Before, it said only that the run wrote no readable outcome file. When write-issue refuses because the issue's title or body changed after `agent-ready` was added, it now sets `refused=edited`, and the run job's collect step records class `issue-edited` in `lane.json`. Any other write-issue failure records `issue-file`. The run job now copies the output sealer even after an earlier step failed, so that `lane.json` is sealed and published; before, the carry step found no sealer, and the scan job refused the unsealed payload. report-outcome's hand-back comment then says the run did not start and why. A record of either class counts only for a run that left no outcome of its own (`.github/scripts/work-resolve-issue/write-issue.mjs`, `.github/scripts/work-resolve-issue/report-outcome.mjs`, `.github/workflows/pr-run-activity-read.yml`).

## [5.19.8] - 2026-10-27

### Fixed

- Intake admission refuses three more kinds of done-when item an unattended lane run cannot perform. A paid eval now also covers `measure-invocation` trigger probes, `/evals:plugin-eval`, and a PR body carrying before-and-after numbers, trigger rates or scores. A validate, dry-run or no-spend form, and `measure-invocation`'s model-free `score`, `compare` and `emit-plugin-eval`, still pass. A live Claude Code CLI run covers `claude -p`, `claude plugin test|install|update|configure` and a headless Claude Code run when the item runs it or names its exit or result (not when it only shows or edits the command), and a recorded probe tied to a Claude Code version. A comment instead of a file change covers an item that opens with a comment on this issue or records its output or result in one (not a script that posts one), and an item that is only "No file is changed". The parked concise-skills rollout issues and the CLI-probe issues re-entered the lane through admission after a person removed `needs-human`; they are now refused there (`.github/scripts/intake-triage/admit.mjs`).

### Security

- pr-verify's `resolve-pr.mjs` now checks who renamed a pull request's title before it uses the PR as its own spec, i.e. a trusted PR with no closing issue ([#9115](https://github.com/melodic-software/claude-code-plugins/issues/9115)). The title has to be never renamed, or last renamed by the PR author or a kind-human trusted actor. That is the rule the body's last editor already follows. When the title fails the check, the PR is not its own spec, the same result as an untrusted body edit. The rename read is `titleRenamers`, exported from `select-trusted-text.mjs` and shared with that action, which keeps its own rule: every renamer must be listed. In resolve-pr, a rename page that comes back with no node list is a failed read, so the title is never trusted on a misread. select-trusted-text now fails the same way on a rename or closing-issues page with no node list, where it used to read that page as empty.

## [5.19.7] - 2026-10-27

### Fixed

- An issue run whose `apply-issue-patch` job failed without giving an escalation reason now hands back as `patch-apply-failed` ("apply-issue-patch failed before it committed or refused the patch"), not as "The run reported done but committed nothing". `work-resolve-issue.yml` sets the reason from the job's result, and the write runner's input check admits it in issue mode.

## [5.19.6] - 2026-10-27

### Fixed

- enable-auto-merge no longer holds a lanes App pull request on a hold path once a person on the trusted-actor list approved its current head, the same `pathLifters` rule `ci-status` lifts that hold by; its other checks then decide. An approval of an older head, an untrusted reviewer's approval, or a newer request for changes lifts nothing, and a hold-path list or file listing that could not be read, or one too long to check, still holds (`.github/scripts/pr-merge/enable-auto-merge.mjs`). The gate's risk score lifts the same paths' `high-path:` reasons on that approval, so such a pull request now arms end to end (source-control's `path_lifters`).

## [5.19.5] - 2026-10-27

### Fixed

- The fix-docs dispatcher no longer dispatches a head again on every cycle when its runs post no check, as a run whose run job emits an empty head does under `post-decline: false` ([#9247](https://github.com/melodic-software/claude-code-plugins/issues/9247)). The dispatch record keeps the fix-docs runs dispatched on each head; once `limits.limit-stops-per-head` of them are kept, the dispatcher reads each one's status and jobs through the Actions API, and a head with that many whose `fix-docs / broker-allowed` job succeeded gets one warning and is recorded as handled until a new push. Broker-refused, held and deleted runs do not count, and a head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`, `dispatch-record.mjs`).

## [5.19.4] - 2026-10-27

### Changed

- The collector reads each range's run count from its first page of 100 runs and keeps those runs, where it made a `per_page=1` count call and then read page 1 again, and it lists workflows busiest first, so a short budget leaves the smaller ones part-read (`.github/scripts/maintenance-audit-lane-runs/collect.mjs`).

### Fixed

- The lane sweep's collector keeps 184 calls for the open pull request and issue reads and the units, not 170: with four slice A units, no slice D unit and four slice C units they cost 4 + 4 × 5 × 7 + 4 × 10 calls, so that mix no longer runs out partway through its slice C units and marks the run incomplete ([#9339](https://github.com/melodic-software/claude-code-plugins/issues/9339)).

## [5.19.3] - 2026-10-27

### Changed

- intake-triage.yml now adds the `needs-triage` floor label itself, in an `intake-label-needs-triage` job that calls the same pinned ci-workflows reusable, so one run per issue event does both and the separate intake-label-needs-triage.yml workflow, with its own kill-switch and born-triaged jobs, is gone. The workflow also takes `reopened`: on a reopen only the kill switch and the floor label run, since born-triaged and the triage job are gated to `opened` (or a dispatch from main). A dispatch never adds the floor label. Each job keeps its own permissions; the label job holds `issues: write` only, as before.
- born-triaged reads its gate before it resolves the triage model, so a model config that fails still leaves the floor label its skip.
- The lost-run reconciler watches intake-triage.yml for a failed first attempt of an issues run and re-runs its failed jobs only when the `intake-label-needs-triage` job is the only one that failed. A run where triage, a gate or a broker job failed is left alone, so none of them runs again as github-actions[bot]. It lists a candidate's jobs only while the run ended in the last 2 hours (four passes), so a run it leaves alone costs at most 4 job listings, not one on every pass of the 24-hour lookback.

### Fixed

- pr-merge requests a whole review of an adopted owner pull request held only by findings a clean whole review would close, with the same bounds as a lane pull request, and the lane's own whole-review record at the current head no longer resets the adoption idle clock while no person has spoken since it ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [5.19.2] - 2026-10-27

### Changed

- maintenance-delete-stale-branches runs as two jobs. A plan job whose token writes nothing reads the branches, issues and pull requests and hands at most `max-deletes-per-run` candidates to a delete job as an artifact. The delete job alone holds `contents: write`, reads no issue or pull request text, and refuses a list for another repository, over the cap, or with an entry outside the rule's shape. No permission is added.
- The delete is one GraphQL `updateRefs` per branch with `beforeOid` set to the listed tip, in place of `DELETE git/refs/heads/<branch>`, so a push that lands after the delete-time re-read makes GitHub refuse the delete, the branch is reported as skipped, and a second ledger line with `notDeletedAt` records that it still stands.

### Fixed

- `ci-status` reads the lanes App's bot account id from the `AUTOMATION_LANES_APP_SENDER_ID` repository variable, its one source, at job level, instead of a literal id; the cost-hold step no longer sets its own copy. The trust-hold, cost-hold and lanes-hold steps keep failing closed, or keeping the hold, when the variable is not a numeric id. The lanes-hold step, which runs on every pull request and in the merge queue, fails red, and the cost-hold step keeps its hold, when the variable is not the trusted-actor id of `merge.agent-identity` in the base commit's `pr-pipeline.yaml`, now part of the base config checkout.

## [5.19.1] - 2026-10-27

### Fixed

- work-unblock re-fires an issue run whose broker-check `Ask the broker whether the lane may run` step failed for any reason but the lanes kill switch, or with no reason its log names, as a failed mint ([#9102](https://github.com/melodic-software/claude-code-plugins/issues/9102)). The read runner work-resolve-issue calls has no `Request the lane token` step, so such a run matched no no-work class and, past its one re-fire per version of the lane workflow files, waited on the stranded backoff. It now waits `limits.reset-clamp-min` hours after the run ended and is re-fired up to `limits.limit-stops-per-issue` times per version of those files, then on the stranded backoff, like a failed `Request the lane token` step. A kill-switch refusal there stays a breaker trip. The failed-mint backoff record now says the run could not get its lane token or the token broker's leave to run (`.github/scripts/work-unblock/label-unblocked.mjs`).

## [5.19.0] - 2026-10-27

### Changed

- The pr-merge hold-path floor now gives each glob a class (owner decision Q26 option B). `trust` (check-trusted-trigger, check-kill-switch, request-lane-token, CODEOWNERS, .gitmodules) and `gate` (every pr-merge script, the pr-merge and ci-status workflows, `babysit_merge*.py`, `babysit_risk.py` and `babysit_review_evidence.py` (they compute the review's clear condition), the rate guard, resolve-config and the pipeline config) still hold for a person. `enforcement` (the other modules the floored scripts import and the Python that decides the holds) no longer needs a person: the merge gate holds such a path as `review-path:<glob>` until the claude-security-review evidence binds to the head with no open finding, then arms it. ci-status leaves those paths to the gate. One classed list on each side, `HOLD_PATH_CLASSES` (`.github/scripts/pr-merge/merge-holds.mjs`) and `babysit_risk.FLOOR_CLASSES`, pinned equal by `test_merge_holds_sync.py`.
- The rest of `.github/scripts/pr-merge/` (gate-check, rotation, who, lane-records and the other scripts pr-merge.yml runs) joins the floor as `gate`, and both review callers' `hold-paths` and ci-status's exempt-author `hold_patterns` name them.

## [5.18.0] - 2026-10-27

### Added

- `patch-rules.json` has a `docs` row for a markdown-only patch. It allows only a path ending in `.md` (the new `markdown` allow rule). Besides the universal set it refuses a path under a `skills/` directory at any depth and a `SKILL.md` anywhere (the new `skills` and `skill-md` refusals, which apply only to a row that names them), each escalating `patch-protected-path`. Its cap, commit, moved-head path and reasons match `default`. No push job selects it yet: fix-docs's `apply-docs-patch` job keeps the `default` row until `pr-refine.yml` passes `patch-prepare: docs`.

## [5.17.3] - 2026-10-27

### Fixed

- The babysit wrapper's effective rung reads `babysit_loop_merge` from `docs/conventions/source-control.yaml` as well as `.claude/source-control.md` and takes the lower value, so a demotion written only to the YAML holds unattended merges ([#9726](https://github.com/melodic-software/claude-code-plugins/issues/9726)). While `.claude/source-control.md` exists it must set the key too, or the rung is `off`, so a raise needs both files; with no legacy file the rung stays `off`, as before, so the YAML alone never raises it. Either file the wrapper cannot read or trust (a rejected YAML or legacy file, an empty, non-scalar or unknown YAML value, an empty or repeated legacy H2) means `off`, never the other file's value alone.

## [5.17.2] - 2026-10-27

### Changed

- work-unblock re-fires an issue run that the lanes kill switch stopped at broker-check on the first hourly sweep after the switch clears, instead of waiting `limits.reset-clamp-min` hours after the run ended. That run ran no model, and the sweep runs only with the switch off. A trip at a post-model `Request the lane token` step still waits the clamp. The trip count, the stranded backoff past `limits.limit-stops-per-issue`, the WIP cap pause and `limits.restarts-per-run` are unchanged (`.github/scripts/work-unblock/label-unblocked.mjs`).

## [5.17.1] - 2026-10-27

### Security

- The schema refuses `scripts/run-test-file.sh` and skill-quality's `check-skill.sh`, the `verify-scripts` that run checkout code, on a skill whose effect is not `read`, since that skill runs in `pr-run-activity-write.yml`'s run job, which holds the lane token and `id-token: write`. A read skill with `applied-by.patch` still lists them; it runs in the read runner, whose run job holds neither. On such a skill, `checks` and `self-checks` may not name a script that runs the checkout's test files (`affected-tests.sh`, `run-outside-node-suites.sh`, `selection-audit.sh`, `check-guardrails-ps-differential.sh`, `run-test-file.sh`); `check-affected.sh --tests` stays allowed, since from the base copy it skips the branch's tests. The write runner no longer installs Python and pytest for the test-file runner ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#skill-activities)).

## [5.17.0] - 2026-10-27

### Added

- `merge.verify-cache` (default `shadow`) sets how enable-auto-merge uses the verifier refusals the last run kept. Each scheduled or hand-started run reads them from the newest trusted run's `pr-merge-verify-answers` artifact (`verify-answers.mjs`, found as the head-ref map is, never through actions/cache) and uploads its own, always, with 1-day retention. Under `shadow` every pull request is still read in full, and each read logs `verify-cache shadow: #<n> key=hit|miss stored=<kind> fresh=<kind> agree=yes|no|n/a`. Under `serve` an unarmed pull request whose kept refusal still matches is left unarmed on it with no further read, and, when an answers file is in use, is answered only from a kept refusal once the read budget is spent; without one it is not read past the budget. `serve` is set only once a day or more of scheduled runs has logged at least 50 `key=hit` lines, at least 5 for each kept refusal kind, and none with `agree=no`, on days with no `cache=error` line. A read whose cache work failed logs `verify-cache <mode>: #<n> cache=error`. An armed pull request is always read in full. A kept answer that holds nothing is read again in full and never arms. A kept refusal writes no new comment or label unless its reason changed. Each cost line shows `cached=0|1` when the answers files are in use.

## [5.16.0] - 2026-10-27

### Added

- address-feedback's thread file gives each kept thread `is_outdated`, true only when GitHub reports the review thread's `isOutdated` true, beside its `review_commit`, so a lane working a thread from an earlier review sees that its line may be stale. Edit scope still keys on paths alone.

### Fixed

- The pr-merge gate's Dependabot content rule, and its fix-scope check on a lanes App fix, count a manifest directory as covered only when `.github/dependabot.yml` lists its ecosystem and directory at both the base and the default branch head. Its review-only match reads the Dependabot policy at both too: an entry either side lists matches, and either side unreadable makes the policy unreadable. A tightening on main now reaches Dependabot pull requests opened before it.

## [5.15.9] - 2026-10-26

### Changed

- pr-merge's `merge` and `enable-auto-merge` jobs now skip a bot-sent `pull_request_target` run in the job condition, before the job joins its concurrency group. Such a run used to wait in the `queue: max` line and then stop at `who.mjs`, since a bot is never a listed human. `who.mjs` is unchanged and stays the check; schedule, `workflow_dispatch` and push runs are not gated on the sender.

### Fixed

- Lifting the lanes kill switch no longer leaves open lanes App pull requests red until a push or a manual re-run. The next `maintenance-reconcile-lost-runs` run re-runs the failed `ci-status` of each lanes App pull request whose newest checks run failed, on its first attempt, only because the switch was on, recorded so `pr-verify` trusts the re-run, at most three per run. While the switch is on, the reconciler still reads nothing.

## [5.15.8] - 2026-10-26

### Changed

- The pr-merge merge job reuses this run's post-merge report by the lane room's reuse rule (`babysit_verify_evidence.py settle`, `babysit_merge_policy.settle_shared`) in place of its 6-minute age and same-main test (`REUSE_MINUTES`), which never passed because the report's age counts from before its 6-8 minute check. A report whose check judged (exit 0, 1 or 5) is reused when `settle` keeps it, including at a moved main with no new lane merge; any refusal or failed read runs the check as before (`.github/workflows/pr-merge.yml`). post-merge-dispatch keeps the commit whose code ran its check beside the report, and both the merge job's reuse and enable-auto-merge's lane room (`POSTMERGE_CODE_SHA`) refuse or read the report again when the babysit-prs scripts or `docs/conventions/pr-pipeline.yaml` differ at their own commit, or that commit is missing. The merge job reads the agent identity with yq only for a fresh check.

### Fixed

- An issue lane run whose scan job refused its output (a patch over its 262144-byte cap, a leak-scan block, a payload that does not match its record) is now handed back naming that refusal instead of "The run wrote no readable outcome file". The read runner's `scan-refusal` job now uploads its `scan-refused-<lane>-<activity>-<attempt>` marker in issue mode too, the write runner downloads the `resolve-issue` markers for `report-outcome`, and `report-outcome.mjs` reads them only for a run that left no readable outcome (`.github/workflows/pr-run-activity-read.yml`, `.github/workflows/pr-run-activity-write.yml`, `.github/scripts/work-resolve-issue/report-outcome.mjs`).

## [5.15.7] - 2026-10-26

### Fixed

- The monitoring lane reads failed runs 100 to a page, up to 5 pages (`LIMITS.failedRunPages`), until it keeps 12 lane runs, so a page full of failing fork or pull-request runs no longer hides a failed run of this repository's own. When 5 full pages keep fewer, the read records a `failed runs` gap, which leaves signal 3's issue as it is.

- The work-resolve-issue lane stops a run whose change needs a path `apply-issue-patch` refuses at its first write to that path, instead of after the whole run, when the push is refused. The run's file tools and shell redirects are denied `Edit` on each such path. `deny-rules.mjs` builds those rules from `protected-paths.mjs`'s `PATH_RULES` for the `issue` row in `patch-rules.json`, and they match no path that row would push, so a plugin's `settings.json` stays writable. The preamble names the patterns and tells the run to stop with `exit` `stopped` and a `reason` starting `patch-protected-path`. `report-outcome.mjs` then hands the issue back naming `patch-protected-path`, before the run's own words. `apply-issue-patch` still refuses every path itself, including writes the rules do not cover, such as a wrapper subprocess.

- Lane scripts no longer fail an activity on one transient network error (undici `fetch failed`, `ECONNRESET`, `UND_ERR_SOCKET`). The shared client (`check-trusted-trigger.mjs` `retryServerErrors`) now times and resends a GraphQL POST whose document is a query, with no mutation, under its GET retry rules; a mutation is still sent once.
- `apply-patch.mjs`, `address-feedback.mjs` (publish-feedback, apply-dependency-verdict, verify-notes), `report-outcome.mjs` and `post-statuses.mjs` send a read, a GraphQL query, or a write that repeats to the same state again after a network error or a 5xx: at most 3 attempts, with a full-jitter wait of a random share of 4 s, then 8 s. The writes resent are the Git Data blob, tree and commit creates, a ref update, a pull request close, an issue label add or remove, and a commit status. After a `POST /pulls` that fails on the network, `report-outcome` reads the open pull request back and creates it again only when there is none. A comment, an issue, a ref create and any mutation are sent once. The wrapper is `retry-fetch.mjs`, one identical copy in each script directory, since each script runs from a copy of its own directory.
- `pr-unblock/dispatch.mjs` sends `Connection: close` on every request, so its workflow dispatch, which follows up to 5 x 10 s of waiting, goes out on a new connection rather than a pooled one GitHub may have dropped while it sat idle.
- The hold-path floor (`merge-holds.mjs` `HOLD_PATH_FLOOR`, `babysit_risk.py` `HIGH_FLOOR`, ci-status `hold_patterns`, and both review lanes' `hold-paths`) now holds `.github/scripts/pr-unblock/retry-fetch.mjs` and `.github/scripts/work-resolve-issue/retry-fetch.mjs`, which the floored `address-feedback.mjs` and `report-outcome.mjs` import.

## [5.15.6] - 2026-10-26

### Fixed

- pr-merge keeps the verifier's carried reads when the merge job's `pr-merge-run-cache` file does not read. `carry-run-cache.mjs read` now warns and treats that file as absent instead of dropping `pr-merge-verify-run-cache` with it; a failed trust check still carries nothing. The run cache section names both artifacts and what each carries.

## [5.15.5] - 2026-10-26

### Fixed

- pr-merge's carried verdict reads stay warm again. Since the run cache moved to the `pr-merge-run-cache` artifact, only the `merge` job uploaded it, and its gate reads no lane verdict, so the chain started empty and stayed empty: every `enable-auto-merge` verifier read started cold, ran into the 4-minute read timeout, and left lane pull requests unarmed. A scheduled or hand-started `enable-auto-merge` job, whose reader is the only one that fills `run-record`, now keeps its reads the same way and uploads them as `pr-merge-verify-run-cache` (1-day retention), only when it kept a read. `carry-run-cache.mjs read` takes each artifact from the newest trusted run on main holding it and adds only the verify file's `carried-*` sections to the merge job's file, whose other sections, the skip refusals included, are unchanged; `carry()` still filters every entry, and a carried read still counts only toward a FAIL.

## [5.15.4] - 2026-10-26

### Changed

- The `limits.api` defaults (each pool's `plan`, `writer-pause`, `breaker`, `read-floor`, github-token's `limit-cap`, content-creation's `per-minute` and `per-hour`) moved out of `pr-pipeline.schema.json` into [`.github/actions/log-api-budget/rate-limits.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/log-api-budget/rate-limits.json), their only copy, with the same values. The schema states no default for them now. The merge path floor (`merge-holds.mjs` `HOLD_PATH_FLOOR`, `babysit_risk.HIGH_FLOOR`, ci-status's `hold_patterns` and both review lanes' `hold-paths`) holds that file, so a change to a rate-limit default waits for a person, while a schema change does not.

## [5.15.3] - 2026-10-26

### Security

- `scripts/check-read-caller-keys.sh` now checks a read run's role secrets per caller. Every file of the run may name only the shared `fallback_claude_code_oauth_token`, `claude_code_oauth_token`, `claude_api_key` and `github_token`. A workflow whose run reaches `pr-run-activity-read.yml` may also name the role secrets in its own `CALLER_SECRETS` entry: `pr-refine.yml` and `pr-unblock.yml` the `pr_unblock_` names, `work-resolve-issue.yml` the `issue_lane_` names. Another lane's secret now fails with a message naming the caller and the secret. A workflow whose run reaches the read workflow with no entry in the map also fails.

## [5.15.2] - 2026-10-26

### Fixed

- Every CI `npm ci` on a GitHub-hosted runner reads npm's fetch bound from one file, `.github/npm-fetch.npmrc` (fetch-timeout 60000, fetch-retries 1, below npm's 300000 and 2): `pr-require-checks.yml` names it as npm's global config at workflow level, which covers each `run-tests.sh` install, and each other workflow's installing job names it at job level from its own checkout. A stalled registry request now gives up after two 1-minute attempts and a retry wait of at most a minute, where it could hold a job for three 5-minute attempts. `resolve-config`'s own install in `action.yml` is unchanged.

## [5.15.1] - 2026-10-26

### Changed

- ci-status's merge-queue step runs pr-merge's verdict reader (`babysit_verify_evidence.py evidence --base-sha`) from a checkout of main for a lanes App pull request at the head it merges, on a listing of its own, and holds on every FAIL class the gate counts, `verify:unreadable` and `verify:too-old` (`merge-holds.mjs` `evidenceHold`), so a FAIL uploaded after the pull request was armed still blocks it; a trusted approval of the head lifts the hold as it lifts a missing pass. A refusal the reader returns before it lists (`verify:too-old`, an unread config) holds the same way and the same approval lifts it. The reader starts from pr-merge's head-ref map and its `pr-merge-run-cache` artifact (`carry-run-cache.mjs read`; ci-status restores no Actions cache), so it makes about 73 requests where a cold reader makes about 860; with no carried run cache, or one whose carried sections are all empty, it reads cold only when GITHUB_TOKEN's core pool has 900 requests for each entry the merge queue builds at once (`max_entries_to_build` of the base branch's `merge_queue` rule) plus the `limits.api` read floor left (read once from `/rate_limit`), and holds otherwise; `ci-status`'s timeout is 20 minutes, up from 11, to fit a cold read. The pass names come from its listing in place of the four by-name lookups (`.github/workflows/pr-require-checks.yml`).
- enable-auto-merge reads the artifact listing once per run and shares it across its pull requests (`evidence --shared-listing`), where it listed again for each one its reader allowed and after every two minutes (`.github/scripts/pr-merge/enable-auto-merge.mjs`).

## [5.15.0] - 2026-10-26

### Changed

- The lane sweep's judge (`maintenance-audit-lane-runs.yml`) runs on ci-workflows' `run-claude-cli` as the `automations` role and spends its own API key, `AUTOMATIONS_CLAUDE_API_KEY`, in place of claude-code-action on the role's subscription token; claude-code-action never takes a key. A unit whose key leg hands off (a credit stop, a 401 or 402, or an empty key) with no permission denial is judged by the new `judge-subscription` job on `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`, and with `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, a unit that leg hands off by `judge-fallback` on that token. A matrix job's outputs are not per unit, so a handed-off leg uploads a marker artifact and the secret-free `judge-handoffs` and `judge-subscription-handoffs` jobs build the next leg's matrix from markers checked against a closed set (`handoff.mjs`). Each unit now leaves one `lane-sweep` lane record. `write-findings.mjs` reads the launcher's `structured-output-file`. The lane-funding catalog marks `automations` keyed and lists the three legs.

## [5.14.2] - 2026-10-26

### Fixed

- `apply-patch.mjs` drops a pull request push, as held, when the pull request body carries a body hold (a line opening with `Hold:` in any case after any whitespace, NBSP included, with a bare CR also ending a line, or "do not merge"), read with merge-holds.mjs's `BODY_HOLD`, unless the lanes App opened the pull request: there the line holds the merge, not a fix. It covers every pull request push, merge rows included. The lanes App's login is now one export of merge-holds.mjs, which `clear-escalations.mjs` and `refire-refused.mjs` read too, and the write runner copies merge-holds.mjs beside apply-patch's base copy.

## [5.14.1] - 2026-10-26

### Fixed

- pr-merge's `merge` and `enable-auto-merge` jobs no longer restore an Actions cache. They hold `id-token: write` and the lanes App token, and they restored the carried verdict reads by the bare prefix `pr-merge-run-cache-`. Any job in the default branch's cache scope can write that prefix, and the pinned restore extracts its archive into the workspace with no entry filter, so a crafted entry could replace a checked-out script before it ran (#9455). The carried reads and skippable refusals now travel as the `pr-merge-run-cache` artifact (`.github/scripts/pr-merge/carry-run-cache.mjs read`). Each job reads it from the newest scheduled or hand-started `pr-merge.yml` run on main whose head commit is on main, found the way the head-ref map is. The read removes any file at its path before it starts. The carried sections are still used only to count a FAIL. Only a scheduled or hand-started `merge` job uploads the file, since no other run's copy is read back, so a `pull_request_target` run no longer passes its reads to the next run. Permissions are unchanged.
- A workflow test fails when a job holding `id-token: write` or a lanes App token restores a cache by a `restore-keys` prefix in any workflow, local composite actions included. The test finds a grant at any indentation, quoted or not, and counts `permissions: write-all`. A second test fails when a token-holding job in `pr-merge.yml` restores any cache.
- pr-merge's head-ref map, lane records and carried run cache readers now also pass over every run while a tag named `main` exists, since a run on that tag reports `head_branch` main. `head-ref-map.mjs` `onMain` reads the tag (only a 404 lets a run count) and main's tip once per process through `check-trusted-trigger.mjs` `readDefaultBranchTip`, and remembers a failed or refused read so the process refuses every run. It then checks each run's head commit with `requireBehindTip`. `requireOnDefaultBranch` now composes those two helpers and behaves as before. The cost is two reads per process.

## [5.14.0] - 2026-10-26

### Changed

- `enable-auto-merge.mjs` adds the human-gated label only for a cause a person must clear (owner rule 2026-10-26): a refusal the gate marks `needsHuman` (an untrusted spec, the repeated-FAIL cap, a pull request too old to verify), the trust hold, a risk hold the gate marks `reviewsPerson`, a hold path, a cost hold, a listing past 300 files (a fourth page that is not empty; no later read completes it), or the lane's own hold line. A changed spec and a changed-file page that did not read get the comment alone, and the next scheduled runs judge them again. `merge-holds.pathHoldKind` reports a path hold's kind, so the routing reads no prose.
- A refusal the lanes clear that has stood at the head for `merge.risk-escalation-minutes`, timed from the first lane refusal noted there (the comment's `pr-merge-unarmed-since` line), shows as a failing `pr-merge/unarmed` commit status on the head; an arm, the refusal becoming a person's, or a member's veto or a person turning auto-merge off standing in for it posts a passing one over it; a run that read nothing new (no time left, unread hold paths, a verdict that did not read) leaves the status alone. The new `unarmed-status` job in `pr-merge.yml` posts them with the job's own token (`contents: read`, `statuses: write`, no lane token) and trusts only a status the GitHub Actions bot posted; the status is informational, not `ci-status`.

## [5.13.8] - 2026-10-26

### Fixed

- pr-merge.yml's full-run dispatch, in both jobs, now also sends again on Go's `net/http: TLS handshake timeout`, which fails before the request is written; a rate limit still stops the step red with no further send. The re-run step's `rerun-failed-jobs` POST and the full-run wait's send to post-merge-demotion-alert.yml take the same retry: at most three attempts, sent again after a capped full-jitter wait (up to 10 s, then 20 s) only when gh's error shows the request never left. A rate-limited alert send now stops red, sent once. The warning after a dispatch that never started a run now says a scheduled pr-merge run starts one only for a lane merge, and any other merge waits for the next push or pr-require-checks' own schedule.

## [5.13.7] - 2026-10-26

### Fixed

- Under `merge.lane-prs: native`, `clear-escalations.mjs` judges `enable-auto-merge`'s person refusal again at the head it was raised at, but only when its recorded verifier or risk cause is one the lanes clear (every code on `LANE_CAUSES`, a label set before its cause became a lane's): the gate's reader runs, and the label comes off as `refusal-cleared` when nothing refuses, or only lane causes refuse, read at least as far as the recorded one. A recorded cause a person clears (an issue link, a security finding, a trust-gate widening, a cost hold, a high path, an untrusted spec, the repeated-fail cap, an unknown code) is never read and never lifted at its head (owner decision Q-CLEAR B); a person removes the label, or the `head-moved` clear does once the head moves. At most three reader runs a run, rotated with the run number.
- `pr-merge.yml`'s merge job allows 45 minutes, up from 30, and the escalation clear step 15, up from 3, so the clear's reader runs fit beside the gate's own budget.

## [5.13.6] - 2026-10-26

### Fixed

- A head whose CI job ran past its `timeout-minutes` is no longer left red with no lane acting on it. GitHub ends such a job `cancelled`, and only its check run's annotation ("The job has exceeded the maximum execution time") says why; fix-ci-context and the fix-ci dispatcher now read that annotation and count the job as failing, so fix-ci works on the slow or hanging test, with the time-limit note in its context. A check cancelled with no such note stays skipped (`.github/scripts/pr-unblock/fix-ci-context.mjs`, `.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- The fix-ci dispatcher waits for the lost-run reconciler's one re-run of a cancelled, timed-out or start-failed first attempt, as it already does for an infra-only failure, so the two do not act on the same head at once (`.github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs`).
- The lost-run reconciler names each CI run lost again after its one re-run in its run summary, with who takes it (`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`).

## [5.13.5] - 2026-10-26

### Fixed

- Intake apply-verdict now writes a native blocked-by edge for each blocker the issue body names, not only those the triage model's `Blocked by:` line lists, so admission, which reads only native edges, no longer admits an issue whose blocker is named only in its text and the issue lane no longer hands it back to a person. A line that starts with `Blocked by` or `Depends on`, and each list item under a `Blocked by` or `Depends on` heading, names its `#<n>` references and this repository's issue URLs; fenced and inline code, HTML comments, `>` quotes, other repositories' references and pull request URLs name nothing, and a Markdown link, inline or by reference, counts as its target alone, so `[#12](<another repository's issue URL>)` names nothing. Each number is only a candidate: it gets an edge when GitHub answers it is an open issue of this repository, not a pull request, with no edge yet, at most 10 per issue, with the existing missed-edge handling. Edges are written on an escalated verdict too, so an `agent-ready` label a person adds later still finds them; an edge missed on a verdict that is not ready only warns, since no `status: ready` waits on it (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).

## [5.13.4] - 2026-10-26

### Fixed

- The fix-ci dispatcher no longer dispatches a head whose tested run ended `cancelled` when no check on the head failed, timed out or failed to start. fix-ci-context fixes only those, so each such run posted `Skipped: not-applicable` and spent the head's per-head cap on nothing. The dispatcher decides from the head's REST check runs through fix-ci-context's own `failingChecks`, so a failed job that a later contract-only run skipped still gets fix-ci (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, `.github/scripts/pr-unblock/fix-ci-context.mjs`, `.github/scripts/pr-unblock/dispatch.mjs`).

## [5.13.3] - 2026-10-26

### Fixed

- pr-merge.yml's full-run dispatch no longer waits out a rate limit and sends again: any 429, or a 403 with a retry-after, remaining 0 or a message naming a rate limit, fails the step red, naming the pool and the reset (with no header time, a minute on for a secondary limit and an hour on for any other, as the lanes' rate guard decides), and the candidate listing fails red on a rate limit instead of retrying it. enable-auto-merge's resend is pinned by a test never to resend an arm GitHub answered with 403 or 429. When a gate reader it starts (the per-pull-request verifier read or the lane-room read) exits 75 on a rate limit, enable-auto-merge holds that pull request and every later one as an unread room: it sends no further read, arm or note that run, disarms each armed lanes App pull request unless the GraphQL pool is the one stopped (then it names each one still armed), and fails red with the guard's error naming the pool and the reset. Either post-merge check (the post-merge-dispatch job's and the merge job's) that exits 75 on a rate limit now fails its job red once its outputs are written, with needs-dispatch false, and no dispatch, re-run or gate follows it. The re-run step's calls and the candidate listing go through the shared shell rate guard (`api-budget.bash`), so a rate-limited read or re-run POST ends it red instead of green. Those steps and the full-run wait also stop on gh's bare `Too Many Requests (HTTP 429)` message, where they used to retry. A rate limit that stops post-merge-dispatch (its check, its dispatch or its re-run) goes to the merge and enable-auto-merge jobs as its `rate-limited` output, naming the pool and the reset; each then ends red at its first step and sends nothing to GitHub.

## [5.13.2] - 2026-10-26

### Fixed

- work-unblock counts a run whose broker-check `Check the kill switch` step saw a kill switch on, and so skipped the broker ask, as a breaker trip. That run ends green with no failed step, so it was handed to a person as stranded with no report instead of being re-fired. The jobs listing alone shows it; no log is read (`.github/scripts/work-unblock/label-unblocked.mjs`).

- The issue lane's WIP cap counts a lane pull request as held when it carries `needs-human` or `do-not-merge` in any case (for example `Needs-Human`), as pr-merge's `enable-auto-merge.mjs` (`holdReason`) matches them, so a hold label with other casing no longer leaves the pull request in the countable total ([#8476](https://github.com/melodic-software/claude-code-plugins/issues/8476)). A label with a missing or non-string name is no hold, and the `Hold: a human merges this` body line still matches exactly.

## [5.13.1] - 2026-10-26

### Changed

- `pr-merge.yml` no longer wakes when `work-resolve-issue` finishes. That run could only disarm an armed pull request on a hold: an event run never arms (`enable-auto-merge.mjs` `READER_EVENTS`), and a pull request the issue lane just opened is not armed yet. The 15-minute schedule arms new lane pull requests as before, and `ci-status` still enforces every hold, on the pull request and in the merge queue. This removes about 1,000 run records and about 140 runner jobs a day.

### Fixed

- A pr-unblock run whose credential was refused (`class=auth`, a 401) now counts as a limit stop: its head waits `limits.fallback-reset` hours before the next dispatch instead of spending all `limits.limit-stops-per-head` runs at once, and the dispatcher logs a notice naming the class and the reset time (`.github/scripts/pr-unblock/limit-stop.mjs`, `dispatch.mjs`).
- `pr-run-activity-read.yml` now puts the lane record's class and reset on the check run it posts, so `limit-stop.mjs` can tell a usage limit or a refused credential from any other failure on resolve-conflicts, address-feedback and review-dependency checks; before, every such check read as a plain failure.

## [5.13.0] - 2026-10-26

### Added

- `limits.api.<pool>.limit-cap` sets the requests per window a GitHub API pool plans to: planned = min(header limit, `limit-cap`), used = header limit - header remaining, left = planned - used. `github-token` defaults it to 1000, GitHub's documented GITHUB_TOKEN limit of 1,000 requests per hour per repository, so an observed 5,000 header limit is headroom, never a target; the other pools have no cap. The rate guard's read floor is now a share of the planned budget, in the Node guard (`planOf` in `.github/actions/log-api-budget/rate-guard.mjs`) and in the shell guard (`API_BUDGET_LIMIT_CAP`, which ci-status sets to 1000). The stop still reads only the header's remaining and GitHub's 403 and 429 refusals, and `writer-pause` and `breaker` stay shares of the header's limit.

### Changed

- Each read-runner lane (pr-unblock's fix-ci, its rung-up, address-feedback, review-dependency and resolve-conflicts; pr-refine's fix-docs; work-resolve-issue's resolve-issue) runs its activity once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the role's OAuth token also stops (a limit stop, a credit stop, or a 401 or 402). Each handoff job reads whether the secret is set and passes it as the second call's `fallback-ready`; a `<subscription>-handoff` job reads this run's jobs and `<first>-fallback` runs on the fallback token alone. With the secret empty, the second call stays the last and the lanes run as before.

## [5.12.0] - 2026-10-26

### Changed

- pr-verify judges once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the pr-verify role's subscription token also stops (a limit stop, a credit stop, or a 401 or 402) with no permission denial: `check-intent-subscription` passes `fallback-ready` to run-claude-cli, and the new `check-intent-fallback` job runs on a third VM and records `fallback-reason` `limit-stop`, `credit-stop` or `auth`. With the secret empty, the subscription leg stays the last and the lane runs as before.

- No path is held for being trusted alone (owner direction 2026-10-24) except a narrow floor (owner decision Q-FLOOR (B)): ci-status's `merge-holds.mjs` `HOLD_PATH_FLOOR` keeps only `.github/actions/resolve-config/**`, `.github/actions/request-lane-token/**`, `.github/actions/check-trusted-trigger/**`, `.github/actions/check-kill-switch/**`, `.github/actions/log-api-budget/rate-guard.mjs`, `**/CODEOWNERS`, `**/.gitmodules` and the files that enforce it (owner decision [Q-ENFORCE (A)](https://github.com/melodic-software/claude-code-plugins/pull/9826#issuecomment-6401599691)): `.github/scripts/pr-merge/merge-holds.mjs`, `.github/scripts/pr-merge/enable-auto-merge.mjs`, `.github/scripts/pr-merge/superseded.mjs`, `.github/scripts/pr-merge/clear-escalations.mjs`, `plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py`, `.github/workflows/pr-require-checks.yml`, `.github/workflows/pr-merge.yml` (which runs those scripts and sets their environment), `docs/conventions/pr-pipeline.yaml`, and every module those scripts import (`.github/scripts/pr-unblock/address-feedback.mjs`, `.github/scripts/pr-unblock/gate-source.mjs`, `.github/scripts/pr-unblock/thread-scope.mjs`, `.github/scripts/work-resolve-issue/report-outcome.mjs`, `.github/scripts/work-resolve-issue/limits.mjs`), and the Python that decides the holds (`babysit_risk.py` and `babysit_verify_evidence.py`, which `enable-auto-merge.mjs` runs, with the 16 `plugins/source-control/skills/babysit-prs/scripts/` modules they import, `babysit_merge.py` and `babysit_merge_policy.py` among them), which `test_merge_holds_sync.py` derives from their imports and requires on the floor, equal to `babysit_risk.HIGH_FLOOR` and read from the base commit's module; a trusted person's approval of the head lifts it. The forced denied paths (the pipeline config and the trusted-actor list) are gone, and resolve-config no longer adds them to `merge.diff-check.denied-paths`: the floor holds the pipeline config, and the widening hold the trusted-actor list. This repository sets `high-path-floor: false`, which no longer turns off the floor. The trusted-actor widening hold and the review lanes still judge the rest.
- ci-status no longer holds a plugin or marketplace manifest change; the security lane flags it.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a cost path; the infrastructure-as-code cost paths stay.
- A body hold (`Hold:` or "do not merge") counts only when a person wrote or edited the body; in a lanes App body only report-outcome's own `Hold: a human merges this` line holds, so untrusted-provenance work still waits.
- The verifier pass binds a link of several issues that still names the judged one, linked the way it judged it; a link that drops the judged issue, a removed link included, holds it.
- `enable-auto-merge.mjs` comments on every refusal and adds the human-gated label only for a cause a person must clear: an untrusted spec, the repeated-FAIL round cap, a security finding (CRITICAL, or a path that could alias another, a symlink or a mode change), a trusted-actor widening, a cost hold, a hold path (a configured `merge.diff-check.denied-paths` match or a floor path, which only a trusted approval lifts) or report-outcome's own `Hold: a human merges this` line (owner decision Q-HOLDLINE; a reader run reads the discussion first so it comments once, and disarms an armed one at once). An issue link the lane does not take, a FAIL, a changed spec and any other risk reason get the comment alone.
- `clear-escalations.mjs` takes that label off once the head moves under `merge.lane-prs: native` too, including a label put back under a standing escalation comment; the next run labels the new head again only if its cause still holds.
- `enable-auto-merge.mjs` reads a pull request's labels and its comments, reviews and review threads whole instead of refusing past 100, arms nothing and labels nothing when the resolved config does not read, and starts each run at an offset that moves with the run number, so the pull requests past the verify budget change from run to run.
- ci-status's `merge-holds.mjs` holds a trusted-actor list change that adds or widens an entry (`actorsHold`, the rule of `babysit_risk._actors_widened`, base and head read at `BASE_SHA` and the head), so one pushed after auto-merge is armed waits for the owner; a trusted person's approval of the head lifts it, as it lifts a hold path, and a change that only removes entries passes.
- The review callers' `hold-paths` name every path-floor entry (`test_merge_holds_sync.py` checks both callers and ci-status's exempt-author `hold_patterns` each match all of them), adding `.github/actions/resolve-config/**`, `.github/actions/request-lane-token/**`, `.github/actions/check-kill-switch/**`, the rate guard (`.github/actions/log-api-budget/rate-guard.mjs`, which the trusted-trigger check imports), the merge-hold code (`merge-holds.mjs`, `enable-auto-merge.mjs`, `superseded.mjs`, `clear-escalations.mjs`, the `pr-unblock/` and `work-resolve-issue/` modules they import, `pr-require-checks.yml`, `pr-merge.yml`, and the babysit-prs Python that decides the holds) and the pipeline config (`docs/conventions/pr-pipeline.yaml`, whose lane slots the token broker reads), so the security lane reads those changes as trusted paths, and ci-status's exempt-author check fails a Dependabot, release App or standards-sync pull request that changes them.
- The review callers' `hold-paths` also name the security review's own files, `plugins/review/skills/security-review/**` and `plugins/review/evals/security-review-*/**`, so a change that weakens the review that judges trust controls gets the same scrutiny. They are scrutiny only: ci-status's exempt-author check does not fail on them, and nothing holds a pull request for them.

## [5.11.3] - 2026-10-26

### Fixed

- The pr-unblock dispatcher no longer fails its run when GitHub answers one pull request's read with a 5xx. A GraphQL query answered 5xx is now sent again with the same bounded backoff and per-attempt timeout as a GET (`retryServerErrors`). A mutation is still sent once: a document that names a mutation or subscription anywhere, or a request that names an operation, is never resent. A per-PR read that still answers 5xx after those retries logs a warning naming the PR and skips that PR until a later run, in fix-docs, resolve-conflicts, review-dependency and fix-ci (its hold read and its required-run read). A rate limit or any other read error still fails the run.

## [5.11.2] - 2026-10-26

### Changed

- `enable-auto-merge` no longer spends most of its lane-room time limit on a full post-merge check when the run's report was refused only because an issue the lanes App opened was edited since (`demotion-changed`). The room reads the demotion records alone and keeps the report when they are unchanged, so a slow API window no longer risks running past the time limit and disarming every armed lanes App pull request.

## [5.11.1] - 2026-10-26

### Changed

- The rate guard keeps a rate-limit reading of every guarded call under `API_BUDGET_TOKEN`, so every Node script's calls reach the job-end api-budget notice, not only `budgetedFetch`'s. The log-api-budget action adds an `api-calls <token>=N not-modified=M` line: this job's own calls, which the notice's `cost` (a counter every concurrent job shares) is not. The jobs that posted no notice now post one: intake-triage's born-triaged and refine-select, pr-verify's two judge jobs, pr-unblock's four select and context jobs, post-merge-demotion-alert's report-red-main, and the audit-lane-runs, delete-stale-branches, monitor-signals and reconcile-lost-runs jobs. No call is added.
- pr-feedback-dispatch's rerun-ci-status sends each repeat poll of the pr-require-checks run as a conditional GET on the last answer's ETag; a 304 stands for that answer, so the poll keeps its 60 s pace, its 10-minute cap and its decisions. Each 304's reading reaches the job's notice, which shows whether GitHub counts a 304 against `GITHUB_TOKEN`.
- pr-merge's dispatch-full-run sends each read of the full run after the first as a conditional GET on the last ETag; a 304 means the run is still going, so the wait keeps its three-minute reads, its 39-minute ceiling and its red-run dispatch.
- pr-unblock's report-escalation reads a pull request's comments 100 to a page, not GitHub's default 30.

### Fixed

- `enable-auto-merge` no longer leaves every lanes App pull request unarmed, and disarms the armed ones, when the run's post-merge report is one the gate would not reuse (for example `demotion-changed`, which any issue the lanes App files and triage then labels sets). The lane's room now checks the report again as the gate does and arms from that answer.

## [5.11.0] - 2026-10-26

### Added

- Adoption: a person's pull request skips the `idle-hours` wait when a trusted person's merge-queue enqueue was removed for failed checks (owner decision Q-REQ (a)). GitHub must have seen that head on the branch by the enqueue and not since, and no person may have commented or reviewed since the enqueue. The pr-merge gate records `eligibility.adoption` as `requeue-after-ejection` and then applies every gate rule unchanged, the `merge.max-queue-ejections` cap included.

## [5.10.7] - 2026-10-25

### Fixed

- The pr-merge lane's escalation to a person (risk, verifier, held-major and shared-copy) is posted as a new comment beside the human-gated label instead of an edit of its earlier comment, so the escalation notifies and the head-moved clear pairs the label with the newest escalation comment. An unchanged escalation is not posted again.

## [5.10.6] - 2026-10-25

### Fixed

- `enable-auto-merge` no longer re-arms a lanes App pull request whose head the merge queue has removed for failed checks `merge.max-queue-ejections` times (default 2) since it last changed. GitHub does not re-arm a pull request the queue removes, and each scheduled run armed it again, so a head that kept failing its merge group was re-queued without end. The count and the limit are the gate's own, read through `babysit_verify_evidence.py evidence --lane-queue`. At the cap the pull request is left unarmed with the gate's `<!-- babysit-merge-queue-ejections -->` comment and no label, since a push resets the count; a count that cannot be read leaves it unarmed.

## [5.10.5] - 2026-10-25

### Fixed

- The shell rate guard ends the step when it cannot record a stop (no space or no permission for `$RUNNER_TEMP/api-budget`), with an error naming the pool, and refuses every later call in that shell, so no call reaches an exhausted pool unrecorded. Its errors go to a copy of the step's stderr taken when the wrapper is set up, so they reach the log when a caller such as ci-status's `gh_read` holds the call's stderr in a file, and from a subshell every shell up to the step's is ended, so no retry loop around the call sends again. The Node guard names a stop it could not record in its error line.
- The shell and Node stop-file readers fail closed: a stop file that exists but cannot be read (no permission, a directory, a path part that is a file) holds every pool, with an error naming the file; a missing one holds nothing.
- The shell and Node stop-file readers take only lines shaped `<pool> <1-12 digits>` and ended by a newline, alike, so a fragment a short write left spoils only the line it runs into; `rate-guard.vectors.json` pins the reader cases for every port. Both guards cap a stop at the largest 12-digit second, so a huge `retry-after` still writes a stop the readers take.

## [5.10.4] - 2026-10-25

### Fixed

- `enable-auto-merge` posts a new refusal comment when it escalates a lanes App pull request to a person (the comment carrying the attended queue's escalation marker, written with the human-gated label), instead of editing its earlier lane comment. An edit sent no notification and kept the comment's old date, so the timeline showed only a bare label event with no visible reason. A refusal that stays a lane's still edits the one comment in place, and an unchanged person's refusal is not posted again.

## [5.10.3] - 2026-10-25

### Fixed

- The fix-ci dispatcher counts a head's earlier `pr-unblock / fix-ci` runs from the REST check-runs listing before it dispatches, instead of from the GraphQL check rollup, which lists only the newest run per check name. The per-head cap (`limits.limit-stops-per-head`) now stops a head that fix-ci-context skips each time, which was dispatched again after every base move. A head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- A head that reaches the per-head cap in fix-ci or resolve-conflicts now gets one `::warning::` annotation on the dispatcher run that finds the cap, naming the PR, the head and the run count. The head then goes into the dispatch record, so later dispatcher runs skip it without reading its hold, check runs or required run (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, `.github/scripts/pr-unblock/dispatch.mjs`, `.github/scripts/pr-unblock/limit-stop.mjs`).

- `enable-auto-merge` no longer arms, and disarms, a lanes App pull request whose linked issue carries a label naming untrusted work, in any spelling, or had one removed by a non-human. report-outcome already writes a `Hold:` line when the issue carries the exact label at PR open, so this covers a label added after the pull request opened, or any other spelling. The refusal is one a person clears: the pull request gets the refusal comment and the human-gated label.

- In the merge queue, `ci-status` now applies the trust hold to a queued pull request an automation opened. The step `Fail a queued pull request carrying a hold label` reads its linked issue: its closing issues here, or with none, the one plain `Refs:` issue. The step fails when that issue carries a label containing `untrusted` in any ASCII case, or had one removed by anyone other than a person on the base's trusted-actor list, or through an App. A lanes App pull request that does not link exactly one issue here fails too, so dropping the link after arming does not skip the check; another automation's that links none passes. A removal by a non-human stays in the issue's timeline, so no later label change lifts it; a new issue and a new pull request linking it do. report-outcome's `Hold:` line covers the exact label at PR open, and `enable-auto-merge` covers arm time, so the remaining gap was a label added after the pull request opened. A pull request armed before the label landed no longer merges on it. An unreadable link, label list, timeline or trusted-actor list, a bot author with no numeric id, or a jq error matching them, fails closed. This costs one GraphQL read per queued pull request, plus one timeline read per linked issue and a labels read for a `Refs:` issue when an automation opened it. A person's own pull request is not read.

## [5.10.2] - 2026-10-25

### Changed

- The pr-merge merge job now needs post-merge-dispatch, so it reads this run's kept post-merge report instead of racing its upload and running the same check again; on 2026-10-25, 20 of 43 scheduled runs read before the report was kept. `!cancelled()` keeps the job running on pull_request_target, where post-merge-dispatch is skipped, and when that job fails. The reuse rule (same main commit, under REUSE_MINUTES old) and the fallback to the job's own check are unchanged (`.github/workflows/pr-merge.yml`).

## [5.10.1] - 2026-10-25

### Changed

- A changed trust-gate path no longer holds a pull request by itself: the review callers' `hold-paths` only sends those files to extra security scrutiny, and the security lane judges them. An exempt author's pull request (Dependabot, the release App, the standards-sync App), which no review lane reads, still fails on a trust-gate path.
- The verifier fails a change to the takeover set only when it lets someone outside the organization gain trust or weakens a check beyond the spec, treats only a hold on a real charge (not model, effort, turn, timeout or schedule spend) as a hold the owner keeps, and passes a diff too large to judge whole with notes naming the parts it could not judge when those parts are prose or data; an unjudged workflow, action, script, hook, binary or takeover-set file still fails.
- ci-status's cost-only clear is no longer blocked by every lanes App comment in the window, only by a lanes App escalation comment.
- The lost-run reconciler re-runs, once, a pr-verify run whose first attempt failed or was lost before or during its judge step. A run whose verdict write started, which happens only when the judgment succeeded, is held, with the reason in the run summary, even when writing or uploading the verdict then failed, so a head is never judged twice. pr-verify fails a run the lanes kill switch stopped, so the reconciler re-runs it once the switch is off instead of leaving the head with no verdict.

## [5.10.0] - 2026-10-25

### Added

- Intake's size split also copies, as written, the task-list lines of intake's refinement comment on an issue a listed human filed, where admission already counts that comment as spec. A Size Large issue whose done-when lives only in that refinement no longer stays parked with no one asked. Each sub-issue that copies a refinement line names that comment's id and update time in its header.
- Admission and pr-verify trust such a sub-issue only while the named comment is still intake's newest refinement on the parent, never edited, with its update time equal to its creation time or to the recorded one, and only on a parent body a listed human wrote. Every line must be one of the listed human's task-list lines or one of that comment's task-list lines, never its prose; after a listed human's edit, either kind may also have its box ticked, and nothing else. A deleted, edited or superseded refinement makes the sub-issue untrusted, even when a listed human has edited it since.

### Changed

- `merge.rung` is a pacing cap: no work class is read, and no class, missing class or diff shape caps it. The only check that names a class is the local babysit lane's untrusted-provenance hold. That lane also needs a human to vouch for the linked issue: a write-access human wrote it, or one applied the admission label in person with no body edit after. The risk score's `class-contradicted`, `blast-radius-missing` and rung reasons are gone (#9668).
- `merge.diff-check.c2-contradictions` is deprecated and has no effect. The schema still accepts it so existing configs validate, and a config that sets it true gets a `configNotes` entry in the gate's `unattended` report saying it has no effect.

- `resolve-issue` reads any web page and runs the research skills; it was limited to six official docs hosts. It runs on the run-claude-cli launcher, which stages no curl-based docs script, from a job with no write token, and admission no longer refuses a done-when item for naming a page outside those hosts ([pr-pipeline.yaml](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline.yaml)).

### Fixed

- fix-ci no longer hands a pull request to a person (`ci-fix-escalated`) in the same run that pushed its fix: a written patch now pushes with no escalation, whatever the model escalated beside it, and the new head's own CI decides. A red new head gets its own fix-ci run, which escalates what it cannot fix, and `loop.fix-ci-rounds` still ends the rounds with `ci-fix-round-cap` ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).

- The issue lane's blocker gate counts the same closes admission does: a size-split parent the lanes App closed once a listed human or a merge closed every sub-issue no longer blocks a run admission already let through (`.github/scripts/work-resolve-issue/check-blockers.mjs`, now on `admit.mjs` `closedByTrusted`).

- The pr-pipeline convention names the repository's default branch, not the pull request's base, as where the merge gate reads admission's `task-list` for a size-split sub-issue.

## [5.9.5] - 2026-10-25

### Fixed

- pr-unblock's publish-feedback step loads again. It runs from a copy of `.github/scripts/pr-unblock/` alone, and the adjudicator module it imports had started loading `request-budget.mjs`, whose `.github/actions` imports do not resolve from that copy, so every address-feedback run failed at publish with `ERR_MODULE_NOT_FOUND`. `adjudicate-feedback.mjs` now loads `request-budget.mjs` only in its `prepare` command, which runs from the full base checkout.

## [5.9.4] - 2026-10-25

### Fixed

- The adjudicator of a disputed review finding now reads the whole review comment and the files and lines it cites, beside the locations the fixing lane cited, instead of only the comment's first paragraph and the lane's locations (`.github/scripts/pr-unblock/adjudicate-feedback.mjs`).
- A disputed code-review finding carrying `severity: CRITICAL`, and a disputed pr-verify verifier note, go to a person again instead of to the adjudicator: resolving a verifier note's thread left its FAIL holding the merge with nothing to say so.
- pr-unblock's `adjudicate-feedback` job runs only when the answering leg's replies hold an `INCORRECT` reply; a round with none no longer checks out, sets up and stages for nothing. Its contents reads are logged in the job's api-budget notice.
- The monitoring lane's rolling issues render each finding's summary inside a text fence, in the body and the change comment, so a mention, link or tag in run or job text no longer works.

## [5.9.3] - 2026-10-25

### Changed

- The pr-pipeline README describes how pr-merge's gate counts a size-split sub-issue the lanes App filed as trusted spec. It does so on the same rule pr-verify applies: every line after the header must be a trusted task-list line of its native parent, or on the edited path that line with its box ticked. A failed read is `verify:unreadable`, and a cut comment page counts nothing.

### Fixed

- work-unblock tells a run the token broker refused for the lanes kill switch, at broker-check or at a lane token request, from other failures by reading the refused job's log (one per run, at most 1 MiB, only the failed step's last line). Such a breaker trip is re-fired an hour after it ended with a record of its own, and past `limits.limit-stops-per-issue` trips on the stranded backoff; it no longer spends the once-per-version re-fire, counts toward the failed-mint bound, or posts the "fault in the lanes" backoff comment. A refusal for another reason, or a log it cannot read, is classed as before (`.github/scripts/work-unblock/label-unblocked.mjs`).

## [5.9.2] - 2026-10-25

### Fixed

- Intake apply-verdict no longer stops the whole verdict when GitHub answers a blocked-by edge read or write with 403, 429 or 5xx: that edge is missed and named in the step summary and a run annotation, and the verdict's other labels still land. Admission and work-unblock read blockers only from the native edges, so the edges that run wrote are deleted again, and a ready verdict with a missed edge lands without `status: ready` and is not admitted; the hourly triage sweep runs intake again on it, and after two runs that leave it so hands it to a maintainer. A 403 fails the job after every write, since no re-run fixes a missing permission (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).
- Intake refinement no longer lifts the lanes App's `status: needs-decision`, on an exact refinement or a split, while the App's verdict comment lists a security or cost flag or records that whether an earlier verdict flagged is unknown, so an earlier flag a later triage omitted can no longer clear through a refinement and the re-triage after it (`.github/scripts/intake-triage/refine.mjs`).

### Security

- A size-split sub-issue a listed human last edited counts as that human's text only when every line after its header is one of its parent's trusted task-list lines or that line with its box ticked. GitHub names only the last editor, so a listed human ticking a box after another account's edit no longer makes that account's text trusted.
- pr-verify stops, writing no verdict, when a split sub-issue's native parent cannot be read or has more comments than the page it reads, instead of judging the pull request without the sub-issue's criteria. Before, an outsider could pad the parent past the page during a run and delete the padding before the merge gate counted the sub-issue.

## [5.9.1] - 2026-10-25

### Changed

- The hourly work-unblock sweep reads closes from 15 minutes before the last scheduled run whose labeling step succeeded (at most 3 hours back; the full 3 hours when that run cannot be read or did not sweep, as under the kill switch or a lane the config turns off) instead of always the last 3 hours. Metric: sweep passes per closed issue. Baseline: about 3 (hub measurement). Expected: about 1.

- enable-auto-merge logs each verifier read's cost, `enable-auto-merge: #<n> calls=<total> github-token=<n> paginated=<n> ms=<elapsed>`, read from the reader's `babysit-gh-calls` stderr line, and adds the same rows to the step summary even on a run that raised nothing. `calls` counts gh invocations; a paginated one (the artifact listing) made one request per page. A reader that exits non-zero is now reported by its last error line, not by the calls line (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
- pr-merge's merge job records each gate candidate's gh invocations as `calls` in its summary row (`.github/workflows/pr-merge.yml`).

## [5.9.0] - 2026-10-25

### Added

- Intake splits an issue admission parked as Size Large into native sub-issues before any run takes it (owner Q93). The refine model returns only item numbers: the parts over the issue's task-list lines and the order between them. Each part becomes a sub-issue holding those lines as written and taking the issue's Issue Type, the order becomes native blocked-by edges (a refused edge leaves the split unfinished for the next triage to retry), and intake triages each sub-issue. An invalid split leaves the issue parked, with the reason in the step summary.
- Admission and pr-verify count the body of such a sub-issue as the text of the listed human who filed its parent when every line after its header is one of the parent's trusted task-list lines and nobody edited it, or when a listed human last edited it (ticking a task box is an edit). An edit by any other account makes it untrusted. Admission does not park or refuse such a sub-issue for Size Large, since it never splits again.
- Admission waits on an issue while any of its sub-issues is open, and work-unblock closes a split issue as completed once every sub-issue is closed by a listed human or a merge.

### Security

- collect-base-activity makes the base marketplace copy read-only (`chmod -R a-w`) once it is staged, and a write skill's `--disallowedTools` carries `Edit(/$RUNNER_TEMP/base-marketplace/**)`, so neither the skill's file tools nor a process it starts can rewrite the plugin hooks and scripts that load in place from that copy ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

## [5.8.1] - 2026-10-25

### Fixed

- An issue's closing pull requests count only the open ones: GitHub lists a merged pull request in `closedByPullRequestsReferences` despite `includeClosedPrs: false`, so admission and the work-unblock sweep waited on a merged closer forever and find-prior stopped the issue lane for one (`.github/scripts/work-resolve-issue/report-outcome.mjs`).

## [5.8.0] - 2026-10-25

### Added

- `limits.api` sets GitHub API margins per pool (`github-token`, `lanes-app`, `graphql`, `owner-token`, `content-creation`), each a share of the limit the pool's `x-ratelimit-limit` header reports: `plan` (0.7), `writer-pause` (0.4), `breaker` (0.2) and `read-floor` (0.1); `content-creation` adds `per-minute` (80) and `per-hour` (500). The defaults live only in the schema. The rate guard reads only `read-floor`; the other fields are thresholds meant for the hub's limits sampler, not enforced here. resolve-config passes the block through as set.

### Changed

- Every lane GitHub call made through createGitHub, the dispatchers' budgetedFetch or the ci-status gh wrapper goes through one rate guard (`.github/actions/log-api-budget/rate-guard.mjs` and its shell port in `api-budget.bash`). A response that shows a pool exhausted (remaining 0, any 429, a 403 naming a rate limit or abuse detection, retry-after, or a GraphQL answer of any status with a `RATE_LIMITED` error or an error naming a rate limit) stops that pool, or every pool for a secondary limit or a 429, until its reset for the rest of the job: later calls are refused without a request, a call GitHub refused fails (one it answered with a 2xx keeps its answer and status, so no write is resent), and a Node step fails red with an error naming the reset. With no usable reset header, a secondary limit stops for a minute and any other limit for an hour; a paginated `gh api` call, whose headers the wrapper cannot see, gets the same from its error text. Under `read-floor` left it warns once and calls continue; ci-status sets the gh wrapper's floor to the schema default. ci-status's gh_read no longer sends a probe request while limited, and waits only for a reset a header gave, never a guessed one. A rate limit on check-born-triaged's read sets its new `rate-limited` output, which stops intake-triage and the needs-triage label. The check-born-triaged read, post-statuses and the maintenance, branch-cleanup and post-merge-demotion-alert scripts' raw API calls go through it too.
- intake-label-needs-triage reads the org and repository kill switches, as intake-triage does; either one stops its API reads and its label.

### Fixed

- The issue lane no longer runs an agent-ready issue that a `blocked_by` issue or pull request still blocks (owner decision Q95). A blocker stops blocking only as admission judges it: a pull request merged in this repository, or an issue closed, for any reason, by a listed human or, in this repository only, a merge; another repository's issue is read there. Admission, work-unblock, the lane's gate and the queued count now share that one rule (`admit.mjs` `blockerDone` and `stillBlocking`).
  - The admit job checks the blockers after the trusted-trigger check. A blocker that still blocks, or blockers it cannot read, skip the run with a notice or warning. The skip takes no model turn, adds no `needs-human`, and leaves `agent-ready` on.
  - work-unblock's sweep never re-fires, strands or hands to a person an agent-ready issue that a blocker still blocks. Once no blocker blocks, it re-fires a run the gate skipped.
  - The same admit step applies admission's provenance rule (`admit.mjs` `untrustedHold`) to a label added by hand. An issue carrying `work-class: untrusted-provenance`, or whose newest removal of it was by neither a listed human nor the lanes App, stops for good with a notice. The sweep never re-fires it and adds no `needs-human`. Labels or events it cannot read skip with a warning, and the sweep retries.
  - Admission no longer keeps an issue out of `admission-deferred` because work-unblock's sweep would not count its blockers: the sweep now counts them by the same rule, so the issue defers and waits its turn oldest first like any other.
  - The WIP cap's queued count leaves out agent-ready issues that a blocker still blocks. It makes at most 30 blocker reads per check.
  - Files: `.github/workflows/work-resolve-issue.yml`, `.github/scripts/work-resolve-issue/check-blockers.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`, `.github/actions/check-wip-cap/check-wip-cap.mjs`.

## [5.7.0] - 2026-10-25

### Changed

- Past the address-feedback round bound (`loop.review-rounds` plus the one fresh fixer round), a pull request whose open findings all come from the code review lane no longer skips `cost-gated` and waits with no label. It escalates `feedback-not-converging` with the human-gated label and a comment that names each open review thread and gives its own resume steps: resolve the open threads, or reply on one with a write-access fix request and dispatch the lane, since removing the label alone would stop again on the same head. No sweep, schedule or dispatch starts another automatic round; a write-access fix request still gets its own round, and a security or intent finding or a pull request a person gated still escalates `feedback-round-cap` (`.github/scripts/pr-unblock/address-feedback.mjs`, `.github/scripts/pr-unblock/report-escalation.sh`).
- The address-feedback round marker reads `round <N> of max <M>`, M being the cap plus the fresh fixer's round, and a round-cap escalation's neutral `address-feedback` and `publish-feedback` checks add the same line to their summary through `report-check-run`'s new `not-run-detail` input, which shows only that line.

- `work-resolve-issue`'s `resolve-issue` runs on ci-workflows' `run-claude-cli` instead of claude-code-action, on `ISSUE_LANE_CLAUDE_API_KEY` first, in `dontAsk` with an explicit allow list. When that call hands off (an empty key, a credit stop, or a 401 or 402), a new `resolve-issue-handoff` job reads so from the run's job conclusions through the shared `handoff-evidence.sh` and `resolve-issue-subscription` runs the activity again on `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`; every later job takes the call that ran. See [Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode).
- On the launcher, an issue lane's check and verify-script wrappers are staged under `.lane/` (read-only, denied to the file tools), `issue.json` goes to the writable `.lane/scratch`, and its skill reads git only through a staged `git-read` wrapper that runs `git status`, `diff`, `log` and `show` and refuses options that write a file or read one outside the checkout. See [Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each).
- The read runner's launcher step and leg timeouts now derive from the run job's `timeout-minutes` (10 and 15 minutes under it); the issue sizes' timeouts grow by 15 minutes (small 65, medium 115, 40 without dimensions) so each leg keeps the time its turn budget was set for, and a first call hands off on `run-claude-cli`'s `handoff` output, which adds a 401 or 402 to the credit stop, in PR mode too.
- `resolve-issue` routes to the `code-fix` model profile, since the launcher needs a model alias; the reuse summary pass also runs on the launcher.
- A run the launcher stopped at its leg timeout (class `timeout`) with no outcome of its own is now a turn-cap stop: it keeps `agent-ready`, work-unblock restarts it within `limits.turn-cap-restarts`, and the next run resumes its branch, instead of handing back as `stopped`.

- An issue run of the read runner (`work-resolve-issue`'s `resolve-issue`) now hands its reply, run fields, patch and outcome files to the scan job only sealed to the scan-carrier key, as a PR-mode run does. The scan job opens them, scans them for credentials, and is the only job that uploads them; the run job uploads nothing and shows no model text in its step summary. See [The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job).
- The read runner's patch outputs now come from the scan job alone. Its issue outputs (`scan-issue-run-started`, `scan-reuse-branch`, `scan-resume-branch`, `scan-resume-tip`, `scan-base-sha`) come from a new `issue-fields` job, which runs whatever the run job's result, holds each run job field to its closed set and combinations, and re-derives any branch claim with the default-tip earlier-work check. `work-resolve-issue.yml` reads only these, and the reuse summary job takes its code from the default branch tip. The run-job-sourced `issue-run-started`, `reuse-branch`, `resume-branch`, `resume-tip` and `base-sha` outputs are removed.
- The skill's `work-outcome.json` is cut at 48 KiB, down from 64 KiB, so every sealed payload at its cap still fits the five chunks a job's outputs hold.

## [5.6.0] - 2026-10-25

### Changed

- work-unblock and the hourly triage sweep no longer stop an item for a person outside an intent or security question (owner intent, 2026-10-24):
  - A stranded issue already re-fired on its lane workflow files, or a lane token request that keeps failing, is re-fired again on a backoff (three hours, doubling, at most 24) with one comment edited in place, never `needs-human`.
  - A lanes App PR merged with `Refs:` or closed unmerged takes `status: ready` and `agent-ready` off and adds no `needs-triage`, so the triage sweep sends the issue back to intake, whose fresh `status: ready` re-admits it.
  - A blocker closed by a listed human or a merge in this repository counts whatever its close reason, and another repository's blocker counts once a listed human closed it there (a merge there, or another repository's pull request blocker, never counts).
  - A listed human's open pull request for an issue counts as work running on it, so work-unblock does not re-fire or relabel it.
  - The triage sweep re-dispatches intake for any issue with no `status:` label and no `agent-ready` or person's hold, whatever comments intake left (an issue the lanes App opened included), and for a born-triaged issue in `status: ready` that nothing admitted. After two dispatches in one triage cycle (a work-unblock hand-back starts a new one) it labels the issue `needs-triage` and says so in its own comment on the issue, instead of filing a new issue, and later passes skip that issue unread while it carries `needs-triage`.
  - Admission on a blocker's close takes the issues it would label oldest opened first (owner Q95) (`.github/scripts/work-unblock/label-unblocked.mjs`, `.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`).

## [5.5.1] - 2026-10-24

### Fixed

- A handoff job's log now shows the decision: `handoff-evidence.sh` prints one line naming each settled fact and the read count, such as `handoff evidence: posted=false allowed=true (1 read)`, before it exits successfully (`.github/scripts/lib/handoff-evidence.sh`).

## [5.5.0] - 2026-10-24

### Added

- Intake writes a native blocked-by edge for each open issue in the repository the triage names on a new `Blocked by: none|#N[, #M]` verdict line, before admission reads the blockers; only `#<number>` tokens count, the issue itself, pull requests, closed and other-repository issues and existing edges are skipped, and at most 50 are written (`.github/scripts/intake-triage/edges.mjs`, `.github/workflows/intake-triage.yml`).

### Changed

- Intake admission now treats a blocker closed as not planned or a duplicate as no longer blocking, and reads another repository's blocker there instead of waiting on it for good. A blocker here still needs a close by a listed human or a merge; another repository's blocker counts only on a listed human's close.
- Intake admission takes the unblocked issues oldest first: an issue that passes the rules while an older open issue waits in `admission-deferred` is deferred behind it, and the hourly sweep admits them in order. While the sweep still counts only completed or merged blockers in this repository, an issue that rests on any other blocker never gets `admission-deferred`, which the sweep would drop without admitting it: with room it is admitted without that wait, and with the lane full it waits with a comment.
- The admission refusal comment no longer asks a person to add `agent-ready` by hand; it names what admission needs.
- An issue admission would refuse only for Size Large (split at intake pending, owner Q93) is parked instead: it keeps `status: ready`, gets no `status: needs-decision`, loses `admission-deferred` and gets a comment naming what it waits on. Any other refusal reason still refuses and names both.

- Intake triage stops an issue for a person only on intent or security. A `status: needs-decision` or `status: needs-info` the lanes App set on an earlier run gives way to a clean verdict and is taken off only when the App's earlier verdict comment lists no `flagged:` reason; a listed flag, or no App verdict comment at all (an issue held before these comments), keeps the hold, and the new comment carries it forward; `needs-human` is never lifted, whoever set it, and a hold from the triage run's own escalation, a listed human or an unread setter still holds. A `needs-triage` the triage left no longer keeps a clean verdict from `status: ready` and is taken off after the verdict. An issue field a listed human set to another value is kept and is the value admission reads, without a hold; one from any other setter still holds. GitHub keeping other field options than `models.issue-dimensions` maps fails the run without adding `status: needs-decision`. Whenever the verdict sets `status: needs-decision`, the reasons go on the issue in one lanes App comment edited in place, not only in the step summary; a held verdict writes that comment before its labels and, when the write fails, adds no label and removes none but `status: ready`, names the failure in the step summary and fails the job, so no hold lands without its record; a ready verdict that admission refused or did not finish leaves that comment too, and a failed write there still rewords the lane comment and fails the job (`.github/scripts/intake-triage/apply-verdict.mjs`).

### Fixed

- ci-status fails a ready pull request whose review lane the kill switch stopped (`CLAUDE_LANES_DISABLED`, `CLAUDE_LANES_REPO_DISABLED`, or a lane's own `CLAUDE_REVIEW_DISABLED` or `CLAUDE_SECURITY_REVIEW_DISABLED`), naming the lane: "did not run on <head> (<run>): a kill switch was on when it started. Once it is off, re-run all jobs of <run>; ci-status re-runs when it finishes." Before, a stopped lane passed, so a head pushed while the switch was on could merge with no review. The kill switch pauses review and never waives it; the admin bypass stays the break-glass.
- ci-status reads only review runs from this repository's head. A fork's run on the same commit, even the newest, no longer decides a lane, and a pull request whose head is a fork fails as a fork before any run is read.

## [5.4.0] - 2026-10-24

### Changed

- Intake refinement no longer stops an issue for a person on its own: a split of done-when items an unattended lane run cannot perform files no `needs-human` child issue, and lists those items in the refinement comment as checks a person runs, leaving the rest of the done-when in the body for admission; the lanes App refines each version of an issue body once instead of each issue once; an exact refinement that finds a duplicate or fixing change asks whether to close the issue instead of failing the run; and an issue edited while the model ran is triaged again instead of left waiting (`.github/scripts/intake-triage/refine.mjs`, `.github/workflows/intake-triage.yml`).
- work-unblock lifts the `needs-human` hold report-outcome put on an issue for a lanes App `Refs:` pull request when that pull request closes unmerged, not only when it merges, and hands the issue to triage (`.github/scripts/work-unblock/label-unblocked.mjs`).

### Fixed

- The lane sweep's file step drops a finding whose slice is not its unit's, whose workflow is not its slice A or D unit's, or whose job is not among the jobs its unit's data lists, so a judge steered by CI log text cannot put a finding in the digest against a workflow or job its unit does not show. A unit that lists no jobs leaves the job unbound; the free-text signature still lets a steered judge mint fresh fingerprints, which land only as digest entries, at most 3 per unit.

## [5.3.0] - 2026-10-24

### Changed

- The monitoring lane keeps one rolling issue per signal, `Monitoring: <signal>`, in place of one issue per signal and key. It rewrites the body and adds a comment only when the signal's state changes, closes the issue when the signal clears, and reopens the same issue when it fires again; it never files a second. GitHub incidents are listed in the run summary and no longer filed. Open issues from the per-key form are closed as not planned, pointing at the signal's rolling issue (`.github/scripts/maintenance-monitor-signals/`).
- The lane sweep writes its findings into one rolling digest issue, `Lane sweep: open findings`, in place of filing an issue per finding. A sweep whose findings or their tracking issues changed replaces the body, so a fixed finding drops off; when the collector or a judge leg read only part of the day, earlier entries carry over (`.github/scripts/maintenance-audit-lane-runs/file-findings.mjs`, `findings.mjs`).
- Neither lane labels its issues `needs-triage` any more; each keeps its `source:` label. Each rewrite takes `agent-ready` off the rewritten issue, since a person vetted the earlier text. The [pr-pipeline README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane) has the rules.

- A review finding `address-feedback` answers `INCORRECT` no longer hands the pull request to a person. pr-unblock.yml's new `adjudicate-feedback` job gives a fresh-context model, once per disputed thread (up to three a round), the finding's claim without its rationale, the locations the lane cited without its note, and those files at the head. It runs on `run-claude-cli` under `dontAsk` with Read alone, confined to its own slot by Read denials on the base checkout and the runner's temp directory (where the lane's replies, with its reasoning, sit), with each staged file under a `.txt` suffix so a cited `CLAUDE.md` is never loaded as instructions, and returns `lane`, `reviewer` or `human` as structured output. The model route is the new run route `adjudicate-feedback`, on the `review` profile (Opus), above the review lanes' `pr-review` (Sonnet at effort high). `publish-feedback` applies the verdict with fixed text: `lane` replies and resolves the thread; `reviewer` replies that the finding stands and leaves it open, and the next round works it again (`threadAuthors` keeps it); `human` escalates `feedback-question-intent`, `feedback-question-design` or `feedback-question-security`. A thread a trusted person directed (a fix request, or a reply after an escalation) is not adjudicated: an `INCORRECT` reply on it escalates `feedback-disputed`. Only a code-review lane finding (a github-actions[bot] comment ending in the `claude-lane: claude-review` footer; the same footer in a claude[bot] comment, whose body the model writes, names no lane) or a verifier note is adjudicated: a disputed security-review finding, or one whose lane its comment does not name, always goes to a person as `feedback-disputed`, and no verdict resolves it. A thread whose finding stood is not adjudicated again: the next round's `INCORRECT`, `UNCERTAIN` or `VALID-defer` on it escalates `feedback-disputed`. No verdict escalates `feedback-unadjudicated`. A stands verdict in a round that left the head unmoved, so no review run follows, skips the reply check as the new `finding-stands`, and `pr-feedback-dispatch.yml`'s half-hourly sweep dispatches that head again, as it does after `no-model-turn`; the select job's round cap and the sweep's three skips per head bound it. Verdicts are checked against the head the select job read, so a round that pushes a fix for one thread still applies the verdict on another. The write file takes `review-adjudication-attempt` and `review-adjudication-sha256`. No label is added; `fix-ci`, `resolve-conflicts`, `fix-docs` and `apply-patch` keep running while a thread is disputed, and the open thread still holds the merge.

### Fixed

- A handoff no longer depends on step data GitHub's jobs listing can return late or empty. Every handoff read (pr-unblock's five handoff jobs and `fix-ci-unreported`, and pr-refine's `fix-docs-handoff`) now runs one script, `.github/scripts/lib/handoff-evidence.sh`, which decides from job-level conclusions first: a skipped report job means no check was posted, and a new read-runner job, `broker-allowed`, succeeds only on broker-check's allow. Only a report that ran is read through its step, and that read is retried with backoff for about five minutes, then fails the job with one error line naming what stayed missing. Before, an empty step list read as "not allowed", so an empty or credit-stopped key ended the item stopped instead of starting the subscription leg, and as "not posted", which started a second leg after a call that had posted.

## [5.2.1] - 2026-10-24

### Changed

- Intake triage no longer holds an issue for cost when the work only spends from a flat or prepaid source: model runs, lane runs and `claude plugin eval` passes bill the prepaid API keys, which do not auto-refill (owner Q37). Only a new or renewing charge (Actions billing, Azure, a key or plan that renews or auto-recharges) is cost (`.github/workflows/intake-triage.yml`).

## [5.2.0] - 2026-10-24

### Added

- intake-reenter sends an issue back to intake triage when a listed human removes `needs-human` and leaves no `status:` label, no `agent-ready` and an author intake admits.

## [5.1.0] - 2026-10-24

### Changed

- On an issue whose body a listed human wrote, and last edited if ever, intake triage's newest refinement comment (opening `<!-- intake-triage refinement -->`) by the lanes App now counts as spec while it is unedited: pr-verify's `resolve-pr.mjs` gives it to the verifier as spec text when it was posted before the pull request opened, and admission (`admit.mjs`) counts its task list for criterion 7. The lanes App is the trusted-actor list's id for `merge.agent-identity` in pr-verify and the list's id for the App's login in admission. An edited newest refinement counts nothing and no older one stands in for it; an App-filed issue, a body someone else last edited, a comment whose first text is not exactly the marker, and any other Bot's or App's comment stay out. A lane pull request still never supplies its own spec. The refinement stays out of the recorded spec comments the merge gate compares, whose filter stays human-only, so the gate does not see a refinement edited, hidden or added after a pass; an edit only removes it from spec. Intake's refinement banner and `refine.mjs`'s criteria check follow the rule.

## [5.0.0] - 2026-10-24

### Changed

- At the address-feedback round cap (`loop.review-rounds`), a pull request whose open findings all come from the code review lane no longer goes to a person. One more round runs on every kept thread, a fresh fixer in a new session like every round, and the round marker names it as past the cap. After that round the select job skips `cost-gated`, adds no label, and waits for the next write-access fix request. A security lane finding, a pr-verify note (an intent mismatch), a `claude[bot]` finding, whose lane no footer proves, or a pull request a person gated with the human-gated label (its hold lifts only on a fix request newer than the last round) still escalates `feedback-round-cap`, before and after the fresh fixer's round.

- pr-merge's `enable-auto-merge` job skips its work, green with a notice, when another run's `enable-auto-merge` job still waits and does the same work, so a backlog of events costs one pass instead of one serial pass each. On a pull request event it runs only for a lanes App pull request (`AUTOMATION_LANES_APP_SENDER_ID`), so any other pull request's check reads skipped instead of pending behind the queue.
- pr-merge's merge job reuses its run's `post-merge-dispatch` check when that check judged main at the merge job's commit under six minutes ago, instead of running the same check again.
- The merge and `enable-auto-merge` jobs read main's pr-merge run listing, each run's artifact list and each compare once between their kept-file readers (the gate cursor, the head-ref map and the lane records).

### Removed

- **Breaking:** the `admission` and `work-classes` keys of `applies-when` are gone from the schema, so a `pr-pipeline.yaml` that still sets either fails validation; delete the key. No pipeline predicate reads a work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): an issue with no class or any class, `work-class: structural` included, is decided by its labels, events and holds alone. resolve-issue's PR still carries `Hold: a human merges this` for an issue labeled `work-class: untrusted-provenance`, a trust hold that reads no other class.

### Fixed

- pr-merge's refire step now reads the annotations of a failed pr-unblock write-runner job (`<caller> / run`) when the jobs API lists its steps empty or cut short without the token step, so a refused run still gets its empty commit. A job that lists the token step as passed, and any job that is not a write-runner job, are still skipped.
- The red-main report counts a failed job that lists no failed step as a failing check of its own, matching the post-merge check.
- The demotion alert judges failing checks with red-main's rule (`failing-checks.mjs`) instead of its own shell copy. A failed job that lists no failed step now files, and, as a baseline entry, such a job excuses nothing.

- A merge job no longer skips its gate citing a pending run whose merge job already ran: a run reads pending while any one of its jobs waits, so the skip now reads the pending run's jobs and counts it only while its merge job still waits.

## [4.21.0] - 2026-10-24

### Changed

- A review-dependency `merge` verdict on a Dependabot pull request that changes a workflow or action file no longer waits for a person, and the `dependency-workflow-held` escalation reason is retired. The verdict job instead posts the merge marker only when that change is a full-SHA pin swap: every changed line in those files a `uses:` line that keeps its indent and action path, with both refs full 40-hex SHAs, so only the SHA and the trailing comment differ. Anything else (a tag ref, a path change, a new step, a `run:` change, an added or removed line, an added or deleted file) escalates the new `dependency-workflow-unpinned`. A lane fix still never lands under `.github/`.

- An issue run of the read runner (`work-resolve-issue`'s `resolve-issue`) now hands its reply, run fields, patch and outcome files to the scan job only sealed to the scan-carrier key, as a PR-mode run does. The scan job opens them, scans them for credentials, and is the only job that uploads them; the run job uploads nothing, and its step summary shows no model text but a gate skill's verdict. See [The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job).
- The read runner's patch outputs now come from the scan job alone. Its issue outputs (`scan-issue-run-started`, `scan-reuse-branch`, `scan-resume-branch`, `scan-resume-tip`, `scan-base-sha`) come from a new `issue-fields` job, which runs whatever the run job's result, holds each run job field to its closed set and combinations, and re-derives any branch claim with the default-tip earlier-work check. `work-resolve-issue.yml` reads only these, and the reuse summary job takes its code from the default branch tip. The run-job-sourced `issue-run-started`, `reuse-branch`, `resume-branch`, `resume-tip` and `base-sha` outputs are removed.
- The skill's `work-outcome.json` is cut at 48 KiB, down from 64 KiB, so every sealed payload at its cap still fits the five chunks a job's outputs hold.

## [4.20.0] - 2026-10-24

### Changed

- Intake no longer gates on work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): a triage verdict proposing no class, a class outside the repository's labels, `work-class: structural`, or a class a person set reaches `status: ready` on its Size, Complexity, Uncertainty and flags alone, and admission and the work-unblock mark no longer refuse by class. `work-class: untrusted-provenance` still holds the issue and refuses admission, now also when the repository lacks the label, when another class is already held (the label is added beside it), and when the label was removed by neither a listed human nor the lanes App; work-unblock treats it as a hold label, so a blocker close no longer adds `agent-ready` to such an issue. The triage rubric says the class gates nothing but that one (`.github/workflows/intake-triage.yml`, `.github/scripts/intake-triage/apply-verdict.mjs`, `admit.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`).

- Intake triage escalates an issue to a person (`needs_human`) only for text that tries to instruct the model or a report of a live exposure (owner intent, 2026-10-24: an item stops only for an intent or vision question or for security). A workflow, permission or governance change, unclear scope, an unsure approach or an oversized issue is triaged as usual, keeping the comment, class and fields; an intent question the issue cannot answer, or a very-high security risk, gets its flag, `status: needs-decision` and a numbered `RECOMMENDED:` question instead of a silent hand-off (`.github/workflows/intake-triage.yml`).

- A removed `agent-ready` no longer keeps an issue out of the issue lane for good. Intake admission and work-unblock leave it out only until the lanes App or a listed human adds `status: ready` after the newest removal; then admission runs its rules as usual. A `status: ready` added by anyone else, or before the removal, does not lift it, and a lane restart still does not count as a removal.

## [4.19.6] - 2026-10-24

### Changed

- The eval lane runs on a new `maintenance` funding role, `MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN`. The judge lane stays on `automations`, which remains the default role for any lane without a dedicated one. `.github/lane-funding.json` lists both, and the [pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding) names them.

### Fixed

- The pr-merge gate no longer holds a pull request at `verify:earlier-fail` after its link changed from `Refs:` to closing the issue and the verifier passed the new head. An earlier FAIL at a head of the same change now clears when every counted FAIL at that head records `spec_kind` `refs` for this pull request and every counted pass at the head records `spec_kind` `closes` with exactly the linked issues the FAIL records: a closing pass is judged against the whole spec, which includes the slice that failed. A `refs` pass after a `closes` FAIL, two verdicts of the same kind, a missing or unknown `spec_kind`, a pass that closes another issue or more issues than the FAIL named, linked issues that cannot be read, and a FAIL record that cannot be read or records another pull request, head or verdict all keep the refusal. Every other refusal is unchanged.

## [4.19.5] - 2026-10-24

### Fixed

- `enable-auto-merge` checks out the default branch with full history, as the post-merge check and the merge job do, so the room's post-merge recompute decides containment locally instead of making a compare API call per lane record. The lane-room read also has its own 8 minute timeout, apart from the verifier reads' 4 minutes, and a timeout still holds the lane. The arm step's timeout is now 18 minutes and the job's 30.

- `fix-ci` dispatch trusts a `ci-lanes` commit status by its creator's type and id (the GitHub Actions bot, `Bot` 41898282) instead of the login `github-actions[bot]`, which GraphQL never returns (it reports `github-actions`); no pull request was dispatched while the login check stood. A status set by any other actor, or with no creator, is still ignored.
- The dispatcher logs why it skips a listed pull request whose `ci-lanes` status failed or errored, so a skip of that kind is no longer silent; a failed status the GitHub Actions bot did not set is named as such.

## [4.19.4] - 2026-10-24

### Fixed

- The work-resolve-issue lane no longer opens a `Refs:` PR for an issue its run delivered whole. `report-outcome` derives the link line from the outcome's `remaining` list and ignores the run's `link` field: a non-empty list opens a `Refs:` PR with a `## Remaining work` section naming each part, which is the remaining work pr-verify's Refs rule asks the body to name. A `remaining` that is not 1 to 20 strings, each with text in the bullet it renders as, counts as empty, so the PR closes the issue. The run text the lane quotes in a PR body or comment also drops C1 control characters now.

## [4.19.3] - 2026-10-24

### Fixed

- A pending lane merge no longer makes `enable-auto-merge` disarm every armed lanes App pull request. The post-merge step takes about as long as the gate's two-minute reuse age, so the lane's room read the report as too old. It now keeps the report while nothing it was read from has moved, and otherwise checks again as the gate does, with the lane records the last run kept, so that check reads them without an artifact or run read each. When the room is held, by a refusal or because it cannot be read, the run raises one warning annotation and step-summary line naming the reason and each lanes App pull request it left unarmed or, in report-only mode, that a disarm would have turned off. A pull request still armed because its disarm failed gets an error annotation and summary line instead. It posts no comment on the pull requests.

## [4.19.2] - 2026-10-24

### Fixed

- The pr-unblock dispatcher no longer sends resolve-conflicts to a Dependabot head (a `dependabot/` branch Dependabot opened): its merge commit stopped Dependabot's own rebases, which resolve the conflict.

## [4.19.1] - 2026-10-24

### Fixed

- The pr-unblock `review-dependency` round cap counts only round markers at the pull request's current commits, so a `@dependabot recreate` or force push no longer carries the replaced head's rounds into the new one. A marker that names no head still counts.

## [4.19.0] - 2026-10-24

### Added

- A listed human adding `admission-deferred` to a decided issue with `status: ready` now has the hourly work-unblock sweep run intake's admission rules on its own work-class label and Size, Complexity and Uncertainty fields, each counting only when a listed human or the lanes App added or set it, admitting it when there is room and refusing it to `status: needs-decision` with a comment otherwise.
- The sweep now re-fires an `agent-ready` issue left with no run and no report for 3 hours, once per version of the lane workflow files, and then hands it to a person with `needs-human` and a comment.

### Changed

- Intake admission now reads the `- [ ]` acceptance criteria only from text a listed human wrote, in the body or a comment of their own, since pr-verify judges a lane pull request only against that text (owner decision Q9). The lanes App's refinement comment no longer satisfies the criteria check; a person who confirms it posts the criteria as their own comment.
- Intake admission now refuses an issue with more than 100 comments, since pr-verify reads only the first 100 and stops on such an issue.

## [4.18.0] - 2026-10-24

### Changed

- This repository sets `merge.dependabot.majors: review`: a Dependabot major, unreadable or disagreeing update merges on the pr-unblock review's `verdict=merge`, as any tier `review` update does, instead of waiting for a person (owner direction 2026-10-24; ADR 0073 addendum).
- `dependency-classify.mjs` reads a security update's version jump from its verified commit subject when the metadata has no `update-type`, matching the pr-merge classifier.
- `clear-escalations.mjs` clears a pr-merge Dependabot-major escalation when the head moves, like pr-merge's other escalations.

## [4.17.1] - 2026-10-24

### Changed

- A lane escalation's `needs-human` no longer stops the other fixers that could clear its cause. `resolve-conflicts`, `apply-conflict-patch`, `fix-ci`, `apply-patch` and `fix-docs` drop `needs-human` from their `labels-absent` (they keep `do-not-merge`); their dispatchers and base-code jobs (`resolve-conflicts-select` and `fix-docs-head` through the new `lane-hold.mjs`, and `fix-ci-context`) hold the human-gated label unless `gate-source.mjs` reads it as a lane escalation whose reasons, from report-escalation's `- Reason:` line, are another activity's. A person's label, a person's comment or review since the label went on (read from the REST issue timeline the way `clear-escalations.mjs` reads one, now one shared `spoken`), an escalation reason report-escalation.sh does not list, a review-lane hold or anything ambiguous still holds as `awaiting-human`. The dispatchers read a held PR's timeline once per run between them, and fix-docs reads it only for a PR not yet refined. When they work past the label, the write runner's `patch-fix-requested` lifts only the human-gated hold for that push, under any patch row. The label stays on, so `pr-merge` still refuses the PR. The verdict is read before the model turn, so a hold that lands during a run stops the next dispatch, not that run's push; `do-not-merge` still stops it.
- `report-escalation.sh` is idempotent per resume key and reason: a second activity escalating on the same head while the label is on posts its own comment, so that activity's own escalation holds it.

### Fixed

- A failed `pr-unblock / resolve-conflicts` run no longer marks its head handled for good: the dispatcher retries it until `limits.limit-stops-per-head` failures (limit stops included) stand on the head.
- A resolve-conflicts run skipped while the pull request was held (`Skipped: awaiting-human`) no longer marks its head handled: the dispatcher skips a held pull request itself, without recording it, and the next sweep after the hold comes off dispatches it. Held skips count toward `limits.limit-stops-per-head` with failures, for resolve-conflicts and fix-ci alike, so a hold the run reads and the dispatcher does not stops there. The dispatch record's version is now 4, so heads recorded under the old rule are read again.
- fix-ci no longer leaves a head for good after a run that found no failing check (`not-applicable`) or `fix-ci-restarts` failed runs: once the base tip moves past those runs the dispatcher dispatches the head again, until `limits.limit-stops-per-head` such runs stand on it. A new head starts with none.

- `enable-auto-merge` posts the gate's `<!-- babysit-merge-pin sha=<head> -->` comment before it arms a lanes App pull request, unless the App's newest pin already names that head unedited. When the pin fails to post, the pull request stays unarmed and the run fails. Arming a pull request that is already mergeable enqueues it at once with no auto-merge event, so the post-merge check now reads that head back against the pin.

## [4.17.0] - 2026-10-24

### Changed

- A trusted spec edit after a pass no longer strands the head at `verify:spec-changed`. `resolve-pr.mjs` judges a head again, with reason `spec-changed`, when every counted pass there started before the spec's last change (an issue body edit, a spec comment added or edited, or a body edit of a pull request that is its own spec), and the lost-run reconciler re-runs, once and with a record, the passed `pr-require-checks` run of such a head so pr-verify starts. The gate decides on the passes of the pr-verify run that started last, so the new verdict replaces the stale one. Each passed checks run is re-run once; a changed closing set and a removed spec comment still wait for a person.
- The verifier prompt no longer fails a pull request for touching workflows, CI, hooks, scripts, agent instructions, package manifests, lockfiles, path or file-type refusals, a `merge: human` setting, deploys, cloud, releases or other repositories; those are judged as ordinary code. It fails a change to the takeover set (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, submodules) whatever the spec says, unrequested work that loosens a hold the owner keeps (outside-organization work, cost and billing, rate, capacity, work-in-progress and round caps), and unrequested work on secret values or organization or repository settings.
- Spec trust is unchanged: text the lanes App wrote, an issue it filed or intake triage's refinement comment included, is still not spec. Trusting it is held for an owner decision.

## [4.16.0] - 2026-10-24

### Added

- Intake refinement now files the split admission recommends. When admission holds an issue at the lanes App's `status: needs-decision` only because some, not all, of its done-when items ask for what an unattended lane run cannot perform, and the triage raised no flag, the `refine-issue` run judges the split. When the model returns exactly the held item numbers, `apply-refinement` files one child issue as the lanes App, labeled `needs-human` and born triaged, that holds those items as written, with their indented sub-lines, and links back. It then replaces them in the issue body with one line linking the child, lifts `status: needs-decision`, and triages the issue once more so admission reads the rest. The refinement marker keeps it to once per issue, and a retry reuses the child it filed. A proposal that names any other items, drafts criteria or asks questions alongside a split is refused before anything is written.

### Fixed

- An address-feedback round whose reply job skipped `no-model-turn` no longer waits for a review or `pr-verify` run that may never come. `pr-feedback-dispatch.yml` also runs when a scheduled `pr-unblock-dispatch.yml` run completes (its half-hourly tick), and sweeps the open lanes App pull requests into `main`. The first head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, fewer than three times at that head, is decided and dispatched as for its newest completed review run, which the dispatched-run record names. A tick dispatches at most one head, keeps no dispatch record, and moves past a pull request it cannot read. The dispatcher stays a `workflow_run` run, so the trusted-trigger gate and the broker check it unchanged.

- Admission waits only on an open pull request in this repository that is for the issue: one GitHub lists as closing it (`closedByPullRequestsReferences`), or one whose body has the issue lane's `Refs: #<issue>` line. A pull request that only mentions the issue no longer defers admission, in `admit.mjs` or in work-unblock's sweep of `admission-deferred` issues.
- `publish-feedback` accepts an earlier fix on a retry. When the compare range holds no lane fix commit and the round wrote no patch, each `VALID` thread's fix may be the newest earlier commit on the pull request that the lanes App made through the API with the push job's `Lane-Activity` trailer, committed after the thread's newest comment by the reviewer, the verifier or the lane, that changed the thread's path and a line the reply's evidence cites (in a file no later commit on the pull request changed), and that no lane reply already names as a fix. A commit the lane already answered on that thread, or one the reviewer raised the finding again after, does not count. Before, a round whose fix had landed but whose replies did not post left every thread open, and every retry ended `feedback-not-landed`.

## [4.15.1] - 2026-10-24

### Fixed

- pr-merge's enable-auto-merge job no longer fails its arm with `fetch failed` after a long verifier read. Every request now sends `Connection: close`, so none goes out on a pooled keep-alive connection that sat idle while the verifier ran and that GitHub had closed. A GraphQL request that still fails on the network (Node's "fetch failed", or a cause code of `ECONNRESET`, `ETIMEDOUT`, `UND_ERR_SOCKET` or `UND_ERR_CONNECT_TIMEOUT`, or "other side closed") is sent up to twice more (a REST write, such as the refusal comment, never is), after full-jitter waits capped at 4 s and then 8 s. An HTTP error answer or a GraphQL error is not sent again. A resent arm passes the same `expectedHeadOid`, so it arms only the head the run read. A pull request whose arm or disarm still fails is left as it was and named with the error's cause code and message, with any token scrubbed. The run then goes on to the other pull requests and exits 1.
- A lanes App pull request that native auto-merge leaves unarmed no longer sits with only an Actions log line to say why. On a scheduled or hand-started run, a refusal on a hold path, a cost path, the gate's verifier verdict or its risk score is written on the pull request in one `<!-- babysit-merge-risk -->` comment that names the head and the reason. The comment is edited in place when the reason changes, and left alone while it does not. A refusal a person must clear also gets the human-gated label: a hold or cost path, an issue link the lane does not take, a verdict the gate marks `needsHuman`, or a risk hold that has stood unchanged for `merge.risk-escalation-minutes`. That comment carries the attended queue's escalation marker. A refusal the lanes clear on their own, such as a missing verdict, gets the comment only. A label a person removes stays off until the reason or the head changes.

- report-outcome's hand-backs (pushback, stopped, a refused patch, a dimension skip and a turn cap with no restart left) open with `<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->`, then the outcome marker, so `/work-items:attend-queue` lists the issue as escalated. The outcome-marker parser that `issue-prior`, work-unblock and the monitor signals share reads the outcome marker after that one line.

## [4.15.0] - 2026-10-24

### Changed

- resolve-config no longer adds `.github/**` to `merge.diff-check.denied-paths`; it still adds the config file's own path and the trusted-actor list. A lanes App pull request touching `.github/scripts`, `.github/actions` or another `.github` path off the merge gate's HIGH floor is no longer held by report-outcome's `Hold:` line, `enable-auto-merge` or `ci-status`, and merges on the two review lanes (owner direction 2026-10-23). The lanes App's token never carries the `workflows` permission, so no lanes App push changes a workflow file; another identity with write access can still push one after auto-merge is armed. Hold paths now match case-insensitively, as the merge gate's `glob_match` does, so `.github/codeowners` or `.github/actions/Resolve-Config/` holds. The floor also holds `.github/actions/check-kill-switch/**`, whose output writer check-trusted-trigger and resolve-config load; a test walks both actions' imports and fails on any file the floor does not hold.
- `merge-holds.mjs` no longer holds every `plugin.json` and `marketplace.json` path-wide. Its hold-path floor is the forced paths plus the merge gate's HIGH floor (`babysit_risk.HIGH_FLOOR`), and `ci-status` compares a changed manifest base against head as the gate's manifest review does (`manifestChanges`, the rule of `babysit_risk._manifest_changes`): an executable `plugin.json` key or `experimental.monitors`, a marketplace plugin added, removed, renamed or re-sourced or a marketplace `name` change, a removed, renamed or copied manifest, and a side that does not read or parse or repeats a key hold; a `userConfig` default or version change merges. `enable-auto-merge` arms such a change once the gate's risk score (`evidence --lane-reviews`) allows it. ci-status now hands the module each file's status and the base commit.

- Intake admission also takes issues whose Uncertainty is Knowable (`admission-rules.json`), which the run lane already runs research-first (owner decision 2026-10-24, amending Q51 criterion 3).

- The intake, pr-unblock and pr-verify lanes run on their own funding roles' secrets instead of the `automations` pair. `intake-triage.yml` passes `role: intake` with `INTAKE_CLAUDE_API_KEY` and `INTAKE_CLAUDE_CODE_OAUTH_TOKEN`, and its intake reusable pins ci-workflows [`b0ecc27`](https://github.com/melodic-software/ci-workflows/commit/b0ecc273abe492d12f2efa98ee4741a84c219ed2), whose runner-policy contract names that role ([standards#863](https://github.com/melodic-software/standards/pull/863)). Every Claude job in `pr-unblock.yml` and the fix-docs jobs in `pr-refine.yml` pass `role: pr-unblock` with `PR_UNBLOCK_*`, and both `pr-verify.yml` jobs pass `role: pr-verify` with `PR_VERIFY_*`. Each run's `credential=` now names its own role's secret. `.github/lane-funding.json` lists the new secrets, the read-run secret allowlist in `scripts/check-read-caller-keys.mjs` admits `PR_UNBLOCK_*` in place of `AUTOMATIONS_*`, and `callers.test.mjs` fails when a catalog lane reads another role's secret or passes a `role:` other than its own ([pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).

### Fixed

- An issue-lane run that waited in its slot while a change to `work-resolve-issue.yml` or `pr-run-activity-write.yml` merged no longer fails red as `workflow-stale`. The read runner's `workflow-current` step sets `stale=true` and ends green with a warning, the `Stop on stale workflow files` step runs, and `go` is `false`, so no model turn, earlier-work check, outcome marker or caller job follows, and lane telemetry counts no failure. work-unblock's hourly sweep finds that step in the run's job listing and re-fires the issue on main's files, once per version of the two lane workflow files, as it does a failed run. The sweep reads each run's job listing once, shared by its checks.

- The address-feedback scope rule (`thread-scope.mjs`) no longer lets a fix edit a plugin's control or instruction files through the plugin-wide arm; it excludes the same control paths the pull-request-files arm does.

## [4.14.1] - 2026-10-24

### Changed

- pr-merge's head-ref map (`.github/scripts/pr-merge/head-ref-map.mjs`) is carried on a run that saves no artifact listing, such as a run with no candidates: the map read before the gate is uploaded as it is, with one log line and no warning, and the next run that saves a listing prunes it. Before, that run warned and uploaded no map, so once the trusted-run window passed the next run downloaded every untied FAIL again. A listing file that exists but cannot be read still uploads nothing, and with no map read before the gate nothing is uploaded. The map is still read only from the newest scheduled or hand-started `pr-merge.yml` run on main and never passes through `actions/cache`.

## [4.14.0] - 2026-10-24

### Changed

- The `enable-auto-merge` activity arms a lanes App pull request whose issue link the merge gate takes, a plain `Refs: #<n>` issue included, instead of only one whose body opens with `Closes #<issue>`. The link is read with the verdict, through the gate's own rule (`babysit_verify_evidence.py evidence --lane-link`, which runs `babysit_merge_policy._linked_issue`), on the scheduled and hand-started runs only: two or more `Refs:` issues, a `Refs:` line in any other form, a number that is no issue, two closing issues, a closing issue in another repository, and a failed read all leave the pull request unarmed, or disarm it. An event run reads no link, so it never disarms on one.
- The `enable-auto-merge` activity applies the merge gate's run-level refusals, which native auto-merge would otherwise skip. Each scheduled or hand-started run waits for the same run's `post-merge-dispatch` job, which keeps its post-merge report as a one-day artifact, and reads the lane's room from that report (`babysit_verify_evidence.py lane-room`, `babysit_merge_policy.lane_room`). While a demotion record, `merge.rung`, the loop setting or the rung cap holds the lane off, or a lane merge failed its post-merge check, nothing is armed and every armed lanes App pull request is disarmed. At `merge.max-in-flight`, counting the queue's lane entries, the lane's unverified merges and armed pull requests not yet queued, nothing more is armed. A missing report, one the gate would not reuse (`shared_refusal`: older than 30 minutes, as a re-run job reads the run's first report, a demotion record filed or changed since, or a lane merge landed since that it does not count), or a room that cannot be read, holds as a refusal does: nothing is armed and every armed lanes App pull request is disarmed. The report is read whenever `post-merge-dispatch` ran, so a later step of that job failing does not disarm anything. The job now holds `pull-requests: read` for the merge-queue and merge reads.
- In the merge queue, `ci-status` holds a lanes App pull request whose verifier pass no longer binds its live issue link. It reads the counted pass's `verdict.json` (one artifact download) and the closing issues (one GraphQL read), and `merge-holds.mjs` `linkHold` holds unless the body still closes, or with no closing issue still names by a plain `Refs:` line, the one issue the pass judged, linked the same way. This is pr-merge's reader rule (`verify:spec-changed`), so a body edited after arming, such as `Refs: #A` to `Closes #B`, no longer merges on a pass for the old issue. A trusted approval of the head lifts it, as it lifts the verifier hold. `refsIssue` moves to `merge-holds.mjs`, which `resolve-pr.mjs` re-exports.
- `enable-auto-merge` holds a lanes App pull request on the merge gate's risk score: `evidence --lane-reviews` runs `babysit_risk.score` and `holding` over the inputs the gate builds, at the lane room's effective rung. Each of these leaves it unarmed or disarms it: an open CRITICAL security-lane finding or a review not bound to the head (whether or not the lane applied its hold label), a symlink, submodule or other non-regular mode, a high path, the manifest review, the trust gate, and the cost review unless the owner's decision lifts it. The job now also holds `checks: read` for the lanes' annotations.
- `ci-status` fails a lanes App pull request while the lanes kill switch (`CLAUDE_LANES_DISABLED` or `CLAUDE_LANES_REPO_DISABLED`) reads anything but `false`, so one armed before the switch was turned on stops in the merge queue. It reads the vars context and makes no API call. Owner and Dependabot pull requests are not affected.

## [4.13.3] - 2026-10-23

### Changed

- `pr-unblock-dispatch.yml` also runs half-hourly, at minutes 9 and 39, five minutes after each `maintenance-reconcile-lost-runs` tick. A lanes App pull request whose reconciler re-run failed now gets `fix-ci` at the first tick after that failure instead of waiting for the next push to `main`, and a conflicting or Markdown-changing pull request is picked up the same way. A tick runs the same listings as a push run, and heads the dispatch record holds are not read again. The gate and the token broker already accept a dispatcher run started by a schedule. A re-run of a scheduled run fails at the trigger check, which handles no `schedule` event; the next tick replaces it. Only a push cancels a dispatcher run in progress; a tick or a hand run waits behind it, so a tick never cuts short a push run's dispatches.

## [4.13.2] - 2026-10-23

### Fixed

- The pr-merge lane no longer adds `needs-human` back to a pull request after a person removed it (a User of kind `human` on the trusted-actor list at the default branch, with write access), while the escalation it explains is unchanged (same head and reasons). A removal by a bot, by an account off that list, or through a GitHub App lifts nothing, and a new head or new reasons escalate again ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane)).

## [4.13.1] - 2026-10-23

### Fixed

- `ci-status` and `enable-auto-merge` hold a lanes App pull request that changes the marketplace manifest (until a trusted approval of the head) or a merge-gate cost path (until the owner's linked cost decision).

## [4.13.0] - 2026-10-23

### Added

- pr-verify's resolver gives the verifier the one issue a plain `Refs: #<n>` line names as the spec of a pull request that closes no issue, by the same rule the pr-merge gate reads (`refsIssue`, kept equal to `babysit_merge_policy.refs_issue` by `test_verify_rules_sync.py`), and marks each spec entry's `spec_kind` (`closes`, `refs` or `pull-request`), which the verdict records as `spec_kind`. The verifier judges a `Refs:` issue as a partial slice (owner decision 2026-10-23): only the part the pull request body says it delivers, in the issue's scope, correct and coherent, with the body naming what remains; a body naming no delivered part or no remaining work, or claiming the whole issue, fails. Closing issues are still judged whole, and the spec trust rules are unchanged.
- A `Refs: #<n>` whose number names no issue or pull request (GitHub's NOT_FOUND) gives the resolver no linked issue instead of failing the run; the resolver reads the `Refs:` issue with a GitHub helper that keeps GraphQL errors, so the default helper's throw on any `errors` never reaches it, and an answer with no repository, or a null issue without that NOT_FOUND, fails the read. work-resolve-issue's report-outcome no longer puts the human-gated label and a refs-hold comment on the issue of a `Refs:` pull request it opens, since the merge lane now merges a plain `Refs:` pull request; work-unblock still lifts a hold set before.

## [4.12.3] - 2026-10-23

### Changed

- API budget logging reads the rate limit from each job's own responses. It no longer reads `GET /rate_limit`, which reports a different bucket from the one the job spends. `.github/actions/log-api-budget` holds three parts:
  - `api-budget.bash`: a `gh` wrapper and the notice
  - `api-budget.mjs`: the fetch side
  - an end-of-job emitter
- Each named token gets one notice for its last reading and one for each refused (403/429) reading: `token=<name> workflow=<path> job=<id> run=<id> attempt=<n> limit= remaining= used= reset=<epoch> resource= cost=<N or na>`. `cost` is how much `used` rose since the first reading with the same reset.
- Where the notices come from:
  - `ci-status` wraps its own `gh api` reads and writes its notice before the aggregate step.
  - pr-merge's merge job reads through the babysit gh seam.
  - The pr-feedback-dispatch and pr-unblock-dispatch jobs read through `request-budget.mjs`.
  - Those three jobs write their notices from their existing end steps.
- The start-of-job `/rate_limit` steps are gone, including those in work-unblock, intake-triage and pr-run-activity-write.
- The lanes App token is now named `lanes-app` (it was `lane`). The monitor-signals ceiling reads both names and both notice shapes.

- `pr-feedback-dispatch.yml`'s `rerun-ci-status` re-runs a head's ci-status once, after the last review lane finishes, instead of once per lane: while the other lane's newest run on the head is still going it stops after one read, since ci-status would still be red and that lane's completion starts the job again. A head with no run of the other lane re-runs on one lane. A ci-status that started after both lanes finished, or a re-run already queued, is left alone. The job list is read once, and each 60-second poll reads only the run. A read refused by the token's primary rate limit (403 or 429) waits `retry-after` seconds, else, with `x-ratelimit-remaining: 0`, until one second past `x-ratelimit-reset` inside the same 10-minute cap instead of failing; a reset past the cap fails the job with an error naming the reset, since nothing else re-runs a ci-status left stale.

## [4.12.2] - 2026-10-23

### Fixed

- Native auto-merge of a lanes App pull request now needs the verifier verdict pr-merge's gate needs. `enable-auto-merge.mjs` arms, and keeps armed, only when pr-merge's gate reader refuses nothing at the head it read (a pr-verify pass, no FAIL at the head, FAILs under `merge.max-verify-fails`, an unchanged trusted spec), and only on its scheduled or hand-started run; event runs never arm. `ci-status` turns an armed lanes App pull request's auto-merge off on each push to its head. In the merge queue, `ci-status` requires a pass or pass-notes artifact at the queued head from a successful pr-verify run on main; a trusted approval of the head lifts it. Pull request events read no verdict, since pr-verify runs only after a green pull request run.

## [4.12.1] - 2026-10-23

### Changed

- pr-verify names a FAIL verdict's artifact with `-i` and the issues its verdict records, ascending and joined by dots (`write-verdict.mjs` `artifactName`), so the pr-merge gate counts it toward each issue's repeated-fail cap from the artifact listing alone. PASS and PASS-NOTES names are unchanged. The writer checks every name against the readers' pattern (`NAME`, now kept in `write-verdict.mjs` and re-exported by `resolve-pr.mjs`) and fails the job before upload on one no reader takes. The resolver checks the names without issues first and skips a head judged under one without reading the linked issues; only then does it read them, which the spec needs anyway, and look up its own FAIL under the `-i` name; a FAIL another pull request left at the same head is still missed and that head judged again, at the cost of a run, and so is this pull request's own FAIL once a body edit changes its linked issues at the same head, one run per change of the issue set; neither changes the gate's decision, since the earlier FAIL stays tied and refuses the head. A FAIL whose issues no name carries (more than 10, or a number over 10 digits) keeps the plain name with a warning, and the resolver never looks such a name up, so that pull request is still judged.

- pr-merge carries the `pr-merge-dispatched-<id>` and `pr-merge-rerun-<id>-attempt-2` records the post-merge check proved from one run to the next as the `pr-merge-lane-records` artifact (`.github/scripts/pr-merge/lane-records.mjs`), so the check stops listing each record and reading the run that uploaded it on every run. Before each post-merge check, in the `merge` job and in `post-merge-dispatch`, a step reads the file from the newest scheduled or hand-started `pr-merge.yml` run on main other than itself whose head commit is on main, found the way the gate cursor and the head-ref map are; the check steps, the `--remediate` step and the gate step name it in `BABYSIT_POSTMERGE_LANE_RECORDS`. After the gate a scheduled or hand-started `merge` job uploads the records the checks read in and proved, while unexpired and still listed by the run's artifact listing under the record's name and sender run; the read step removes any file already at its path first; with no listing file (no candidates, or a listing the run could not read), unexpired records are carried as they are and pruned on the next run that saves a listing; a listing file that exists but cannot be parsed uploads nothing, and the next run reads an older file. Only a run's own steps can upload its artifacts, and the file never passes through `actions/cache`. Any failure leaves no file, and the check reads each record as before. Permissions are unchanged.

## [4.12.0] - 2026-10-23

### Changed

- `merge.lane-prs` (default `native`) leaves the lanes App's pull requests to GitHub's native auto-merge: pr-merge's `merge` job no longer lists them, so its gate never scores, escalates or enqueues one. Adopted owner pull requests and Dependabot's are gated as before. `gate` restores the earlier listing, and this repository sets it until `ci-status` or `enable-auto-merge` enforces the pr-verify verdict and the post-merge check judges native merges ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)).

### Removed

- `merge.read-token-floor` and the pr-merge gate's switch to the lane App token. The gate's review-evidence reads (timeline, comments, review-lane runs with their attempts, jobs and annotations) stay on `GITHUB_TOKEN` whatever its budget, since GitHub's [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) section H bars sharing tokens to exceed its rate limits ([owner decision](https://github.com/melodic-software/claude-code-plugins/issues/9297#issuecomment-6368281689)). A read refused for a rate limit is made once and not retried: the candidate's lanes read `evidence-missing` and it holds until a later run reads again. **Breaking:** `merge.read-token-floor` is gone from the schema, so a `pr-pipeline.yaml` that still sets it fails validation; delete the key.

### Fixed

- `work-resolve-issue` no longer resumes an earlier run's lane branch that is behind the default branch. Such a branch carried its stale base into the runner's whole-branch checks, which failed and handed the issue to a person with no pull request. The run now starts fresh from the default branch under a new lane branch and leaves the old one in place. `issue-prior` reads `behind_by` from the compare call it already makes, and fails the step when that value is not a whole number. The outcome comments say a restart continues from the branch only while it is not behind.

## [4.11.1] - 2026-10-23

### Changed

- The verifier-notes poster (`verify-notes.mjs`) and `pr-feedback-dispatch.yml`'s FAIL filter accept a FAIL artifact name that ends with `-i` and the issues the verdict records, ascending, each once, joined by dots, so `write-verdict.mjs` can start writing them later. `pr-feedback-dispatch.yml` fails its run on a FAIL-shaped name no reader takes rather than skipping it, and anchors its filter at the true end of the name; the notes poster refuses a name whose issues are not the ones its verdict JSON records. The resolver's name pattern (`resolve-pr.mjs` `NAME`, checked by `isVerdictName`) follows the same grammar, though its already-judged lookup still builds exact names and finds an issue-named FAIL only once the writer change teaches it to. `test_verify_rules_sync.py` checks that the gate, the resolver's pattern (`isVerdictName`; it does not exercise `judged()`), the notes poster and the workflow filter accept the same names, with the same 10-digit pull request bound and 194-character limit.

## [4.11.0] - 2026-10-23

### Changed

- `address-feedback` may fix a finding in any file the pull request already changes that the gated head holds, not only in the thread's own scope. The select job writes the PR's files, rename sources included, as `pr_paths` in the thread file and `run.json`, less `.github/workflows/`, `.gitmodules`, `CODEOWNERS`, `settings*.json`, package manifests, `requirements*.txt`, anything under `.github/`, `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, `.lsp.json`, a `.claude` or `.claude-plugin` directory and a plugin's `hooks/`, `monitors/` and `bin/`. `apply-patch.mjs`'s `kept-threads` rule and the reply job admit them, and only as changes to an existing file: a file the fix creates keeps the old scope. A `VALID` fix commit lands when it changes the thread's path or a `pr_paths` file at a line the reply's evidence cites inside one of its hunks. Every apply-patch refusal still applies.

## [4.10.2] - 2026-10-23

### Fixed

- A `resolve-conflicts` round whose scan refused the model's output (a leak-scan block or an oversize patch) now escalates `unresolved-conflict` instead of ending with a failed leg and no escalation. The new `conflict-scan-refusal` job in [`pr-unblock.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-unblock.yml) runs when the answering leg handed on no patch state, downloads the read runner's scan-refusal markers by name, never a job output, and reads them with `scanRefusal` through [`conflict-scan-refusal.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-unblock/conflict-scan-refusal.mjs); `report-escalation` and `report-conflict-status` take its reason. No marker escalates nothing ([#9391](https://github.com/melodic-software/claude-code-plugins/issues/9391)).

## [4.10.1] - 2026-10-23

### Changed

- `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/6d6cb798e7cb7560a0f9327d8a22398961c23b31/.github/workflows/pr-review-cli.yml) v0.64.2, which spends fewer job-token API requests per run ([ci-workflows#869](https://github.com/melodic-software/ci-workflows/pull/869)). It reads the pull request's file list once instead of three times and pulls.get twice instead of three times, and the publish gate now comes through git. A whole review with an inline comment drops from 15 requests to 8. Check names, the marker comment, the review-complete notice and holds are unchanged.

- The pr-merge lane token carries no Actions permission: `merge-pr`'s `activity-grants` row is gone, and a test pins that no live slot resolves an actions permission. The verdict downloads, the artifact listing, the run records and the compares stay on `GITHUB_TOKEN`, and nothing is built to fall back from them to the lane token.

## [4.10.0] - 2026-10-23

### Added

- The pr-merge lane's `enable-auto-merge` activity (effect `merge`) turns on GitHub's native auto-merge, squash at the head it read, for each open lanes App pull request into main that opens with `Closes #<issue>` and carries no hold (a `Hold:` line or "do not merge" in its body, `do-not-merge`, the human-gated label, a member's newest comment saying "do not merge", a head that now changes a denied path), and turns it off on an armed one that now carries a hold. Auto-merge a person turned off stays off. `pr-merge.yml` runs it in its own job, with its own lanes App token, when the issue lane finishes (a new `workflow_run` trigger the merge job ignores), on a listed human's edit, unlabel or ready, and on the schedule. While `merge.report-only` is true it writes nothing ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)). `ci-status` fails a lanes App pull request on a body hold, a member's veto comment or a changed or renamed-from denied path (lifted by a trusted person's approval of the head), on each pull request event and in the merge queue, so a hold added after arming stops the merge.

### Changed

- `resolve-conflicts` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token or runs git. [`pr-unblock.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-unblock.yml) runs it as five jobs: `resolve-conflicts-select`, a base job with a read-only token, pins the default branch tip, merges it into the head with the base's `prepare.sh` and decides clean, conflicted or escalate; `resolve-conflicts-not-run` posts the check neutral (`clean-merge` for a clean merge) when no model is needed; the model job and its subscription call (started by `resolve-conflicts-handoff`'s read of the run's jobs, `fallback: handoff`) merge the pinned base again, must reach the same conflict tree, and hand the skill's resolutions on as a patch; and `apply-conflict-patch` merges once more and commits the merge with the head and the pinned base as parents. Every gate, head, base and conflict tree comes from the select job, and every model-call input from one leg's scan job.
- `resolve-conflicts` has effect `read` and `applied-by` `patch: apply-conflict-patch`, and routes to the `code-fix` profile (the read runner refuses `default`). Its skill gets Read, Grep, Glob, Skill, Edit, Write and Agent with no Bash, and `.lane/merge/`, which the new [`context.sh`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/merge-base/context.sh) writes before any model turn (each conflicted path's three stages and both sides' history, capped), read-only and denied to the file tools. The new script activity `apply-conflict-patch` runs `apply-patch.mjs` under the `merge-base` row.
- `prepare.sh` prints `conflict-tree`, the merge's stage-0 entries plus each conflicted path's marker file, and runs the version-bump script under `LC_ALL=C`. The new [`run-prepare.sh`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/merge-base/run-prepare.sh) is the step around it in all three jobs, and fails red unless a later job's merge reaches the select job's state and tree. `collect-patch.sh` takes an optional tree to measure the patch from.
- `apply-patch.mjs` commits a merge: under a row with parents `[head, base]` it applies the patch to the conflict tree in a scratch index, holds only the patch's own changes to the refusals, `max-files`, the `merge-result` predicate (a conflicted path, else `unexpected-path-staged`), the credential scan and the blob caps, escalates `unresolved-conflict` for a conflicted path left with markers and `workflow-staged` for a workflow change that is not exactly the base's, uploads only the blobs the base's `tree-entries.sh` flags, refusing before any write past the new row key `max-blobs`, and commits `[head, base]`. A clean merge commits with no patch. The `merge-base` row sets `max-files` 300, `max-blobs` 300, `skip-moved-head`, `empty-at-push: conflict`, and the escalations `conflict-patch-invalid`, `conflict-patch-not-applied` and `conflict-patch-protected-path`, which `report-escalation.sh` explains.
- The read runner's scan job reads a merge-base patch as text and never applies it to the head; a binary hunk blocks it. `report-conflict-status` posts on an `unresolved-conflict` from the select or the push job. The schema requires `applied-by.patch` of a read `merge-base` skill and adds the `clean-merge` skip reason.

### Removed

- The write runner's `merge-base` skill mode: its post and commit steps, the promote step's merge branch, and its `merge-state` output. A `merge-base` skill on the write runner, or on `claude-code-action`, now fails red. `post.sh` and its tests are gone, and `prepare.sh` no longer copies `.git/config` or prints the config, attributes and snapshot hashes only `post.sh` read. `collect-base-activity` drops the merge-base git deny list: every write skill on `claude-code-action` is denied all of git.

## [4.9.0] - 2026-10-23

### Added

- Intake refines a thin issue: one whose triage flags `intent` or whose body has no task list line. A read-only model run in `intake-triage.yml` (`refine-issue`, contents read only, no project settings, `dontAsk`) explores the default branch, checks the open and closed issues and merged pull requests a title search found for duplicates and finished work, and reads the docs hosts resolve-issue reads. The `apply-refinement` activity posts its output as the lanes App in a separate comment opening with `<!-- intake-triage refinement -->`, once per issue.
- An exact refinement lists its acceptance criteria as a task list, lifts the lanes App's `status: needs-decision`, and triages the issue once more; one that is not exact asks numbered questions with `RECOMMENDED:` answers and leaves the issue at `status: needs-decision`. It never adds `agent-ready` or `needs-human`.
- Admission's criterion 7 also counts the task list in that comment when the lanes App's account posted it after the body's last edit, and the work lane's `issue.json` keeps that comment as `author_kind: refinement`.
- Only issues and pull requests a listed human or the lanes App opened reach the refinement model as duplicate candidates, and refinement text cannot add a link, an autolink or a `GH-N` reference.
- A refinement is dropped when the issue's title or body changed while the model ran. Labels change before the marker comment is posted, so a failed label update leaves no marker and the next triage refines the issue again.

### Changed

- `fix-docs` moves from `pr-unblock` back into its own `pr-refine` lane (stage `refine`): `pr-refine.yml` holds the `fix-docs`, `fix-docs-subscription` and `apply-docs-patch` jobs, and `pr-unblock.yml` no longer takes `fix-docs`. `pr-unblock-dispatch.yml` dispatches `pr-refine.yml`, still once per PR and at most `limits.fix-docs-per-run` per run; a PR that already has a `pr-unblock / fix-docs` run counts as done.
- `fix-docs` now tidies every ready PR that changes Markdown, lanes App PRs included, except Dependabot's, the release App's and the standards-sync App's, matched by account id.
- Both activity runners name `pr-refine.yml` as the dispatched workflow for the `pr-refine` lane. pr-merge's refire of a broker `workflow-modified` refusal leaves `pr-refine` runs out: a `pr-refine` run is dispatched on main, so an empty commit on the PR cannot make it pass, and a listed person re-dispatches it.

- The pr-merge lane token now carries Actions read (owner decision Q8), for its verdict and run reads to fall back on; the verdict downloads, listing and run records still read with `GITHUB_TOKEN`.

- pr-merge's `merge` job carries the head ref each untied pr-verify FAIL's verdict.json records, by artifact id, from one run to the next as the `pr-merge-head-refs` artifact (`.github/scripts/pr-merge/head-ref-map.mjs`), so the gate stops downloading every old-format untied FAIL on every sweep. Before the gate it reads the map from the newest scheduled or hand-started `pr-merge.yml` run on main other than itself, found the way the gate cursor is; after the gate a scheduled or hand-started run uploads that map plus its own downloads, for ids the artifact listing still lists. Only a run's own steps can upload its artifacts, and the map never passes through `actions/cache`. Any failure leaves no map, and the gate downloads as before. Permissions are unchanged.

### Security

- `fix-docs-subscription` no longer starts on `fix-docs` outputs, which its head-code run job could forge. A `fix-docs-handoff` job reads this run's jobs through the Actions API, as `fix-ci-handoff` does for fix-ci. The fallback runs only when the broker allowed `fix-docs` and its report job posted no check (#8890).
- `apply-docs-patch` no longer takes its patch inputs or head from `fix-docs` run-job outputs. It takes them from the answering leg's scan job and the head from `fix-docs-head`, as fix-ci's `apply-patch` does (#8890).

## [4.8.1] - 2026-10-23

### Changed

- The pr-merge HIGH path floor holds only the takeover set: the trusted-actor list, the trusted-trigger check, `CODEOWNERS`, `.gitmodules` and `resolve-config`. Agent permission config, package manifests and lockfiles, and the release and `id-token: write` workflows merge on the review lanes. The `high-path-floor` schema description and the README say so.

## [4.8.0] - 2026-10-23

### Changed

- `address-feedback` works a pull request carrying the human-gated label when a lane escalation (pr-unblock or fix-ci) put the label on and no review-lane hold names the current head or is open; a review-lane hold, or anything ambiguous, still limits it to threads a trusted person with write access asked it to fix. The label stays on: `clear-escalations` removes it only while no address-feedback round has been recorded since it went on, so once a round runs a person removes it. To stop the lane working such a PR, add `do-not-merge`.

## [4.7.5] - 2026-10-23

### Added

- `ci-status` now gates tests that cannot fail. On a pull request or merge group, the `check-plugins` gate `cant-fail-scan` runs `/testing:audit`'s scan on each changed test file, and reports not applicable when the diff changes none. When there is no diff base (the schedule, a dispatch, or a pull request or merge group that resolves to the whole tree), a new `check-tests` job scans the whole tree; with a diff base it returns at once ([#9184](https://github.com/melodic-software/claude-code-plugins/issues/9184)).

## [4.7.4] - 2026-10-23

### Changed

- The pr-merge HIGH path floor also holds `.github/actions/resolve-config/**`, so a change there waits for a human merge: the token broker runs that directory's code from main in its signer process.

- Every reader of a pr-verify verdict name (the pr-merge gate, the resolver, the FAIL-notes poster `verify-notes.mjs` and pr-feedback-dispatch) also accepts the name followed by `-<ref-digest>`, the first 16 hex digits of the SHA-256 of the head branch the verdict records (`headRefDigest` in `write-verdict.mjs`). The gate ties an untied FAIL from such a name without downloading it, so a digest-named FAIL whose verdict.json cannot be read no longer refuses `verify:unreadable`. `verify-notes.mjs` checks the digest against the verdict. pr-verify still uploads the old name until a follow-up switches the writer.

## [4.7.3] - 2026-10-23

### Changed

- The pr-merge gate fetches each verifier verdict by its artifact id, one request where `gh run download` spends two, and an untied FAIL record that could not be read refuses the run's later candidates without another download. Both stay on `GITHUB_TOKEN`, since the lane App token holds no Actions permission.

## [4.7.2] - 2026-10-23

### Fixed

- `pr-unblock-dispatch.yml` releases a `review-dependency` head the usage limit stopped once that limit resets, as it does for `resolve-conflicts`, and stops re-dispatching the head after `limits.limit-stops-per-head` limit stops. Before, a limit stop held the head until the next push, and the dispatch record could store it as reviewed. The dispatcher now reads the base's resolved limits and its clock for `review-dependency` too ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9379](https://github.com/melodic-software/claude-code-plugins/pull/9379)).
- The dispatch record's version is now 3, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could hold a limit-stopped `review-dependency` head as reviewed, past its reset. The cost is one pass of re-reads, never an extra dispatch ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382)).
- The lane catalog's trigger gate check covers `issue_comment`: a job that holds a Claude credential under it must show an author or same-repo gate, and `lane-funding.schema.json` requires a `gate` for a lane with that trigger ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9380](https://github.com/melodic-software/claude-code-plugins/pull/9380)).

## [4.7.1] - 2026-10-23

### Fixed

- address-feedback's and review-dependency's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. As for fix-ci, `address-feedback-handoff` and `review-dependency-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API once, and the fallback call runs when the first call's report job posted no check ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).
- Every fallback call with a handoff job, fix-ci's among them, passes `fallback: handoff`, which the read runner now accepts, instead of a label taken from the first call's `lane-class`. Its lane record reads "posted no check" in place of "hit a credit stop" or "is empty" ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).

- An issue held before admission (an escalated or flagged intake verdict, or a hold label) whose done-when asks for what an unattended lane run cannot do now gets the admission comment that names those items and recommends the split, which a `needs_human` escalation used to drop. The intake rubric no longer sends such items through the `intent` flag: the model triages the lane-checkable items with their work class and leaves the hold to admission.

- `pr-unblock-dispatch.yml` dispatches `review-dependency` again at a head whose newest `pr-unblock / apply-dependency-verdict` check skipped `no-model-turn`. The `pr-unblock / review-dependency` check runs that started before that verdict no longer hold the head, a limit stop aside. Each such round still posts its round marker, so the round cap bounds the retries. The dispatcher records a head as reviewed only once a verdict check started after its newest `review-dependency` check, or once that check is a select job skip (`awaiting-human`, `not-applicable`, `superseded-sha`) that no verdict follows ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362)).
- The dispatch record's version is now 2, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could still hold a `no-model-turn` head as handled and skip the release ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362), [#9360](https://github.com/melodic-software/claude-code-plugins/pull/9360)).

## [4.7.0] - 2026-10-23

### Added

- Both review lanes hold a pull request for a person: `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/9aca743c4ed9aaf7870288a36586c3994e9321e4/.github/workflows/pr-review-cli.yml) v0.64.1 with `hold-label: needs-human`, and a changed file under `.github/standards/trusted-actors/**`, `.github/actions/check-trusted-trigger/**`, `**/CODEOWNERS` or `**/.gitmodules` holds as `trust-gate` whatever the review says ([Review-lane holds](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#review-lane-holds)).
- ci-status requires both review lanes on the head of a ready pull request: the newest `pull_request` run of each caller must have a successful status job whose `Apply the hold` step ran. A pending, failed, skipped or summary-mode review fails with the cause named; a lane the kill switch stopped passes; Dependabot, the release App and the standards-sync App are exempt by author id unless their PR changes a hold path.
- ci-status fails when a review-lane hold was lifted by anyone but a person on the base's trusted-actor list: the first removal of the human-gated label after the newest hold comment or lane-added label event decides.
- `pr-feedback-dispatch.yml`'s `rerun-ci-status` job re-runs the head's ci-status job when either review lane completes on an open same-repository pull request, after polling at most 10 minutes for a ci-status already in progress.

### Changed

- `fix-ci` dispatch keys on the head's `ci-lanes` commit status instead of ci-status, so a hold, a pending review or a contract failure no longer summons it.

## [4.6.4] - 2026-10-23

### Fixed

- Intake admission refuses `agent-ready` for an issue whose done-when asks for what an unattended lane run cannot do: a run on a named host or OS (such as a Windows 11 host), a paid eval, a run repeated N times, a measurement over time, or a page on a host outside resolve-issue's web-access domains. The issue gets `status: needs-decision` and the admission comment names each such item and recommends splitting it into a needs-human child issue. The intake rubric raises the `intent` flag for the same items.

## [4.6.3] - 2026-10-23

### Fixed

- A read runner scan that refused or failed on a model call's output (an oversize patch, a leak-scan block, a refused decode) now hands the round to a person instead of ending it as `no-model-turn`. When the scan job fails or is cancelled, the new `scan-refusal` job in `pr-run-activity-read.yml` uploads a `scan-refused-<lane>-<activity>-<attempt>` marker artifact. The write runner's reply and verdict jobs download it by name, so no decision depends on a failed job's outputs reaching a `workflow_call` caller. `address-feedback` escalates `feedback-invalid`, and `review-dependency` escalates `dependency-fix-not-landed` for an oversize patch or `dependency-invalid` otherwise. The read runner's `scan-refused` output and the write runner's `dependency-scan-refused` input are removed ([#9340](https://github.com/melodic-software/claude-code-plugins/issues/9340)).
- `address-feedback`'s reply job escalates `feedback-invalid` when the scan named replies it uploaded (a replies attempt or SHA-256) but none arrived, for example after a failed download, instead of skipping `no-model-turn` ([#9225](https://github.com/melodic-software/claude-code-plugins/issues/9225)).
- `pr-feedback-dispatch.yml` dispatches `address-feedback` again at a head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, on that head's next review or `pr-verify` completion. The `pr-unblock / address-feedback` check runs that started before that reply no longer hold the head. Each such round still posts its round marker, so the round cap bounds the retries ([#9218](https://github.com/melodic-software/claude-code-plugins/issues/9218)).

## [4.6.2] - 2026-10-23

### Fixed

- fix-ci's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. `fix-ci-handoff` and `fix-ci-rung-up-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API, and the fallback call runs when the first call's report job posted no check ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- A fix-ci round in which no call posted a check now posts `pr-unblock / fix-ci` failure on `fix-ci-context`'s head from the new `fix-ci-unreported` job when a call's broker-check job allowed the lane; as in the report job, a kill switch or a broker refusal posts nothing. fix-ci-dispatch counts that check toward `fix-ci-restarts`, so the loop stays capped whatever the run reports ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- The read runner's report job no longer counts the PR head it reads at report time as a gated head. With no caller or event head, any run head is forged, and failure is posted on the head it read ([#8945](https://github.com/melodic-software/claude-code-plugins/issues/8945)).
- The read runner's run job fails before the head checkout when its trigger gate read a head other than the caller's non-empty `head-sha`. This is fix-ci's part of [#8954](https://github.com/melodic-software/claude-code-plugins/issues/8954).
- A fix-ci patch collection the collector refused (`collect-patch.sh` exit 3) now reaches a person. The collect step sets `state` `refused`, the scan job hands it on as the new `scan-collect-refused` output, and `apply-patch` runs on it and escalates `ci-fix-invalid` through `report-escalation`. `apply-patch` and `apply-patch-rung-up` now take every patch input from one leg's scan job, never from a run job ([#8912](https://github.com/melodic-software/claude-code-plugins/issues/8912)).

## [4.6.1] - 2026-10-23

### Added

- `merge.read-token-floor` (default 0.3): the pr-merge gate reads its review evidence (timeline, comments, review-lane runs with their attempts, jobs and annotations) with `GITHUB_TOKEN` only while that token has at least this share of its hourly core limit left. Below it, or when the limit cannot be read, those reads use the lane App token, as they did before. The floor is only an early switch: when one of those reads is refused for a rate limit (a 429, or a 403 naming one), the gate reads that candidate's evidence again with the lane App token and marks `GITHUB_TOKEN` spent in the run cache for later candidates. Either token reads the same data, so no gate decision changes. The value is read at the default branch head. The repository's `GITHUB_TOKEN` pool, 1,000 requests an hour shared by every job, ran out on 2026-10-23 once these reads moved onto it.

### Fixed

- pr-merge.yml's `post-merge-dispatch` job caps its dispatch waits at 180 s instead of 300 s. Its whole run took 97-127 s on recent scheduled runs, and the re-run step after the dispatch sleeps up to 170 s while it reads back attempt 2. The lower cap leaves about 6.5 of the job's 15 minutes free, so a timeout no longer lands after the re-run POST and leaves attempt 2 unrecorded.
- Both dispatch steps send the dispatch again after no response only when gh's error shows the connection failed before the request was sent (a `dial tcp` error or a failed TLS handshake). A reset or timeout on an open connection may follow GitHub creating the run, so the step now warns and stops, as it does on exhaustion.

## [4.6.0] - 2026-10-23

### Changed

- The code review lane (`pr-review-hosted.yml`) runs on ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/83b739f625b501ad40c65dee7168d836883195e1/.github/workflows/pr-review-cli.yml) (v0.63.1), lane `code`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review / claude-review-status`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-review` footer. A newer push no longer cancels a running review: it waits for it.
- Both review lanes now run on `pr-review-cli.yml`, funded by the `reviews` role's `REVIEWS_CLAUDE_API_KEY` and `REVIEWS_CLAUDE_CODE_OAUTH_TOKEN`; the code lane no longer reads the bare `CLAUDE_CODE_OAUTH_TOKEN`.

### Fixed

- pr-merge.yml's `dispatch-full-run` and `post-merge-dispatch` jobs send the full-run dispatch at most three times: a rate-limited 403 or 429 waits retry-after seconds, else until one second past `x-ratelimit-reset` while none remain, else 60 s, and a request that got no response waits a full-jitter backoff, all within a per-job cap (180 s and 300 s) that keeps each job inside its timeout. Any other answer, a 5xx included, is not sent again, since the run may exist. A dispatch that still fails ends the job green with a warning naming the merge commit, uploads no `pr-merge-dispatched-<id>` record and skips the wait, so the next push or scheduled run starts the run instead of a red job.
- The wait for the dispatched run reads its status every three minutes instead of every minute, 13 reads over 39 minutes.

## [4.5.0] - 2026-10-23

### Changed

- The security review lane (`pr-review-security-hosted.yml`) runs on ci-workflows' `pr-review-cli.yml` (v0.63.1), lane `security`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review-security / security-review`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-security-review` footer. A newer push no longer cancels a running review: it waits for it.
- `address-feedback` and `pr-feedback-dispatch.yml` treat a `github-actions[bot]` comment as the reviewer's when its last non-blank line is a review lane's footer and its review is `github-actions[bot]`'s; `claude[bot]` findings are unchanged.
- One funding role, `reviews`, backs both review lanes and is keyed; the `reviews-security` role is gone.

## [4.4.0] - 2026-10-23

### Changed

- `review-dependency` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token. `pr-unblock.yml` runs it as six jobs: `review-dependency-select`, a base job with a read-only token, selects the pull request and uploads the context file and `context.json`, the run fields the verdict job reads; `review-dependency-not-run` posts the check neutral when the select job does not proceed, so the dispatcher does not send that head again; the model job and its subscription call return the verdict as structured output and leave a fix as a patch; `apply-dependency-patch` pushes the patch only beside a scanned `fix` verdict; and `apply-dependency-verdict` acts on the verdict whenever the select job proceeded. Every gate and head comes from the select job, and every model-call input from one leg's scan job.
- `review-dependency` has effect `read`, `applied-by` `patch: apply-dependency-patch` and `dependency-verdict: apply-dependency-verdict`, and routes to the `review` profile (Opus, 60 turns). Its skill gets Read, Grep, Glob, Skill, Edit, Write and Agent with no Bash, the context file read-only under `.lane/dependency/`, and one `WebFetch(domain:)` rule per configured host. A launcher activity with a `web-access` host list now gets those per-host rules instead of failing red. The new script activity `apply-dependency-patch` runs `apply-patch.mjs` under the `dependency-review` row, which now skips a moved head and holds each file to the new `dependency-version-change` content rule (`fixRefusal` on the local blobs, before any commit is built). The row's `dependency-manifests` rule reads the base `.github/dependabot.yml`, which the write runner copies out of the base, and its `dependency-verdict: fix` requirement reads the scanned verdict, which the write runner checks against the scan job's SHA-256 before the mint.
- `apply-dependency-verdict.mjs` reads the select job's `context.json` and the scanned `dependency-verdict.json`, each against the SHA-256 its own job recorded. A round with no verdict counts and skips `no-model-turn` only when the same call's scan handed on no patch, refused nothing, and the head is unmoved; a scan that refused an oversize patch escalates `dependency-fix-not-landed`, and any other gap `dependency-invalid`. A round with no model run named always posts its marker.
- The read runner carries, seals, scans and uploads a `dependency-review` skill's verdict at 49152 bytes, never beside a `review-threads` skill's replies, so the sealed payloads still fit five chunks. Its new `dependency-attempt`, `dependency-sha256`, `dependency-verdict` and `scan-refused` outputs come from the scan job alone.
- The schema requires `applied-by.patch` and `applied-by.dependency-verdict` of a `read` `dependency-review` skill.

- work-unblock's restart sweep reads a reopened fix issue's comments and events once: the recurrence check and the restart check share that read instead of listing both again, so each alert-filed issue costs one or two fewer lanes App calls per sweep, with the same verdicts.

- The work-unblock and intake-triage apply-verdict jobs log the lane token's and the job token's REST budget at mint and at job end (`.github/actions/log-api-budget`), as pr-merge does, so each run's lanes App spend is on record. pr-run-activity-write logs it at mint, before the head checkout replaces the base checkout the step runs from.

### Removed

- The write runner's `dependency-review` mode: its select step, the promote step's dependency branch, the verdict collect and upload steps, and its `dependency-round`, `dependency-run-sha256` and `dependency-run-attempt` outputs. A `dependency-review` activity on the write runner now fails red.

### Fixed

- The hourly triage sweep re-dispatches intake for an issue whose intake run failed: the `needs-triage` floor label, which lands on open whether or not intake runs, no longer counts as triaged, so the missing intake comment decides. A filing records an in-progress state before it files, so a failed write cannot file twice (`.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`, [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
- `status: needs-info` holds an issue like `status: needs-decision`: resolve-issue and apply-issue-patch start nothing on it, work-unblock neither adds `agent-ready` to it nor restarts it, and the WIP cap leaves it out of queued work. Pull request hold labels are unchanged ([#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

- The pr-merge lane holds a pull request before it enqueues when an owner, member or collaborator's newest comment on it says "do not merge". A later comment from that person lifts the hold ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane), [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

- The lane sweep's collect job reads every run of its 24-hour window. It made one capped run listing, which returns at most 1,000 runs and so covered about the last 4 hours. It now reads each workflow's run count with one `per_page=1` call and halves any range at the cap until each part fits, inside its 350-call budget with 170 calls kept for the units. A workflow it reads only part of is named in a warning, and its unit carries `window_complete: false`, which the judge is told to report as partial.

## [4.3.0] - 2026-10-23

### Changed

- Merge authority: a review flag holds only for a cost increase, a trusted-actor widening or a CRITICAL security finding; other open findings are reported. New **Trusted-actor widening** rule: a change that adds or widens an entry in `trusted-actors.json` waits for the owner whatever `high-path-floor` says; a pure removal merges.

## [4.2.0] - 2026-10-23

### Added

- `merge.gate-candidate-minutes` (a whole number of minutes; absent is no limit): how long one candidate's gate in `pr-merge.yml` may spend reading. Past it the gate starts no further read and the candidate is reported `unknown:candidate-deadline` (exit 11), never ready; a write already started finishes, and the loop goes on to the next candidate within `merge.gate-budget-minutes`. The first candidate a run stops is recorded in the gate cursor as deferred and gated first in the next run under `merge.gate-deferred-minutes` (20 here; absent is no limit), so a pull request whose gate always runs past the limit still gets a longer gate. One stopped at that ceiling gets a warning annotation and goes back to the capped rotation, never deferred again. Set to 4 here, so one slow candidate no longer holds the serialized merge queue for 20 minutes or more.

## [4.1.1] - 2026-10-23

### Changed

- pr-merge.yml's merge job runs its read-only post-merge check under the job's own `GITHUB_TOKEN` (the job gains `issues: read` for the demotion records) instead of the lane App token; only the `--remediate` run keeps the lane token. The gate's review-evidence reads run under `BABYSIT_VERIFY_GH_TOKEN` too, so the lane token is spent on writes and the reads that need the App's identity.

## [4.1.0] - 2026-10-23

### Changed

- An issue whose Size, Complexity or Uncertainty field is empty, or was last set by an account that is neither a listed human nor the lanes App, is no longer refused with `not-assessed`: the field reads as Size `small`, Complexity `medium` or Uncertainty `known`, and the run goes ahead at that budget. The config check rejects an `issue-dimensions` table that lacks one of those keys, or whose `small` size is `split`.
- `report-outcome`'s resume pick still passes over a `not-assessed` marker an earlier run left, so a turn-capped issue resumes.

### Removed

- `not-assessed` as an issue-dimension skip: `report-skip` and the write file's `dimension-skip` input no longer accept it. fix-ci's neutral `not-assessed` check is unchanged.
- The `labeled-after` predicate key from `predicate.mjs`.
- The unused copy of `checkPatchRules` and its old refusal list in `resolve.mjs`; the live check is in `patch-rules.mjs`.

## [4.0.0] - 2026-10-23

### Changed

- **Breaking:** `merge.diff-check.floor-paths` and `merge.diff-check.floor-script-scopes` are gone from the schema, so a `pr-pipeline.yaml` that still sets either fails validation; delete both keys.
- `merge.diff-check.floor-paths` and `floor-script-scopes` are gone, and `high-path-floor` holds only the external-effect path set and the manifest review that `babysit_risk.py` defines; a MED score of class and size reasons alone merges (#9270); the security lane holds only on a CRITICAL finding.

## [3.11.0] - 2026-10-23

### Added

- Intake admits clear issues with no person in the loop (owner decision Q51): after apply-verdict sets `status: ready`, `.github/scripts/intake-triage/admit.mjs` adds `agent-ready` as the lanes App when the issue meets the rules in `.github/actions/resolve-config/admission-rules.json` (type Bug or Task, or Feature under an open parent a listed human filed; class read-only, mechanical or scoped; Size Small or Medium; Uncertainty Known; a `- [ ]` task list; no open blocker (a blocking issue counts as done only when a listed human or a merge closed it), open pull request or refusing label; a listed author) and the issue lane's caps have room. Over a cap, or while an open pull request in the repository names the issue, it adds `admission-deferred`, which work-unblock's sweep admits once there is room and no such pull request is open; a refusal swaps `status: ready` for `status: needs-decision` and says why in one App comment ([#9214](https://github.com/melodic-software/claude-code-plugins/issues/9214)).

### Changed

- Lane patches reach review outside workflows and settings. Every [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json) row now refuses `github-workflows` (`.github/workflows/**`, which the lane token cannot push), `codeowners` (a `CODEOWNERS` file at the root, in `.github/` or in `docs/`), `gitmodules`, `settings`, `symlink`, `gitlink` and `rename-into-refused`, plus `backslash` on every row. The rest of `.github/`, `.claude/`, the root `.mcp.json`, agent instruction files, plugin hooks, monitors and bin, and an executable bit the patch sets now reach the branch and its review.
- `address-feedback` hands a pull request to a person as `feedback-protected-path` only when it changes `.github/workflows/**`, and a kept thread's scope may now hold a path elsewhere under `.github/`. `pr-merge` clears that reason once the pull request changes nothing under `.github/workflows/`.
- `resolve-conflicts` escalates `protected-path-conflict` only for a conflicted workflow, `.gitmodules` or `settings*.json`; a conflicted `CLAUDE.md`, `.claude/` or `.mcp.json` goes to the model, and `post.sh` keeps the resolution it staged. It escalates `unexpected-path-staged` only for a symlink, gitlink, backslash path, `.gitmodules`, settings file or `CODEOWNERS` change outside the conflicts; any other change the model stages is committed and reaches review.

- A pr-verify `fail` goes to an `address-feedback` round instead of a person. `pr-feedback-dispatch.yml` also runs when `pr-verify` completes: its new `post-verify-notes` job posts a fail verdict's summary and notes on the pull request, still at the judged head, as file-level review comments by `github-actions[bot]` whose first line is `<!-- pr-verify:fail-note -->` (`.github/scripts/pr-unblock/verify-notes.mjs`), posting only the comments the head does not hold yet, by file, so a retry after a partial post finishes it. An adopted pull request the lanes App did not open gets the notes but no round, so its author sees why the pr-merge lane refuses it. The dispatch job then decides as for a review run, with the newest completed review run at that head as its recorded upstream, so the gate and the broker check the same run as before. Only `pr-unblock / address-feedback` check runs started after the `pr-verify` run was created hold it, so a round an earlier review started at the same head does not swallow the notes.
- `address-feedback` keeps such a thread as the `verifier`'s finding, beside the reviewer bot's, when its review is `github-actions[bot]`'s on a marker-confirmed head. The round cap, the scope rule and the reply job are unchanged.
- The verifier prompt passes work the spec does not ask for with a note (`pass-notes`). It fails only a spec not delivered, a correctness or safety problem, a change of intent, or a change to a hold the owner keeps, and asks each note to start with its file path so the note lands on that file.

- `wip.pause-from` is set (2026-10-22), so over the WIP or held cap the issue lane pauses its runs, and over the queued cap admissions pause, instead of only alerting.
- Intake holds an issue on security only for a very-high risk, the security review's CRITICAL tier: the triage prompt sets the `security` flag only when the work would expose a credential, bypass a trust boundary or open an external attack surface, and apply-verdict no longer keeps an issue from `status: ready` for the `area: security` label alone.
- work-unblock admits nothing, newly unblocked or deferred, while the issue lane is paused over its WIP or held cap, so its sweep no longer undoes intake's deferral during a pause.

### Removed

- The `github`, `claude`, `mcp-config`, `new-executable` and `instruction-path` refusals, and the rule that a `script-exec-bit` row must refuse `instruction-path`.

## [3.10.0] - 2026-10-23

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run once when its first attempt failed on anything but infra, so a flaky test the diff did not cause costs no model run ([#9271](https://github.com/melodic-software/claude-code-plugins/issues/9271)). Its attempt number caps it at one re-run per run and head; a run where only ci-status failed gets none.
- fix-ci waits for that re-run before it takes a head, and also takes a head whose ci-status passed but whose advisory pr-test-windows run failed again, since the merge gate holds a pull request on any failing check.

### Changed

- This repository's Uncertainty `knowable` maps to `run`, so a Knowable issue runs instead of skipping with `research-first`. Unknown still skips with `probe-first` and Large with `split-required`.
- `work-resolve-issue` no longer adds `Hold: a human merges this` for `work-class: structural`; untrusted-provenance work, `merge: human` and the denied-path diff still carry it.
- intake-triage holds an issue for cost only when the charge is one no diff shows: a new paid service or subscription, a plan upgrade, or an account, organization or repository billing setting. A charge a diff shows (IaC, runner labels or cron, model, effort or turn flags, new secrets) gets no `cost` flag; the merge-time cost hold catches it.

### Removed

- The `labeled-after` key from the live config and its schema property, and the issue update-time read that served it. The `work-resolve-issue` lane's go-live cutoff is gone, so an issue labeled `agent-ready` at any time starts a run.

## [3.9.0] - 2026-10-23

### Added

- [`.github/lane-funding.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/lane-funding.json),
  the catalog of the seven lane funding roles (`reviews`, `reviews-security`, `issue-lane`,
  `intake`, `pr-unblock`, `pr-verify`, `automations`): each role's target secrets, whether it is
  keyed, and each lane's workflow, job, launcher and the secrets its job reads today, with a JSON
  schema beside it. No workflow's secrets change. `callers.test.mjs` fails when a job that reads a
  Claude secret is missing from the catalog or reads other secrets than it lists, when a job reads
  an API key off `run-claude-cli`, or when a role's secret names do not follow its prefix.

### Changed

- `address-feedback` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token. `pr-unblock.yml` runs it as five jobs: `address-feedback-select`, a base job with a read-only token, keeps the threads and uploads the thread file and `run.json`; the model job and its subscription call answer them and hand on a patch and their replies; `apply-feedback-patch` pushes the patch; and `publish-feedback` posts the replies. Every later job takes its gate, head and reply inputs from the select job, never from a model call's run job, and `publish-feedback` runs whenever the select job proceeded. A skip or an escalation posts both checks neutral.
- `address-feedback` has effect `read`, `applied-by` `patch: apply-feedback-patch` and `feedback-replies: publish-feedback`, and the `code-fix` route. The new script activity `apply-feedback-patch` runs `apply-patch.mjs` under the `review-threads` row, which now skips a moved head. The row's `kept-threads` rule reads the select job's thread file, `named_paths` included. A needs-human PR's push still takes a fix that a trusted person with write access asked for.
- `publish-feedback.mjs` requires an empty `fix_sha` and names the fix itself: the one lanes App commit in the range, committed by `web-flow` with a valid signature, that carries the `Lane-Activity: pr-unblock/address-feedback` trailer. A push that was superseded, refused, escalated or held leaves none, and a `VALID` round ends `feedback-not-landed`. `replies.jsonl` is capped at 49152 bytes and `run.json` at 1 MiB. A round with no `replies.jsonl` still counts. It posts a `no-model-turn` skip rather than escalating only when the same call handed on no patch and the head has not moved; otherwise it escalates. `replies.jsonl` must match the SHA-256 the scan job recorded. The push and reply jobs take every model-call input from one call, the subscription call when it ran, and push a patch only beside that call's replies. The read runner passes the `pr-feedback-dispatch.yml` trust to its gate only for a `review-threads` call. The round marker names the model attempt that produced the replies, so a re-run of the model job counts a new round. The read runner carries, seals, scans and uploads it at that cap; all four sealed payloads at their caps still fit five chunks.
- The read runner accepts a `pr-feedback-dispatch.yml` dispatch and supports `prepare: review-threads` in PR patch mode. It checks the select job's thread file against its SHA-256, PR and head. It stages the review-thread tool read-only under `.lane/feedback/`, except `state/`, which only the tool writes (all of `.lane/feedback/` is denied to the file tools), and names the tool's path and subcommands in the preamble. Its `feedback-attempt` output comes from the scan job alone.
- The schema requires `applied-by.patch` of a `read` skill with `prepare: ci-context` or `review-threads`, and `applied-by.feedback-replies` of a `read` `review-threads` skill.

- The Funding section of the PR pipeline convention names the seven roles and points to the
  catalog instead of listing lanes in prose.

### Removed

- The write runner's `review-threads` mode: its select, promote-scope, collect and upload steps and its `feedback-round`, `feedback-run-sha256` and `feedback-run-attempt` outputs. A `review-threads` activity on the write runner now fails red.

## [3.8.0] - 2026-10-23

### Added

- intake-triage.yml writes the triage verdict as the lanes App after each triage run that applied: the proposed `work-class:` label, the Size, Complexity and Uncertainty issue fields, and `status: ready` or `status: needs-decision`, from the lane comment's class line and four verdict lines, each checked against a closed set (`.github/scripts/intake-triage/apply-verdict.mjs`, lane `intake-triage`, activity `apply-verdict`, effect `mutate-tracker`). It never adds `agent-ready`, keeps a class or field a listed human set, and drops the comment's "a maintainer confirms" wording once it applied the class ([#9213](https://github.com/melodic-software/claude-code-plugins/issues/9213)).

### Changed

- Intake triage follows a written priority, type and dimension rubric, and may no longer apply `good first issue` or `help wanted`.

## [3.7.0] - 2026-10-22

### Added

- pr-merge holds a pull request that could add or raise a charge (IaC files, new workflow
  schedules, billed runner labels, new secrets references, new model legs, raised model-leg
  timeouts, pipeline config changes) for a human unless its body links an owner
  `**Decision recorded.** Cost:` comment on its closing issue or the pull request itself.

## [3.6.1] - 2026-10-22

### Fixed

- work-resolve-issue's report-outcome names apply-issue-patch's escalation reason when it refused a done run's patch, instead of saying the run committed nothing.

- pr-unblock's `fix-docs` reports its check on the head it ran on when the PR head moves while it
  runs, instead of posting failure on the new head and blocking the merge. A new `fix-docs-head`
  job, which runs no head code, reads the head both `fix-docs` calls pass as `head-sha`; a run head
  that matches no gated head still posts failure. The read runner's new `post-decline` input
  (default `true`) is `false` for fix-docs, so a run that stops before its trigger gate posts
  nothing and the once-per-PR dispatcher tries the PR again.

## [3.6.0] - 2026-10-22

### Added

- `adoption.spec-from-body-apps`: the App ids whose PR bodies a script writes (the release App
  and the standards-sync App here). An adopted PR that closes no issue is judged against its own
  title and body when a person or one of these Apps opened it; resolve-pr hands the verifier that
  text as the spec, and the verdict records `intent: pull-request`. Any other App, the lanes App
  included, still needs a closing issue, since a model that wrote the diff would also have
  written its spec. A body last edited by anyone but its author or a trusted person is not the
  spec, and the verdict records the body's sha256 (`intent_sha256`).

### Changed

- Adoption covers every account on `.github/standards/trusted-actors/trusted-actors.json`, people
  and Apps alike, matched by id (owner decision 2026-10-22): fix-ci fixes a red PR the release
  App, the owner or anyone later added to the list opened, and `merge.verify-authors:
  lane-or-owner` judges it. An App's PR is adopted at once; a person's still waits
  `adoption.idle-hours`. Dependabot's red PRs stay with review-dependency.
- The verifier fails a change that alters behavior or intent the spec does not ask for, a lane's
  CI fix included, which escalates the PR to a person.

### Removed

- `adoption.owner-ids`: the trusted-actor list is the one source. Without `adoption.idle-hours`
  nothing is adopted.

## [3.5.1] - 2026-10-22

### Fixed

- pr-merge's `post-merge-dispatch` job re-runs a red full run it dispatched once before the
  demotion alert judges it, when the run was created within `red-main.confirm-wait-minutes` plus
  50 minutes (90 by default) and demotes by the affected-set rule, not only inside a lane merge's
  attribution window. The alert demotes only when that re-run fails too.

## [3.5.0] - 2026-10-22

### Changed

- resolve-config accepts `merge-base`, `review-threads` and `dependency-review` on a `read` skill
  that hands its change on as a patch (`applied-by.patch`), as the Activities section already
  describes, so those activities can move to the read runner. Without `applied-by.patch` the
  shape is still refused
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [3.4.2] - 2026-10-22

### Fixed

- work-unblock's sweep re-fires an `agent-ready` issue whose work-resolve-issue run was cancelled
  in `pick-slot` (its timeout while it waited in the WIP cap step) after `admit` passed and before
  `resolve-issue` ran, like a failed run and under the same once-per-workflow-version re-fire
  record ([run 39711139895](https://github.com/melodic-software/claude-code-plugins/actions/runs/39711139895)).
  A run a newer `agent-ready` run replaced while it waited ran no job and is still not re-fired.

## [3.4.1] - 2026-10-22

### Fixed

- Lane scripts send a GitHub REST GET again when it is answered 5xx, answered 200 with an empty or unparsable body, or fails on the network, after about 2, 4 and 8 seconds with jitter, instead of failing the step on the first bad answer. Each attempt is aborted after 20 seconds, and the time failed attempts take plus the waits is capped at 60 seconds per API client. POSTs, 4xx answers, rate limits and other thrown errors are not retried here, and a retry line never prints an error's message.
- pr-verify, the feedback dispatcher and the workflow_run trigger gate read a commit's pull requests through GraphQL's `associatedPullRequests` when `GET /commits/{sha}/pulls` still fails after those retries, and apply the same open, same-repository and base filters to the result.

## [3.4.0] - 2026-10-22

### Added

- `merge.verify-authors: lane-or-owner` judges the lanes App's pull requests and the owner
  account's, matched by account id, so an idle owner pull request the pr-merge lane adopts has a
  verdict. This repository sets it.

### Changed

- The verifier's spec now counts text a trusted human wrote even when that human opened the
  pull request, so an owner pull request whose closing issue the owner wrote is judged against
  that issue. Text by the lanes App, any other Bot or App, or an untrusted account is still left
  out.

### Fixed

- The issue lane's new or changed scripts land executable. apply-patch now makes each file that
  ends in `.sh` or starts with `#!` mode 100755 after every refusal passes, under the new
  `script-exec-bit` row key that the `issue` row sets. The model still sets no mode:
  `new-executable` refuses any executable bit the patch itself carries. Before this, the patch
  committed such files as 100644 and check-affected's exec-bit check failed
  ([run 39729937593](https://github.com/melodic-software/claude-code-plugins/actions/runs/39729937593)).
  A resumed run keeps the executable scripts an earlier lane commit landed.
- Inside an issue lane's patch run, `check-affected.sh --uncommitted` gives its snapshot the same
  bits: the checks wrapper sets `CHECK_AFFECTED_SCRIPT_EXEC_BIT=1`, so exec-bit passes on a new
  script. A run that commits gets no such flag and still has to chmod its own scripts.
- The `issue` row now refuses `instruction-path`, so the issue lane pushes no plugin hooks,
  monitors or bin, and no agent instruction file. A row that sets `script-exec-bit` must refuse it.

## [3.3.3] - 2026-10-22

### Fixed

- Write lanes deny git commands: they reach git only through the base wrappers. In `merge-base`
  mode, whose skill resolves the merge with git, the lane denies git's global options, the
  subcommands that read config or reach a remote, absolute and parent paths, quotes, and the flags
  or paths that read a file outside the index (including `blame` and `grep`) or run a diff or
  text-conversion program
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- check-wip-cap treats a GitHub search answer with `incomplete_results: true` as unknown, not as a failed read: new admissions pause whether or not `pause-from` is set or reached, with `admission_basis` and `admission_reason` `search-incomplete` and a `check-wip-cap` warning, so work-unblock defers newly unblocked issues instead of admitting without limit on a false empty. A read that fails without that answer still fails open, the queued cap still pauses only past `pause-from`, and no run pause changes.
- check-wip-cap's over-cap warning names why the lane keeps running (the base config could not be read, `pause-from` is not set, or `pause-from` not reached), and work-unblock's deferral log names its reason instead of always citing the queued cap.

## [3.3.2] - 2026-10-22

### Fixed

- The verifier verdict rules say a failed read of a verify record, run time or diff refuses `verify:unreadable` rather than keeping `verify:earlier-fail`, except a diff GitHub answers with 404, which still keeps it (#9063).

- fix-docs runs again, now in the read runner's default `dontAsk` mode instead of `auto`, which
  run-claude-cli's subprocess env scrub forced back to the default mode
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).
  Its Bash runs only explicit allow rules: each `ai-slop:audit` script by absolute path under
  `.lane/plugins`, bare and double-quoted, plus `sha256sum` and `mkdir -p` in `.lane/scratch`
  for the fix flow's digests, and `Edit(./.lane/scratch/**)` so a redirect into the scratch
  directory is approved. It denies `git`, the `user-scope.sh` script, `NotebookEdit` on the
  staged plugin and the write lanes' shell deny set. The staging step also makes `.lane/prompt.md`
  and `.lane/` read-only, so a script's `--out` lands only in `.lane/scratch`.
- Write lanes also deny `wc`, a read-only command that runs with no allow rule and can print
  file contents in its errors.

## [3.3.1] - 2026-10-22

### Fixed

- The read runner's permission-mode check accepts a leg whose CLI reports `default` when `dontAsk` was asked for, so read-runner skills such as fix-ci no longer fail after their model leg ([#8964](https://github.com/melodic-software/claude-code-plugins/pull/8964)). The launcher's `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` forces the CLI into `default`, and the launcher always passes `--permission-prompts none`, under which Claude Code denies every call no rule allows ([CLI reference](https://code.claude.com/docs/en/cli-reference)). Every other mismatch still fails, and a test fails any launcher pin not yet checked to pass that flag.

- The pr-unblock and feedback dispatchers wait out a rate limit on the repository's job token instead of failing at once: retry-after when GitHub sends it, else until one second past the reset when no requests remain, else one minute, then the call is sent once more. Waits are capped at six minutes per run, summed; a reset further away fails at once and names the reset time.
- The lost-run reconciler re-runs, once, the failed jobs of an intake-label-needs-triage run whose first attempt failed within its lookback, so an issue the floor label missed (a rate limit, most often) gets it on the next tick.

## [3.3.0] - 2026-10-22

### Added

- `models.issue-dimensions.complexity-profiles` maps an issue's Complexity to the profile its run starts on. This repository sends high Complexity to the new `code-xhigh` profile (Opus at effort xhigh); low, medium and unset keep the activity's default.
- A profile's `escalate-to` names the profile one model rung up, which a run resolved at resolve-config's new `model-rung` input 1 takes instead. `code-fix` escalates to `code-xhigh`; nothing escalates past it.
- fix-ci retries once one rung up: a run that changed nothing and escalated only `unfixed` or `not-reproducible` checks skips apply-patch with the new `rung-up` reason, and the same pr-unblock run runs fix-ci and apply-patch again at `model-rung` 1. Unless that retry's patch applies cleanly, the pull request goes to a person, as do `protected-path`, `weaken-required` and `flaky` escalations.

- A top-level `adoption` section (`idle-hours`, default 24; `owner-ids`, default empty) names
  owner accounts whose pull requests the lanes adopt. pr-unblock-dispatch starts `fix-ci` for a
  non-draft owner PR whose `ci-status` failed once its last update and its head commit are both
  `idle-hours` old, with no `do-not-merge`, `needs-human` or tracker human-gated label and no
  body line starting `Hold:` (babysit's reading: any case, after any whitespace, a bare CR ends
  a line). This repository adopts kyle-sexton's PRs after 24 hours (owner decision Q22).

### Changed

- The Fable rung above `code-xhigh` stays off: no profile names `fable` or `best`, pending an owner decision on a per-week Fable allowance for the lanes.

- While `adoption.owner-ids` lists anyone, the tracker's human-gated label also holds lanes App
  PRs from `fix-ci`. A base `.work-item-tracker.json` that is not JSON holds only the adopted
  owner PRs, and fails the dispatcher run; lanes App PRs still get `fix-ci`.

- The pr-pipeline README's WIP cap section names each `agent-ready` writer and whether the queued cap paces it: only work-unblock's new labels are paced.

### Fixed

- fix-docs is paused: its pr-unblock slot is `enabled: false`, so a dispatched run skips at
  resolve-config before any model turn, and the broker grants it nothing. Under run-claude-cli's
  subprocess env scrub the CLI forces the default permission mode instead of `auto`, so every
  fix-docs run failed its permission-mode check after spending a model leg
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).

- The queued count no longer counts an issue twice when a person edits its lane PR's first body line: an open lane PR whose first line names no issue is matched by its `work-resolve-issue/issue-<n>-...` head branch, at one pull request read each.
- work-unblock's `label-unblocked` job runs one at a time across the repository, so a burst of closes or a close run beside the hourly sweep can no longer each admit the queued cap's whole room.

## [3.2.0] - 2026-10-22

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run that failed only from an outside outage: each failed job hit its time limit, had an install step cancelled or timed out, or lost its runner. An install step that exits with a failure, such as `npm ci` on a stale lockfile, counts as a real failure. It re-runs at most twice per run, 15 then 30 minutes after the attempt ended, only while status.npmjs.org and githubstatus.com both show no incident, and never a run with any other failure.
- fix-ci starts no model run on a head whose required-run failures are all infra while the reconciler will still re-run it; once both re-runs are used, or the run is older than the reconciler's 24-hour lookback, fix-ci takes the head.

### Fixed

- The red-main report names every red full run since the last green one that has no report on the log, so a report the repository-wide concurrency group cancelled while pending is seen in the next report, whose range re-decides over its merges.
- The red-main report takes the oldest `github-actions[bot]` issue carrying the log marker as its log, and counts only that account's comments on it (matched by user id) toward the daily cap and the dedupe, so a newer issue carrying the marker can neither take the reports nor reset the cap.

## [3.1.1] - 2026-10-22

### Fixed

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) now fit the 32768-byte carry cap after JSON escaping: each `denied` entry's `tool_name` is cut to 100 characters, the write file keeps at most 4 `local_command_stderr` messages as the read file does, `subtype` and up to 10 model names are cut to 100 characters, and `local_command_stderr_total` counts every stderr message. When the file would still exceed the cap, the oldest stderr messages drop first, then denials from the end, so a PR-mode read run's scan job no longer refuses an oversized file.

- `check-trusted-trigger` stops a pull request whose `base.ref` is not the payload's `repository.default_branch` with the new reason `untrusted-base`, on `pull_request`, `workflow_dispatch` and `workflow_run` alike, as it does a payload without the default branch. Before, a listed author's PR stacked on another branch passed. `report-check-run` maps `untrusted-base` to no skip reason, so the check posts failure, not neutral.

## [3.1.0] - 2026-10-22

### Added

- A skill activity's `permission-mode` (`dontAsk`, the default, or `auto`) sets the read
  runner's launcher mode, through `resolve-config`'s new `permission-mode` output. A step after
  each launcher leg fails the run unless the CLI's init message reports that mode. fix-docs sets
  `auto`
  ([ADR 0049](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).

### Changed

- fix-docs moves into the `pr-unblock` lane, so its check is `pr-unblock / fix-docs`.
  `pr-unblock-dispatch.yml` dispatches it on each push to main, once per open, ready pull request
  a person opened that changes a Markdown file, carries no `do-not-merge` or `needs-human` label
  and never had a fix-docs run, at most `limits.fix-docs-per-run` (default 2) per run
  ([README, fix-docs](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
- fix-docs runs on the read runner with no write token, on ci-workflows' run-claude-cli and the
  automations role's API key first. pr-unblock.yml calls the read runner twice, each call with one
  Claude secret: `fix-docs` passes only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-docs-subscription`
  passes only `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only after a credit stop or with the
  key empty. Every fix-docs job trusts the default branch tip
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- fix-docs's change leaves as a patch that the `apply-docs-patch` job pushes as one commit, only
  when a patch was written. A refused patch posts the `pr-unblock / apply-patch` check neutral and
  labels nothing
  ([pr-run-activity.md, prepare: apply-patch](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).
- The `default` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  refuses every agent instruction path, caps a patch at 300 files and takes a moved head with
  `--3way` (`skip-moved-head: false`).
- The read runner's launcher takes a skill with no prepare mode that hands on a patch: Bash,
  Edit, Write and Agent as tools, no Bash allow rule, and `Read(./.git/**)` denied. It fails red
  on `checks`, `self-checks` and `verify-scripts`.
- fix-docs routes to the new `docs-fix` profile, a mechanical worker from the multi-agent role
  map, which resolves to sonnet.
- The launcher accepts `web-access` (`domains: any` only), staging the research skills and their
  plugins under `.lane/`. fix-docs leaves it off.

### Removed

- The `pr-refine` lane and `pr-refine.yml`, whose `pull_request` trigger ran the read runner's
  scan job off main, where the `pr-pipeline-scan-carrier` environment refuses it.

## [3.0.0] - 2026-10-22

### Added

- The optional `red-main` block (`dry-run`, `daily-cap`, `max-culprit-age-hours`, `confirm-wait-minutes`) and the Red main rule: after a full run on `main` fails, `post-merge-demotion-alert.yml`'s report job confirms the red on its one re-run, pins the culprit merge, and reports whether the bot would revert it, in dry-run only ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).

- `apply-issue-patch`: a script activity that runs
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  with the `issue` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  (now capped at 300 files, and at 5 MiB per patched blob and 20 MiB in all). It makes a new `work-resolve-issue/issue-<n>-<run id>-<attempt>`
  branch at the commit the model worked on, with one commit, after re-reading the issue's hold
  labels and `agent-ready`, and names that branch in the run's `lane.json`. On a resumed run its
  refusals cover everything the new branch adds since the default branch, not only the patch. resolve-issue sets
  `applied-by` (`patch: apply-issue-patch`, `work-outcome: report-outcome`), and
  `activity-rules.json` refuses it any write effect.

- Monitoring lane signal 9, lane stop: a lanes App comment in the window that starts with a work-resolve-issue `outcome=funding`, `outcome=limited` or `outcome=turn-cap` marker files or updates one issue per outcome (`lane-stop:<outcome>`), listing each stopped issue ([README.md, The monitoring lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane)).

- `limits.admission-min-per-hour` (default 1, 0 to 100): the issue lane's queued cap never falls
  below this rate times `wip.merge-rate-window-hours`, so a day with no lane merges cannot hold
  admissions shut. 0 removes the floor.

- post-merge-demotion-alert.yml files one fix issue per newly failing check of a red scheduled or
  dispatched full run on main, at most 5, beside the new demotion or failure record, and dispatches
  intake triage for each. The issue holds fixed text only (the failing job's name in a checked
  charset, never an annotation title, hex SHAs, the run link and the record number), carries no
  label, is locked before intake reads it, and is reopened when its check fails again, keeping
  `agent-ready` and with no second intake dispatch, so a repeat goes straight back to agents. A fix
  issue that could not be filed, locked, reopened or sent to intake is named in a comment on the
  record.
  The record keeps `needs-human`; closing a fix issue changes nothing on it.

- `merge.max-verify-fails` (default 3): counted fails at that many distinct heads refuse `verify:repeated-fail`, which needs a human, whatever a later pass says. Fails of other open or closed pull requests in the repository that close the same issue count too, so a new pull request does not reset the count. A value that is not a count of 1 or more, empty or non-scalar included, is 1. The escalation comment names the refusal, and skip-unchanged carries it forward like the other verifier refusals.

- **Role profiles in `models`.** A profile may name a multi-agent role (`role`, optional `workload` and `effort-role`) in place of a model. resolve-config takes its model and effort from the base checkout's [multi-agent role map](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/multi-agent/reference/defaults.yaml). The model is `opus` when the role map gives `inherit`, `default`, a model ID or nothing. The schema refuses a `model` or `effort` key on a role profile, so it can name neither `default` nor a model ID.
- **fix-ci routes to a role profile:** a worker on code at the verifier's effort, with 75 turns as before.
- **New `applied-by-patch` output** from resolve-config: the activity that applies the selected activity's patch.

- The optional `red-main.remedy` key, `rollback` (default) or `fail-forward`. Under `fail-forward` the red-main report plans no revert: its decision is `human`, naming the remedy, and a person or a fix pull request repairs `main` ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).

- A `branch-cleanup` leaf (`max-deletes-per-run`, default 25) and the daily
  maintenance-delete-stale-branches.yml that applies it: a branch lives as long as its issue is
  open, and one whose pull request closed or merged and whose linked issue closed is deleted, at
  most `max-deletes-per-run` a run with the calls those deletes need reserved first, after a re-read of its tip and open pull requests and a
  ledger line in the step summary and an artifact. A lane run's stop marker does not keep a
  branch once its issue closed. A branch with an open issue or pull request, and a protected or
  ruleset branch, are never deleted; a branch that never had a pull request, or whose tip moved
  after its pull request closed with commits ahead, is listed for a person. A manual run is a
  dry-run by default.

- `merge.quarantine-days` (default 7, at most 30): days a quarantine issue excuses its suite's out-of-set
  failures from post-merge demotion. post-merge-demotion-alert.yml now checks out main's tip and,
  when every newly failing suite is outside the merges' affected set, files no demotion record and
  runs no red-main report; it files or comments each suite's quarantine issue instead.

### Changed

- resolve-issue runs on the read runner. Its model job holds no write token: only the read-only
  job `GITHUB_TOKEN`
  [claude-code-action](https://github.com/anthropics/claude-code-action) needs, and no App token
  or `id-token`. Its uncommitted change leaves as a patch, collected also after a turn cap or a
  usage limit so a resumed run continues it. The earlier-work check, the issue file, the reuse
  path and the reuse summary pass move to the read runner with it
  ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
- work-resolve-issue.yml checks the labeler in an `admit` job, with a read-only token and no
  secret, before any job that gets the lane's Claude credential: an unlisted account's
  `agent-ready` starts no credentialed job.
- The write runner refuses an issue skill, and its apply-patch select step runs the activity's
  own script from the base.

- The monitoring lane and the lane sweep reopen the closed issue they hold for a key or fingerprint, with a comment carrying the new evidence, instead of filing a new one; a close as not planned or duplicate mutes it, and the lane sweep no longer limits this to a 14-day window ([README.md, The monitoring lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane)).

- The Models and Limits sections point at `pr-pipeline.yaml` (`models.profiles`, `models.routes`, `limits` and `wip`) for this repository's values instead of restating them; the built-in defaults stay.

- The held cap pauses the issue lane like the WIP cap: on or after `wip.pause-from`, at or over
  `wip.held-cap` held lane PRs, work-resolve-issue starts no run and work-unblock re-fires none.
  It used to alert only. This repository sets `held-cap: 10` (was 60).
- check-wip-cap publishes `pause_reason` (`wip`, `held-cap` or `wip,held-cap`) and, on every
  pause, logs `admission paused: reason=... countable=... wip_cap=... held=... held_cap=...` as a
  `::notice` and in the step summary, so pauses can be counted.
- `docs/adr/**` joins this repository's `floor-paths`: a lane PR that changes an ADR scores HIGH
  and waits for a human.

- pr-verify hands the judgment to the subscription job on run-claude-cli's `handoff` output instead of the `credit-stop` class, so a key the API refuses with status 401 or 402 (class `auth`) also falls back; a 403 still fails the key job. The key-leg warning says whether to replace the key or rotate one in. The subscription job's lane record is plain `pr-verify`, with the reason in `fallback-reason` (`credit-stop`, `auth` or `no-key`). Every ci-workflows action pr-verify uses is pinned to v0.58.0, whose run-claude-cli installs the latest Claude Code release by default.

- The unattended merge reads the `merge:` block and `babysit_loop_merge` at the default branch head as well as at the pull request's base SHA and takes the stricter value of each setting, so a tightening on the default branch reaches pull requests opened before it; the two must name the same agent identity and enable the same authority ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- Merge authority no longer promises a later C4 rung: `merge.rung` stops at `C3`, and the pr-merge lane merges on the verifier verdict.

- **BREAKING:** `models.profiles`, the `models.issue-dimensions` option maps and `models.issue-dimensions.sizes` are written in block style, one key per line, in `docs/conventions/pr-pipeline.yaml` and in `examples/claude-code-plugins.yaml`. Values and key types are unchanged. The shared YAML-subset reader that `set-dimensions.sh` and `scripts/check-convention-yaml.sh` use now refuses flow mappings, so a consumer's `pr-pipeline.yaml` that writes these maps as `{ ... }` must rewrite them in block style.

- This repository sets `limits.turn-cap-restarts` to 1: one run that reaches its turn cap resumes from its pushed branch per `agent-ready` a listed human adds, then goes to a person. The built-in default stays 0.

- The pr-merge lane no longer holds a pull request for an earlier head's `verify:earlier-fail` once its current head has counted pass or pass-notes verdicts whose runs were all created after every such fail's run (each `created_at` read fresh from GitHub, which a re-attempt keeps), and the pull request's own change at the head differs from its change at every failed head. That change is a digest of the changed lines in the compare diff from the merge base with the base branch, so a head that only merges the base, an empty commit, or an edit that only changes whitespace or adds blank lines keeps the hold, as does a diff that cannot be read. Those passes then decide, so a changed or untrusted spec still refuses. Skip-unchanged no longer carries a `verify:earlier-fail` forward while a pass artifact names the head.

- The HIGH path floor rule and the `floor-paths` and `floor-script-scopes` descriptions say that a test file (a `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name; a `tests/` or `fixtures/` directory alone is not one) under a plugin `scripts/` directory, a `floor-paths` glob ending in a `scripts` directory or a script scope, safe, under no declared path and named by no other changed file, no longer holds a pull request for that reason; every other floor entry and `floor-paths` glob, and `denied-paths`, still do.

- fix-ci runs on ci-workflows' run-claude-cli v0.54.0, on the automations role's API key first.
  pr-unblock.yml calls the read runner twice, each call with one Claude secret: `fix-ci` passes
  only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-ci-subscription` passes only
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only when the first call's key leg hit a credit
  stop or its key is empty. A call that hands off uploads nothing, records no lane outcome and
  posts no check; the fallback call's lane record names why it ran. Both calls queue in the
  per-PR write group
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- The read runner stages a PR-mode skill's plugin, CI context, scratch directory and prompt
  under `.lane/` in the checkout, which `--restricted` can read, and leaves `.lane/` out of the
  patch. A head that already holds `.lane` fails red. A staged plugin with no `.mcp.json` gets
  an empty server list, and the patch leaves out the CLI's empty scrub stubs; a stub name the
  head does not track that holds anything else fails the collector, so nothing is collected.
- fix-ci's patch goes through
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  as the `apply-patch` activity, named in fix-ci's `applied-by`. The `ci-context` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  caps a patch at 300 files and gains the optional `instruction-path` refusal, so fix-ci still
  pushes no agent instruction path. apply-patch refuses a row with no `requires` list.
- `collect-patch.sh` runs git against a fresh scratch repository that borrows only the checkout's
  objects, so no filter, hook, fsmonitor or include the activity planted in `.git` runs. The PR-mode
  leak scan applies the patch onto the gated head, as apply-patch does, and scans every file it
  makes; it scans copies of the reply and patch that the uploads then read, and the run's
  `patch-sha256` is the scanned copy's.
- The read runner's PR-mode model job uploads nothing and writes no step summary. It hands the
  reply, the run fields and the patch to a new scan job as job outputs sealed with
  `seal-lane-output` to the committed `.github/lane-keys/scan-carrier.pub`, each with its byte
  count, with the patch capped at 256 KiB. The scan job runs with `contents: read`, no `id-token`,
  and in the `pr-pipeline-scan-carrier` environment, whose `SCAN_CARRIER_PRIVATE_KEY` its
  `open-lane-output` step alone reads; each caller passes it by name as `scan-carrier-private-key`,
  and `scripts/check-scan-carrier-secret-shadow.sh` fails when a repository or organization
  secret shares the name. It fails closed on a withheld, oversize, mismatched or
  unopenable output, scans against a fresh checkout of the gated head, and is the only job that
  uploads the reply, patch and verdict
  ([pr-run-activity.md, The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job)).
- The read runner's dirty-tree check runs through `collect-patch.sh` and prints no path, and a
  PR-mode run removes the workspace's `.git` and `.base/.git` after the collector, so no git
  config the model planted runs after its legs.

- The HIGH path floor rule says that adding only `disable-model-invocation: true` to a plugin skill's frontmatter that no agent could preload, and a non-script file under `plugins/<plugin>/evals/`, are exempt from the floor entries `babysit_risk.py` names; manifests, named files, declared paths and `denied-paths` still hold them.

- The HIGH path floor rule says a plugin or marketplace manifest leaves the floor and clears only when every key that differs is on its allow-lists (metadata such as `version` and `description`, or a title or description edit on an existing `userConfig` key); any other difference, including an added `userConfig` key, a `defaultEnabled` change and a removed `version`, a new `plugin.json`, an added, removed or renamed marketplace entry, or a side that cannot be read or parsed scores HIGH as `manifest-review-required`.

- The HIGH path floor rule says a changed file in an eval case whose `case.yaml` could name a `scaffold_script`, or could not be read, and any script or mode 100755 file under `plugins/*/evals/**`, scores HIGH as `eval-scaffold-review-required`; a manifest key on the allow-list clears only with its expected type, compared as JSON.

- `publish-feedback` counts a fix commit as touching a review thread on a skill's `SKILL.md` when it changes any file in that skill's directory (its `evals/` and `reference/` included), so a fix to a skill's evals no longer escalates `feedback-not-landed` (#8832). Every other thread still needs its exact path, and the range check is unchanged.

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) record `denied` as one `{tool_name, input}` for each of the first 20 denied calls, where `input` is the call's command, `file_path`, `path` or `pattern` cut to 300 characters, dropping entries from the end until `denied` serializes to at most 8192 bytes, and `denied_total` as the count of all of them, so a PR-mode read run's sealed `act-turns.json` stays under its 32768-byte carry cap; the read file gains `denied`, and a denied Read, Grep or Glob call now keeps its path or pattern. The step summary shows each as `tool: input`, then `(+N more)` when some were cut. In a PR-mode read run, `denied` travels in the sealed `act-turns.json` and reaches the step summary only after the scan job's leak scan.
- The `skill-reply-*` artifact is kept 7 days instead of 3 in both run-activity files, matching the patch and dependency-verdict artifacts.

- check-wip-cap is the one admission pacing gate. It counts queued work (open `agent-ready`
  issues with no hold label that no open lane PR names on its first body line, plus held lane
  PRs) against the queued cap, `max(limits.admission-factor × lane merges per hour,
  limits.admission-min-per-hour) × wip.merge-rate-window-hours`. At or over it, on or after
  `wip.pause-from`, new admissions pause: the action's new `admission-open` output is `false` and
  it logs `admission paused: reason=queued queued=... held=... cap=...`. Runs never pause on it.
- work-unblock admits at most the queued cap's room per run. A ready issue past it gets
  `admission-deferred`, and each hourly sweep revisits those issues oldest first, re-admitting only
  one whose newest `admission-deferred` the lanes App or a listed human added.
- The status JSON gains `queued_issues`, `queued_truncated`, `queued_total`, `queued_cap`, `admission_factor`,
  `admission_min_per_hour`, `queued_over`, `admission_open`, `admission_reason`,
  `admission_room` and `admission_basis`.

- `wip.pause-from` is empty: over the WIP cap or the held cap the issue lane alerts and keeps starting runs.

### Removed

- The read runner's `output-mode` input: patch mode follows the activity's `applied-by.patch`,
  and issue mode refuses an activity that names no patch.
- `apply-ci-fix` and `.github/scripts/pr-unblock/apply-ci-fix.mjs`.

- **Breaking:** `limits.admission-window-hours` is gone from the schema, so a `pr-pipeline.yaml`
  that still sets it fails validation; delete the key. `admission-window.mjs` is removed with it.

### Fixed

- pr-verify's verdict upload checks the summary and notes against every shared credential pattern (`findSecret` in `lib/publish-gate.mjs`: GitHub, AWS, private keys and the rest), not only Anthropic key shapes, and the error names the matched kind.

- The issue lane's `run-checks` job keeps the base's check scripts but restores the lane branch's own `scripts/` data files (`.txt`, `.json`, `.jsonl`), so a check reads the lists the branch changed, such as a new plugin in `scripts/fragment-plugins.txt`, the same as the pull request's CI.

- `check-signed-commits` reports a pull request it could not check (its head never matched its branch, or its commits could not all be listed) as "could not verify the lane's commits" in its log and escalation comment, instead of "unverified commits" with no commit named. It still fails closed.

- work-unblock's hourly sweep relabels a red-main fix issue that post-merge-demotion-alert.yml
  reopened on a repeat failure, so work-resolve-issue starts on it. The reopen keeps `agent-ready`
  but runs on that workflow's `GITHUB_TOKEN`, which starts no run. The sweep matches the issue's
  `<!-- post-merge-fix check=... -->` first line and the workflow's recurrence comment, both
  `github-actions[bot]`'s, logs how many match, and has the lanes App post a record naming that
  comment, then remove and re-add `agent-ready`: once per recurrence comment, inside the
  five-a-run cap, and only when a listed human or the App added its newest `agent-ready`; never on
  an issue that is held, has an open lane PR or a lane run in flight,
  or had `agent-ready` added since the reopen.

- An `agent-ready` issue the issue lane skips on its dimensions (`split-required`, `research-first`, `probe-first`, `not-assessed`) no longer ends the run green and silent: work-resolve-issue.yml's `report-skip` job runs `report-outcome` with the new `dimension-skip` input, which labels the issue `needs-human`, removes `agent-ready`, and comments the next step (`/work-items:decompose`, research, a probe, or setting the fields) with no model run. A later run still resumes the branch an earlier turn-cap or stopped run left ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).

- A red full run pr-merge.yml starts after a merge now reaches post-merge-demotion-alert.yml, so its
  record, fix issues and red-main report follow the merge instead of waiting for the next scheduled
  run. The run uses `GITHUB_TOKEN` and raises no `workflow_run` event, so pr-merge's
  `dispatch-full-run` job sends its run id through `workflow_dispatch`. Red is every conclusion
  `babysit_postmerge.py` counts as failed (`failure`, `timed_out`, `cancelled`, `startup_failure`,
  `action_required`), so a run cancelled on a time-budget overrun files its record and fix issues
  too; the red-main report still takes only `failure`. The alert takes the id only from
  `github-actions[bot]` or a listed human, never the lanes App, and only for attempt 1 of a red
  `pr-require-checks.yml` run on this repository's `main` that `github-actions[bot]` dispatched.
  pr-merge re-runs such a run only inside a lane merge's attribution window, so the alert waits up
  to `red-main.confirm-wait-minutes` for a re-run and starts none of its own. A dispatched red,
  whether its re-run failed or never finished, files nothing once a newer `pr-require-checks` run on
  this repository's `main` has succeeded: `main` already recovered, and the alert logs so and files
  no record, fix issue or report. The dispatch also sends the run's head SHA, which the alert
  checks against the run and keys its concurrency group on, so every sighting of one signal and
  SHA runs one at a time.

- `check-signed-commits` waits up to 60 s, backing off 5, 10, 20 and 25 s, for the pull request's head to match its branch before it gives up, instead of 8 s, since GitHub's pulls API can lag a push by minutes.
- `report-check-run` posts "The lane's commits could not be verified." when the signed-commit check failed without naming an unverified commit, and keeps "not GitHub-verified" for a named one. It takes the check's `unverified` output as a new input.

- A run record whose id is a boolean no longer stands for run 1.

- check-wip-cap keeps the last known WIP and held-cap pause when the open listing or the base
  config cannot be read, instead of failing open. work-unblock's hourly sweep saves the
  status to the Actions cache; work-resolve-issue's pick-slot only restores it
  (`cache-mode: read`). With no saved state the check still fails open. A kept pause logs
  `admission paused: reason=<reason> (read-error, kept last state)`, and the status gains
  `pause_basis` (`read`, `last-state` or `fail-open`).

- `check-trusted-trigger` re-reads a `workflow_dispatch` PR until `GET /pulls` shows the head its branch ref points at, waiting 5, 10, 20 and 25 s (60 s in all), so a job after pr-unblock's model job gates the head that job just pushed instead of the one `/pulls` still reports. When the two never agree, or the branch ref is missing, the lane stops with the new reason `head-lag` instead of gating a stale head, and `report-check-run` posts it as a `superseded-sha` skip, since the push that moved the branch is gated by its own run; a fork is not waited on. `check-signed-commits` now uses the same read from `check-trusted-trigger`.

- review-dependency dispatches again. dependency-dispatch matched Dependabot by the login
  `dependabot[bot]`, but the GraphQL listing names the Bot `dependabot`, so every Dependabot pull
  request was dropped and no dependency review ever ran. It now matches the Bot account id
  (49699333).
- A review-dependency `fix` lands only when its commits change npm (`package.json`,
  `package-lock.json`, `npm-shrinkwrap.json`) or pip (`requirements*.txt`/`.in`) manifest and lock
  files outside `.github/`, in a directory `.github/dependabot.yml` lists for that ecosystem. The
  promote step checks every changed path against the base's `dependency-classify.mjs` (copied
  with its SHA-256 before any model turn) and leaves any other fix
  off the branch, which the verdict job escalates as `dependency-fix-not-landed`; the verdict
  job checks the same rule on what landed, and the `dependency-review` patch row allows only the
  new `dependency-manifests` predicate.
- A `merge` verdict on a Dependabot pull request that changes a workflow or action file posts no
  merge marker and escalates the new `dependency-workflow-held`, so a person merges it.
- A lanes App commit on a Dependabot pull request must be a version change. The promote step,
  the verdict job's `fix` and `merge` paths, and the pr-merge lane refuse a fix file that is not
  modified in place, not a regular `100644` file (a symbolic link, submodule or executable), or
  whose content changes more than a version: in `package.json` only existing dependency entries'
  plain, bounded semver ranges may change; a lock keeps the Dependabot commit's package keys, and
  each entry resolves to exactly its own `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`
  with a `sha512-` integrity, the same alias `name` as before, and no install-script change; and requirements lines may add only
  `name==version` pins of projects the fix also unpins, with `--hash=sha256:` continuations. The
  repository's version-bump commit is admitted only when its `plugin.json` changes nothing but
  `version`. The verdict job's `merge` path now checks every commit that
  is not Dependabot's own (matched by account id, web-flow and a valid signature), reads the
  `[ecosystem, directory]` pairs from the base's `.github/dependabot.yml` itself, and requires
  run.json to name the head the model job's gate passed. A refusal escalates the new
  `dependency-fix-refused`.

## [2.20.4] - 2026-10-20

### Fixed

- The lost-run reconciler lists pr-verify runs once per lost conclusion and per not-yet-completed status instead of all runs of the day, so a day with more than 500 runs no longer fails the page cap.

## [2.20.3] - 2026-10-20

### Fixed

- `check-trusted-trigger` matches the re-runner by account id on every path instead of by login: it reads this run's own record (`GET /actions/runs/{run_id}`) and checks `triggering_actor.id` against the trusted-actor list, so a released login re-registered by someone else no longer passes. A failed or malformed read, or a record for another run or attempt, stops with `untrusted-rerunner`. The App-label re-runner must still be the listed lanes App or a listed human. `pr-unblock-dispatch.yml` now passes the job token to the gate so it can read its run.

## [2.20.2] - 2026-10-20

### Fixed

- The lost-run reconciler pages through a day of pr-verify runs instead of failing when there are more than 100, says how many listings failed instead of "nothing lost", and explains an exit 1 in the act step.

## [2.20.1] - 2026-10-20

### Fixed

- The finding-closure paragraph states that a finding any review of a head reported, whole or incremental, clears only by a new head (a fix) or a human resolution: each head on the covering chain counts the summary and thread-less inline findings any review of it reported, and a later clean review of the same head never clears one ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- The code review, security review and intake triage callers now honor the lane kill switches. A `kill-switch` job ahead of each reusable call runs `check-kill-switch` on `CLAUDE_LANES_DISABLED` and `CLAUDE_LANES_REPO_DISABLED`, which fail closed, and the call runs only when it says proceed. The code review lane also stops when `CLAUDE_REVIEW_DISABLED` is `true`, and the security review lane when `CLAUDE_SECURITY_REVIEW_DISABLED` is `true`. Intake has no switch of its own. The pinned ci-workflows reusables still read none of these variables.

## [2.20.0] - 2026-10-20

### Added

- address-feedback: a fix request by a trusted person with write access may name files to add to
  its thread's scope. The select step reads each file-shaped word of the request outside fenced
  code and quoted lines, from the repository root when it holds a `/` and from the thread path's
  directory when it does not, and records it in the thread's `named_paths` when it is in the same
  `plugins/<p>/` directory as the thread's path, in normal form, not under `.github/`, not an
  instruction path, and a regular file at the gated head (ten per thread at most). The promote
  step and the reply job accept changes to those files.

### Fixed

- A plugin's `.mcp.json`, `.gitmodules` or `CODEOWNERS` is no longer in the plugin-wide part of a
  kept thread's scope.
- The instruction paths `apply-ci-fix` and address-feedback refuse now also cover a `hooks`,
  `.claude` or `.claude-plugin` segment with nothing after it, a plugin's `monitors/` and `bin/`,
  and `.lsp.json`; a thread's plugin-wide scope also refuses `.bash`, `.zsh`, `.ps1`, `.cjs`,
  `.mts` and `.cts` files and any path with a character outside ASCII letters, digits and `_@+.-`.
- The address-feedback promote step moves the PR branch only when every path the lane branch
  adds or changes is a regular file at its tip, not a symbolic link or gitlink.

## [2.19.5] - 2026-10-20

### Fixed

- work-resolve-issue's `post-statuses.mjs` posts a resumed branch's `pipeline/*` statuses only while the branch ref still points at the tip run-checks checked; a branch that moved, or whose ref cannot be read, gets no status, as report-outcome already treats those check results.

## [2.19.4] - 2026-10-20

### Fixed

- The Unattended merge section documents that pr-merge refuses, as `shared-copy-sources-changed:`, a pull request carrying a shared-library canonical that main changed since its merge base, escalates it with the human-gated role label and a `babysit-merge-shared-copy-escalation` comment, and that the fix is merging main and running `scripts/sync-shared-copies.sh`. The head-moved clear removes that label once the head moves ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.19.3] - 2026-10-20

### Fixed

- The review-threads round records the SHA-256 of the thread file before the model runs, and the branch move and the reply collection read the file only when it still matches; otherwise the PR branch is not moved and no replies are collected ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- pr-merge's `gate-check` job writes a `pr-merge / gate` check only at a candidate's current pull request head: its read also fetches each pull request's head, and a row whose head differs, or whose pull request the read reports `NOT_FOUND`, is skipped with a logged reason instead of taking its commit from the summary artifact alone. A missing pull request skips only its own row; any other GraphQL error still leaves the read's candidates unwritten. The job gains `pull-requests: read` for that read.

- pr-merge counts the cap of two whole reviews per lane pull request from the lane identity's conversions to draft on the pull request timeline as well as from the reasons comment's record lines, so editing that comment, which the lane token can do, no longer resets the cap. An unread timeline requests no whole review.

## [2.19.2] - 2026-10-20

### Changed

- Write lanes deny the shell commands that can print a file or the environment (`echo`, `printf`, `cat`, `head`, `tail`, `grep`, `find`, `env`, `printenv`, `strings`, `od`, `xxd`, `diff`, `sed`, `awk`, `sort`, `cut`, `tr`, `base64`, `nl`, `tac`, `rev`, `uniq`, `fold`, `column`, `jq`, `xargs`, `more`, `less`) and `Read` of `/proc`; the skill reads files with `Read`, `Grep` and `Glob`. `resolve-issue` fetches only the Claude Code, Claude platform, GitHub, Node.js and Python docs hosts, and no longer runs `scripts/run-test-file.sh` or `check-skill.sh`; the pull request's CI runs the tests ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

## [2.19.1] - 2026-10-20

### Fixed

- pr-merge holds a stale-input pull request at its old head when the `update-branch` call gets no answer (a timeout, no HTTP status, or a server error), since the update may have landed; only a 4xx refusal enqueues as before. `merge.check-inputs` reads only a clone that is neither shallow nor partial ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.19.0] - 2026-10-20

### Added

- pr-merge requests a whole review of a lane pull request held only by findings an incremental review cannot clear: it records the request in the reasons comment, then converts the pull request to a draft and marks it ready, once per head, at most twice per pull request and once per run, only while fewer than 35 jobs run or wait and both tokens have 30% of each rate-limit bucket left ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.18.0] - 2026-10-20

### Changed

- pr-verify runs its model on the automations API key first and on the subscription token only after a key credit stop or when no key is set, as two jobs on run-claude-cli v0.54.0. A permission denial in either job yields no verdict. A key credit stop warns that the automations key needs rotating and leaves one lane record: the subscription job's, named for the stop, or the key job's as rate-limit when a denial on the key leg ends the run. Every ci-workflows action is pinned to v0.54.0.

## [2.17.1] - 2026-10-20

### Fixed

- A resumed `work-resolve-issue` run that reports done with no commit of its own now opens its PR from the branch it resumed instead of stopping for a person. `run-checks` runs the activity's checks over that whole branch, and `report-outcome` opens the PR only when at least one check ran and none failed, the branch is still at the tip checked (the compare and the new PR use that SHA), `lane.json`'s `resume` equals the branch the run resumed, and every commit on it ahead of the default branch is the lanes App's. The PR body's Verification section records this, and the run's `pipeline/*` statuses go on that checked tip; otherwise the run still hands back.

## [2.17.0] - 2026-10-20

### Added

- `intake-reenter.yml` sends an answered issue back to intake: a listed human's `**Decision recorded.**` comment on a `status: needs-decision` issue, or the author's or a listed human's reply on a `status: needs-info` issue, removes the status label, adds `needs-triage` and, for an issue from a listed human or the lanes App, dispatches `intake-triage.yml` once. It never adds `agent-ready`. A dispatched intake run no longer skips a born-triaged issue ([README.md, Stages](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#stages)).

- The monitoring lane (`maintenance-monitor-signals.yml`, "The monitoring lane"): an hourly scripted job on the job token that reads eight factory signals and keeps one deduplicated issue per signal and key.

### Changed

- The finding-closure paragraph states the rule pr-merge applies: a clean whole review of the current head in the thread's own lane closes a resolved thread whoever resolved it, so a HIGH security finding needs the security lane's own clean whole review, and an incremental review never closes an unchanged thread.

## [2.16.0] - 2026-10-20

### Added

- `merge.dependabot.majors` (`hold` or `review`, default `hold`) decides a Dependabot pull request
  with a major update, or with an update whose version cannot be read (a SHA pin), marked
  `<name>(unreadable)`, or whose title and commit metadata disagree, marked `<name>(disagree)`.
  Under `hold` the pr-merge lane refuses it with the reason `dependabot-major-held:<names>`
  whatever the review verdict says, and escalates it once: a marked comment whose first line is the
  `<!-- work-items:escalation lane=pr-merge kind=escalated -->` marker, so
  `/work-items:attend-queue` lists it, then the tracker's human-gated role label. `review` keeps the
  earlier behavior, where the lanes App's `verdict=merge` marker merges it. This repository sets
  `hold`. Non-major tiers and the publisher rule are unchanged. `version` stays 2.

- A skill leaf's optional `self-checks`: repository check scripts with fixed flags, the same shape as
  `checks`, that the skill runs and fixes before it commits through the same wrapper. They are
  advisory: unlike `checks`, the issue lane's run-checks job never reruns them, so a failure the
  skill cannot fix still opens the PR and is named in its report. `work-resolve-issue`
  `resolve-issue` lists `scripts/check-affected.sh --uncommitted`, which checks the work tree as
  the commit the API would make, with untracked files and file modes included, and leaves the
  checkout's HEAD and index as they were. `version` stays 2.

- New config: `merge.max-queue-ejections` (default 2, 1 to 20). The unattended merge gate refuses to
  enqueue a head the merge queue has removed that many times for failed checks since the head last
  changed (a pushed commit or a force push), and posts one marked comment naming the failing
  `merge_group` runs; an unreadable timeline, or 20 items with no head change, also refuses.
  `version` stays 2.

- `funding`, a map from Claude lane id to its funding role (`reviews`, `automations` or
  `issue-lane`), whose `<ROLE>_CLAUDE_API_KEY` and `<ROLE>_CLAUDE_CODE_OAUTH_TOKEN` secrets a lane
  on ci-workflows' run-claude-cli action passes; intake is the first, and the other entries name
  the role each lane takes when it moves ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  `version` stays 2.

- `limits.admission-window-hours` (default 24): the hours of issue-lane admissions the admitted
  backlog (open issues labeled `agent-ready`) may hold before new `agent-ready` labels pause. This
  repository sets 24.
- `limits.admission-factor` (default 0.8, greater than 0 and at most 1): the share of the lane's
  hourly merge rate admitted per hour.
- `.github/scripts/work-resolve-issue/admission-window.mjs` reports whether admissions are open
  from live counts and exits 0 open, 1 held, 2 on error.

- `merge.diff-check.floor-paths` (a list of globs) adds paths to the risk scorer's HIGH path floor
  while `high-path-floor` applies; a pull request touching one waits for a human, where a denied
  path makes it ineligible. With the floor, a changed SKILL.md, agents/**/*.md or commands/**/*.md
  file is compared by its base and head text, each read once: it scores HIGH when its frontmatter
  gains or changes `hooks`, `allowed-tools`, `tools`, `permissionMode`, `mcpServers`, `memory` or
  another capability key `babysit_risk.py` lists, when it adds or changes a `!` backtick command or
  gains a ```` ```! ```` block, when a changed line falls inside a ```` ```! ```` block, or when
  either side or changed frontmatter cannot be read. `merge.diff-check.floor-script-scopes` (a list
  of globs) holds a `.ps1` or `.cjs` file, or one with git mode 100755, inside one of them or at the
  top level the same way. This repository lists `bin/`, `.lsp.json`, `settings*.json` and the
  scripts of the plugins the CI lanes load as floor paths, with the directories of the scripts a
  SessionStart or PreToolUse hook runs by path outside its plugin's `hooks/` (`pydeps.py`,
  `arm_observer.py`, `destructive_guard.py`), held whole so a sibling module cannot shadow an import, and those plugins as script scopes
  (Q646), and sets `high-path-floor: true` (owner decision 2026-10-18, reversing Q661), so its
  pr-merge lane holds such a pull request for a human, and the scorer's fixed HIGH floor
  (`.github/**`, `docs/conventions/**`, agent instructions, hooks, `lib/`, `scripts/`, package
  manifests and more) now applies there too. The switch governs both lanes: in the local babysit
  lane, false leaves out `floor-paths`, `floor-script-scopes`, the capability check and the new
  fixed floor entries (`plugins/*/monitors/**`, `plugins/*/workflows/**`), so a local-lane pull
  request scores as it did before this release. `version` stays 2.

- A new optional `wip` block derives the issue lane's WIP cap from the lane merge rate: merged
  lanes-App pull requests per hour over `merge-rate-window-hours` (24) times
  `target-lead-time-hours` (2), rounded up, at least `min-cap` (default 1; this repository sets
  12, the earlier fixed cap); `limits.wip-cap` applies only when the merged count cannot be read.
  Held lane pull requests (`needs-human`, `do-not-merge`, or a body line exactly `Hold: a human
  merges this`) no longer count against it and form their own buffer, `held-cap` (60), with an
  alarm past `held-alarm-hours` (24). Lane PRs opened in the window may be at most
  `opened-to-merged-ratio` (0.8) of those merged. Over a cap the check alerts, and pauses the lane
  only on or after `pause-from` (empty: never). The check publishes its status as the `wip` step
  output, the step summary and its log line (README, WIP cap). `version` stays 2.

- New config: `merge.gate-budget-minutes` (a whole number of minutes; absent is no budget). The
  pr-merge workflow's gate loop starts no further candidate once it has run that long, and the
  candidate in progress finishes first, so the budget never stops a gate between its check and its
  merge-queue write. Each run starts after the last candidate the previous loop reached, read from
  the `pr-merge-gate-cursor` artifact of a scheduled or hand-started `pr-merge.yml` run on the
  default branch, and wraps
  round to the lowest PR number, so every candidate is reached across runs. This repository sets
  10, and the merge job's timeout returns from 55 to 30 minutes as a ceiling above it. `version`
  stays 2.

- `models.issue-dimensions` budgets a run on an issue from its Size, Complexity and Uncertainty
  org issue fields, read by field and option id: turn cap = the size's `base-turns` times the
  complexity factor, rounded up, and the size's `timeout-minutes`. A field with no value, or whose
  latest setter is neither a listed human nor the lanes App, is not assessed, and an unmapped
  option fails the resolve (`unmapped-dimension`). New skip reasons, before any model turn:
  `not-assessed`, `research-first` and `probe-first` (Uncertainty Knowable and Unknown) and
  `split-required` (Size Large). This repository sets `small` (75 base turns, 50 minutes),
  `medium` (150, 100), `large` (`split`), and complexity factors 1, 1.5 and 2.
  work-resolve-issue.yml reads the fields (`issues: read`) and the timeout before its run job
  starts and passes the new `issue-dimensions` input on, so a field set while the run waits
  cannot outgrow the timeout, which is 25 minutes without `issue-dimensions`. No lane reads a
  `size:` label. A run that reaches its turn cap with no outcome of its own now leaves a
  `turn-cap` marker naming the cap and the branch, and the `pipeline/resolve-issue` status says so.
  `limits.turn-cap-restarts` (0 to 5, default 0) is how many times work-unblock restarts such an
  issue since a listed human last added `agent-ready`; past it the issue goes to a person, and this
  repository sets 0. The next run after a `turn-cap`, `stopped` or `limited` marker resumes from
  that run's lane branch when every commit on it ahead of the default branch is the lanes App's
  verified commit, and `issue.json` gains `resume`; a resumed run that reports `done` with no commit
  of its own opens no PR: the runner checks only the run's own branch, so it goes to a person naming
  the resumed branch. A run that exits non-zero on a funding stop
  (`api_error_status` 400 with "regain access on <date>", or 401) leaves a `funding` marker, keeps
  `agent-ready`, counts toward `limits.limit-stops-per-issue` (not `turn-cap-restarts`), and work-unblock restarts it after
  the date; `lane.json` gains `failed`, `api-error-status` and `error-text`
  ([README, Models](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#models); [pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
  `version` stays 2.

- `resolve-config` outputs `model` and `effort` for run-claude-cli callers: `model` is empty for a
  `default` model, which the launcher cannot pass, and `effort` is empty when the profile sets
  none.

- On its schedule, `pr-merge` takes off a `needs-human` label the lanes App set for a pr-unblock
  escalation once every reason it recorded since adding the label no longer holds at the head: `workflow-staged` when main
  changes nothing under `.github/workflows/` since its merge base with the head, `unresolved-conflict`
  and `protected-path-conflict` when GitHub reports the PR mergeable, `feedback-protected-path` when
  the PR changes nothing under `.github/`. It posts one comment naming the reason and the head first,
  never touches a label a person added, and keeps the label once any account but the lanes App
  commented or reviewed since it went on. At most five a run. `version` stays 2.

- The pr-merge workflow's merge job uploads each sweep's verdicts as the `pr-merge-summary` artifact
  (30-day retention): the run, the candidate, enqueued, merged and held counts, refusal counts by
  reason with PR numbers and run lists stripped so they aggregate, any gate-budget stop, and the
  per-candidate results. It also logs one `refusal-counts=` line built from that data, so a log
  search finds it once.

- `merge.skip-unchanged` (`max-minutes`, default 60; `max-skips`, default 3): the pr-merge workflow
  reports a candidate the last gating run refused on unchanged inputs with that refusal, marked
  `carried`, instead of gating it again, until the refusal is `max-minutes` old or has been skipped
  `max-skips` runs in a row. `0` in either turns it off. The `sweep-cost=` line gains `skipped=`, and the
  `pr-merge-summary` artifact gains `skipped`: its `candidates` stays the listed count and
  `budget_stop` counts only gated candidates as reached.

- A skill leaf's `applied-by` names what it hands on, keyed by artifact (`patch`,
  `feedback-replies`, `dependency-verdict`, `work-outcome`), and the script activity that applies
  each. Only a skill with effect `read` and gating `advisory` sets it. The config reader rejects
  (`invalid-applied-by`) a target that is not a script activity, a `patch` target without
  `prepare: apply-patch`, and a lane that holds the producer without the target in a slot that
  needs it. `resolve-config` emits the map in the resolved activity and takes an
  `applied-by-supported` input, which `pr-run-activity-read.yml` passes as `patch`. A `read` skill
  whose `applied-by` sets `patch` gets the edit tools of a write skill, commits nothing, and is not
  asked to fix instruction surfaces or CODEOWNERS paths. No activity in this repository sets it
  yet ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#activities)).
- `.github/actions/resolve-config/patch-rules.json`, with its schema, registers what an apply-patch
  script is to admit from each producer's patch: one row per prepare mode, plus `default` and `issue`.
  Every row refuses `.github/**`, `.claude/**`, the root `.mcp.json`, `.gitmodules`,
  `**/settings*.json`, symbolic links, gitlinks, a new executable bit and a rename into any of
  those; a row without that set, or a two-parent commit whose `allow` is not exactly `[merge-result]`, is rejected.
  `resolve-config` checks the registry before every lane resolve and fails closed without it; the
  lanes token broker does not read it
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).

- `.github/scripts/apply-patch/apply-patch.mjs`, the one script that applies a read model job's
  patch to a pull request branch, driven by the
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  row of the producer's prepare mode (`default` when it has none), read from the trusted base
  checkout. It refuses the whole patch on any change under `.github/` (any case, any `..` segment)
  or `.claude/`, to the root `.mcp.json`, `.gitmodules` or a `settings*.json`, on a symbolic link,
  gitlink or new executable bit, on a rename into any of those, on a path holding a backslash, on more paths than the row's
  `max-files`, on a path its allow predicates refuse, and on an Anthropic API key, OAuth token or
  GitHub token shape in the patch or a patched blob. A row without the universal refusals, or with
  an unknown predicate, throws before any write. A head that moved since the model job takes the
  patch with `git apply --3way` only when the moved commits touch no patched path, else it skips
  `superseded-sha`. The commit goes through the Git Data API with one blob per changed file plus a
  tree, a commit and a ref update. No workflow runs it yet
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).

- The pr-merge workflow shows each candidate's verdict on its head as one `pr-merge / gate` check
  run: neutral and titled with the top refusal, with the blockers in the summary, or success once
  enqueued or merged over a refusal already on show. One GraphQL read per 50 candidates, and a write
  only where the title or conclusion changed. A new `gate-check` job writes it with its own
  `GITHUB_TOKEN` and is the only job holding `checks: write`; the merge job keeps `checks: read`.
  The check is never required and is not part of `ci-status`.

- `merge.check-inputs`: git pathspecs the pull request checks read. When main changed one since a
  pull request's merge base, the pr-merge lane updates the pull request from main instead of
  enqueuing it. The default lists the shared-copy registry (`scripts/shared-copies.txt`) and the
  docs-only allowlist (`scripts/docs-only-paths.txt`); the registry counts only for a pull request
  that touches a path it registers.

- `pr-merge` also takes off a `needs-human` label the lanes App set for one of its own escalations
  once the head has moved: when the marked App comment written last before the label is pr-merge's
  and came within a minute of it, and the newest App comment carrying each of
  `<!-- babysit-merge-verify-escalation -->` and `<!-- babysit-merge-risk -->` names, in its
  ``at head `<sha>` ``, a head other than the current one, it posts one comment naming
  `head-moved`, the old head and the new one, then removes the label so pr-merge judges the new head
  and escalates again if its refusal still holds. A head that does not parse as 40-hex, any other
  marker (another lane's escalation just before the label included), a label a person added, or a
  person speaking since the label keeps it.

### Changed

- A pull request that changes this convention adds a changelog fragment under `.changes/pr-pipeline/`
  (`scripts/new-changelog-fragment.sh pr-pipeline <bump>`) instead of a `CHANGELOG.md` entry, and the
  release pull request writes the fragments into one entry, so concurrent lane pull requests stop
  conflicting on this file. `version` stays 2.

- The checks copy also carries the base's `.shellcheckrc`, `.markdownlint-cli2.jsonc` and
  `.github/requirements-ci.txt`, which `check-affected.sh` and `run-ruff.sh` read. A check's
  wrapper unsets `GH_TOKEN` and `GITHUB_TOKEN` and pins git config the way a verify-script's wrapper
  does. A skill with checks is told to fix what a check reports in the working tree and to name
  anything it could not fix in its report; a skill that commits is told to run the checks, fix,
  and run them again before it commits.

- The pr-merge workflow's merge job logs its API budget through the shared `log-api-budget` action,
  for the lane token and the job's own token, at mint and at job end, so the reading also lands on a
  run that times out. A `sweep-cost=` line (both tokens' spend since mint, candidates listed,
  candidates reached) goes to the log and the step summary. The action gains a `costs` output.
- The merge job keeps the verdict reads that never change (FAIL run records of pr-verify origin,
  FAIL head refs by artifact id, run heads found on main) across runs with `actions/cache`, under a
  new key per run, restored by prefix. The restored entry is untrusted: each kept read lands in a
  `carried-*` section the reader uses only to count a FAIL; everything else is dropped
  (`.github/scripts/pr-merge/carry-run-cache.mjs`).

- The PR pipeline convention says that after main changes a lane workflow, a lane run is
  re-triggered with a fresh event, not `gh run rerun`, which the token broker denies as
  `workflow-modified`.

- `pr-verify.yml` judges on ci-workflows' run-claude-cli action as the `automations` role, so its
  runs spend `AUTOMATIONS_CLAUDE_API_KEY` credits first and fall back to
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` after a credit stop
  ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  The model reads its data files from `pr-verify-data` in the working directory with Read alone,
  every other path and tool denied. No verdict is written when any leg hit a permission denial,
  or when the summary or notes hold text shaped like an Anthropic key or OAuth token, and a run
  that leaves no verdict fails. The
  artifact name and verdict JSON are unchanged. `version` stays 2.

- `address-feedback` now also works a review thread the lanes App never commented on when a
  trusted person with write or admin permission replies to the reviewer bot's finding with a fix
  request (`PR-fix lane: please fix this finding`); every other comment must still be the reviewer
  bot's or a trusted person's. The select step, the reply job's re-read and
  `pr-feedback-dispatch.yml` judge threads the same way
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
  A fix request posted after the head's review starts the round when an account on the trusted-actor list runs
  `gh workflow run pr-unblock.yml -R melodic-software/claude-code-plugins -f pr-number=<n> -f activity=address-feedback`.
  `version` stays 2.

- `pr-run-activity-write.yml` takes a required `role` input, the funding role whose OAuth token the
  caller passes, and the lane record names that role's token (`<ROLE>_CLAUDE_CODE_OAUTH_TOKEN`) as
  the run's credential instead of always `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`.
  `work-resolve-issue` passes `issue-lane` and its own `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`;
  `pr-refine` and `pr-unblock` pass `automations`.

- `verify:fail` joins the verifier refusals that need a human: while `merge.report-only` is false the pr-merge lane escalates it with the `<!-- babysit-merge-verify-escalation -->` comment, which for `verify:fail` quotes the head `fail` verdict's `summary` as data, and the human-gated role label, so a refused pull request leaves the lane WIP count.

- At the address-feedback round cap (`loop.review-rounds`), a kept thread with a fix request
  from a write-access trusted person created after the newest counted round (its latest round
  marker or model check-run completion) runs one more round, on the requested threads only; other
  kept threads wait, and without such a request the PR still escalates `feedback-round-cap`. A
  round with no readable time grants none
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- `pr-merge` now keeps a lanes-App `needs-human` label only when a person commented, reviewed, or
  left a review or commit comment since it went on. A comment or review by a bot account (an AI
  review, another lane) no longer blocks the clear. An App comment carrying any marker other than
  pr-unblock's escalation still keeps the label.

- `checks`, `self-checks`, `verify-scripts` and `web-access` turned on need a skill whose runner
  stages edit tools: an effect other than `read`, or `applied-by.patch` without
  `prepare: ci-context`. Before, they needed an effect other than `read` and `checks` had no
  rule. `web-access` still requires `reads-untrusted: true`. `version` stays 2.

- A `verify:fail` escalation whose verdict record cannot be read, or a `verify:earlier-fail`, quotes
  the last fail summary the lane's comment carried, under the head it was given at.

- The work-resolve-issue lane's `report-outcome` no longer writes `Hold: a human merges this` on a `Refs:` pull request, and it holds a diff at the compare-listing cap only while `merge.diff-check.denied-paths` lists a path. A trusted `merge: human` label, structural or untrusted-provenance work, a denied-path match and an unreadable denied-path list still hold the pull request.

- A pr-merge `risk:MED` or `risk:HIGH` refusal whose reasons comment has stood unchanged at the head for `merge.risk-escalation-minutes` (new setting, 60) now gets its comment rewritten once to say the refusal persisted and needs a person, then the human-gated role label (the rewrite dates the comment beside the label, so the head-moved clear pairs them), while `merge.report-only` is false, so the pull request leaves the lane WIP count. A LOW score at that head first marks the comment cleared, so the time restarts with the next refusal. The README no longer says only a human removes that label: the `head-moved` clear does once the head moves. The README records the owner's finding-closure decision for #8450 and that the gate does not apply it yet (#8478).

### Removed

- The `funding` map. No workflow read it: each lane's workflow names its funding role as a literal
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).

### Fixed

- A write lane `pull_request` run on a PR that changes a workflow file the token broker compares no
  longer fails red. When the broker refuses the mint as `workflow-modified` and GitHub's compare of
  the default branch with the gated head lists the named file, the run job ends green with no token,
  its summary names the reason and file, and the check is neutral with the new skip reason
  `workflow-modified`
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#a-workflow-file-the-pr-changes)).
  Every other denial, and a refusal of a file the PR does not change, stays red. `version` stays 2.

- `pr-run-activity-read.yml` takes the write file's `trusted-base` input and passes it to
  `check-trusted-base`, and pr-unblock's `fix-ci` job passes `trusted-base: default-tip`, as every
  other pr-unblock job does. A lane PR opened before `fix-ci` joined the config kept a base SHA
  whose config had no `fix-ci` slot, so every dispatched `fix-ci` run on it failed at "Resolve the
  config". `version` stays 2.

- pr-merge.yml's merge job now files the demotion record when its read-only post-merge check
  exits 1 (a failed lane merge: a canary or read-back failure, a missed dispatch deadline, or a red
  full run whose attempt 2 the agent identity did not start). It runs the check again with
  `--remediate` under the lanes App token, which files (or comments on, reopening) the record and
  dequeues the lane's merge-queue entries, so a human closing that record re-arms the lane. A full
  run this workflow dispatched with `GITHUB_TOKEN` raises no `workflow_run` event, so
  post-merge-demotion-alert.yml never files for it; when a human re-runs such a red run (run
  39200031682, red attempt 1, human attempt 2), the check reads it red and this step files the record.
  A red dispatched run that nobody re-runs still waits for its one re-run (exit 5) and files nothing;
  the lanes App cannot start that re-run.
- That step judges the remediation by its report, not its exit code: a missing report or a failed
  record filing or dequeue raises an error annotation, and only the expected refused re-run and
  dispatch attempts warn.
- post-merge-demotion-alert.yml also reads records the lanes App filed and treats a record of either
  filer that names the same failing run as this run's record, so one red run no longer gets two. Its
  record says the lane stays at rung off while any demotion record is open: fix main first, then close
  every open record.

- A red full run that pr-merge.yml dispatched now gets its one re-run without a person. The
  `post-merge-dispatch` job, which already holds `actions: write` under `GITHUB_TOKEN`, starts
  `rerun-failed-jobs` on attempt 1 of a red lane-dispatched run the post-merge check reports
  (`laneDispatched` in its `reruns`), one run per job. Once attempt 2 exists it uploads
  `pr-merge-rerun-<run id>-attempt-2`, which the post-merge check needs before it counts that
  attempt. Before this, such a run waited for a re-run the lanes App cannot start, every candidate
  was refused with exit 5, and no demotion record existed for a human to close until a person
  re-ran it. The lanes App gets no new permission. The re-run step runs only when the check
  could judge (exit 0, 1 or 5), after the full-run dispatch, and a failure in either leaves the
  other to run. Once the re-run starts, the step retries reading its attempt for about three
  minutes, and fails with an error rather than finishing quietly when it cannot confirm attempt 2.

- The held buffer only alerts: over `wip.held-cap` the WIP cap check writes its warning
  annotation and sets `held_over` and `alert`, but no longer pauses the lane. Only the WIP cap
  pauses it, on or after `pause-from` (README, WIP cap). Its warning over the held cap alone
  says only the WIP cap pauses the lane, instead of "pause-from not reached".

- `address-feedback` now works a thread a trusted person's fix request started even when the
  reviewer bot left the finding in a review of an earlier head than the one the reviewed-head
  markers name. Threads left by the reviewer bot alone, and threads the lane escalated, still need
  a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- The `log-api-budget` action no longer reports a token's cost as `window-rolled` when the reset
  time moved earlier within one window; it counts `used` at end minus `used` at start, and calls
  the window rolled only when `used` fell or the reset moved more than 10 minutes later.

- `address-feedback` now works a thread a trusted person answered after the lane escalated it even
  when the reviewer bot left the finding in a review of an earlier head than the one the
  reviewed-head markers name, as it already did for a fix request with no escalation. Threads left
  by the reviewer bot alone still need a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- `pr-unblock.yml` posts `pr-unblock / fix-ci` neutral `not-applicable` on the head when
  `fix-ci-context` skips (a closed pull request or no failing check). The skip posted no check,
  so `fix-ci-dispatch.mjs` sent the same lowest-numbered pull requests again on every run and
  starved every other red one.

- fix-ci now sees a failed check that a later skipped or neutral run of the same check hides, such as a contract-only run on a head whose `ci-status` stays red on the earlier failure; a later success still clears it.

- The merge-base lane (`pr-unblock` update-branch and resolve-conflicts) no longer escalates
  `workflow-staged` when the merge only brings in the default branch's own `.github/workflows/`
  files: `post.sh` lets the merge through when every staged workflow entry is the trusted base's
  (mode and blob), no head workflow is dropped, and the PR's own diff against every merge base
  touches no workflow. Every other case still escalates.

## 2.15.1 - 2026-10-18

`work-resolve-issue` no longer takes the model's word that its checks passed. A new `run-checks`
job, on a fresh runner after `resolve-issue`, runs each of the activity's `checks` from the default
branch tip's copy against a checkout of the lane branch whose `scripts/` is the base's, so
`scripts/fragment-plugins.txt` comes from the base and only the branch's own files, such as
`.changes/`, are checked. It hands the results (branch, tip, each check's exit status) to
`report-outcome` as a job output, never through the outcome artifact that code the model started
can rewrite, and only when `run-checks` succeeded. `report-outcome` lists those results under
Verification and stops a done run whose checks failed, are missing, or ran on a tip the branch has
since left, even when the outcome file's `not_done` is empty ([#7497](https://github.com/melodic-software/claude-code-plugins/issues/7497)).
`version` stays 2.

## 2.15.0 - 2026-10-18

`pr-unblock-dispatch.yml` starts pr-unblock's `fix-ci` for open lanes App pull requests whose
head's `ci-status` failed, from one GraphQL query per page with its `rateLimit.cost` logged, at
most `limits.fix-ci-per-run` per run and, on a head whose earlier runs all failed, at most
`limits.fix-ci-restarts` more times ([README](README.md#lanes)). Its job's concurrency group
now cancels a run in progress. `version` stays 2.

## 2.14.0 - 2026-10-18

`prepare` gains `ci-context`, the one mode for a `read` skill, and `apply-patch`, the one mode for
a script, a `mutate-branch` one. `pr-run-activity-read.yml` performs `ci-context`: it downloads a
base job's `ci-context-<attempt>` artifact, checks its SHA-256 and head, and gives the skill that
file plus Bash, Edit and Write; it takes `ci-context-attempt` and `ci-context-sha256` and gains a
`reply-attempt` output. `pr-run-activity-write.yml` performs `apply-patch` with the new
`patch-state`, `patch-sha256`, `patch-attempt`, `patch-head-sha`, `patch-activity` and
`reply-attempt` inputs ([pr-run-activity.md](pr-run-activity.md#prepare-apply-patch)). The
pr-unblock lane adds `fix-ci` and `apply-ci-fix`, which refuses the whole patch on a change to
`.github/**` or an agent instruction path (`CLAUDE.md`, `AGENTS.md`, `.claude/` or `.claude-plugin/`, a
plugin's `hooks/`, `.mcp.json`, `.gitmodules`, `CODEOWNERS`), and `report-escalation` takes six `ci-fix-*`
reasons. New config: `loop.fix-ci-rounds` (3), `limits.fix-ci-per-run` (2) and
`limits.fix-ci-restarts` (1). `version` stays 2.

## 2.13.0 - 2026-10-18

`pr-run-activity-read.yml` gains an `output-mode` input. The default, `clean-tree`, keeps failing a
run that leaves the tree changed. `patch` instead uploads what the activity changed against the
gated head as the artifact `patch-<lane>-<activity>-<run attempt>` (one `patch.diff`) and sets the
new `patch-state`, `patch-sha256` and `patch-attempt` outputs, beside a new `head-sha` output. An
empty change is `patch-state` `empty` and a success check titled `Passed: no changes`
([pr-run-activity.md](pr-run-activity.md#patch-output-mode)). `version` stays 2.

## 2.12.5 - 2026-10-18

The unattended merge gate reads `merge.max-in-flight` at the default branch head instead of at each
pull request's base, once per cache window; when the head's config cannot be read, the base's value
applies, and the post-enqueue room check keeps the lower of that and the cap the assessment applied. Every other `merge.` key is still read at the base.
`version` stays 2.

## 2.12.4 - 2026-10-18

`pr-run-activity-read.yml` takes a `dispatcher-run-id` input and passes it to its trigger gate with
`dispatcher-workflow: .github/workflows/pr-unblock-dispatch.yml` and
`dispatched-workflow: .github/workflows/pr-unblock.yml`, so a read activity that
`pr-unblock-dispatch.yml` sent to `pr-unblock.yml` runs; any other `github-actions[bot]` dispatch
still stops with `untrusted-actor`. With the id set, the skill step also admits `github-actions` in
`allowed_bots`. No caller passes it yet. `version` stays 2.

## 2.12.3 - 2026-10-18

`pr-unblock` `address-feedback` widens a kept thread's scope from its path alone to also a file in
the `plugins/<p>/` directory that path sits in, and a test file (`test_*.py`, `*_test.py`,
`*.test.*`, `*.spec.*`) in that path's directory
([#8109](https://github.com/melodic-software/claude-code-plugins/issues/8109)). The plugin-wide
part leaves out files the harness or a shell runs or loads as instructions: anything under
`hooks/`, `.claude-plugin/` or a `.claude/` directory, a `CLAUDE.md` or `AGENTS.md`, and any
`.sh`, `.py`, `.mjs`, `.js` or `.ts` file. The review-thread tool, the promote step and the reply
job apply the same rule; the promote step imports the base's `thread-scope.mjs` from a copy taken
before the head checkout, checked against its SHA-256. `.github/` stays refused. `version` stays 2.

## 2.12.2 - 2026-10-18

On a pull request labeled `needs-human` (the human-gated role label), `pr-unblock`
`address-feedback` works a thread when a person on the trusted-actor list with write or admin
permission asks for the fix: a line of their reply after the lane's escalation starts with
`PR-fix lane: please fix this finding`, in any case, outside a fenced block. Without one the
dispatcher starts nothing and the select step skips `awaiting-human`, so the pull request stays
held; with one the write runner lifts only the human-gated hold for that run
([pr-run-activity.md](pr-run-activity.md#prepare-review-threads)). Its `labels-absent` is
`[do-not-merge]`, `do-not-merge` still stops it, every other activity still waits on
`needs-human`, and `pr-merge` still refuses a `needs-human` pull request. `version` stays 2.

## 2.12.1 - 2026-10-18

A write-runner skill run that claude-code-action fails only because its `success` result went over
`--max-turns` now counts as a success: `act-outcome`, the verdict, the lane record and the job
result report success, so `pipeline/resolve-issue` posts `success` and report-outcome proceeds as on
any finished run. The run job reads this from the execution file's last result message (subtype
`success`, `is_error` false, `num_turns` over the cap); any other failure, or a missing or
unreadable execution file, still fails
([pr-run-activity.md](pr-run-activity.md#the-run-job)). `version` stays 2.

## 2.12.0 - 2026-10-18

`merge.max-in-flight` (an integer of at least 1, default 1) caps the lane merges in flight: the
agent identity's merge-queue entries plus its merged pull requests the post-merge check has not
verified. This repository sets 5. A red full run or canary run still charges every unverified
merge whose commit it contains. `version` stays 2.

## 2.11.10 - 2026-10-18

This repository's `limits.wip-cap` drops from 60 to 12, so `work-resolve-issue` starts no run, and
work-unblock re-fires none, while 12 or more lanes-App pull requests are open. The value is the
measured lane merge rate (about 1.5 per hour) times an 8-hour open-to-merge target. The schema
default (60) and its range (1 to 500) are unchanged. `version` stays 2.

## 2.11.8 - 2026-10-18

`pr-refine` no longer starts on `synchronize`: it runs when a PR opens, reopens or turns ready, or
on a `workflow_dispatch`, so an author push no longer draws a fix-docs commit and a fresh review
round. A docs change pushed after its first run waits for a reopen or a dispatch. When
`resolve-conflicts` escalates with `unresolved-conflict`, `pr-unblock.yml`'s scripted
`report-conflict-status` job posts a `failure` commit status with context `pr-unblock/conflict` on
that head, since GitHub runs no `pull_request` workflow on a conflicted PR. `version` stays 2.

## 2.11.7 - 2026-10-18

A `resolve-issue` run that waited in its slot while a change to `work-resolve-issue.yml` or
`pr-run-activity-write.yml` merged fails red `workflow-stale` before the token request, by the
broker's own blob comparison against main, instead of spending a mint the broker refuses as
`workflow-modified`. It leaves no outcome marker, so work-unblock's hourly sweep re-fires the issue
on main's files ([pr-run-activity.md](pr-run-activity.md#issue-mode)). `version` stays 2.

## 2.11.6 - 2026-10-18

An issue-lane run never dies on GitHub's rate limit or a pile of open lane pull requests.

- New `limits.wip-cap` (default 60, set in this repository's config). `work-resolve-issue`'s
  `pick-slot` job counts the lanes App's open pull requests with one search, through the new
  `check-wip-cap` action. At or over the cap, `resolve-issue` is skipped and takes no slot and no
  lane token. A failed count starts the run.
- work-unblock's hourly sweep re-fires a run that did no work: either its `Request the lane token`
  step failed (GitHub's rate limit past the 8-minute retry budget, among other causes) or the WIP
  cap skipped it. It waits `reset-clamp-min` hours after the run ended. The broker's `Retry-After`
  is at most an hour, so any rate-limit reset has passed by then. It acts only while fewer than
  `wip-cap` lane PRs are open, and stays within `restarts-per-run`.
- Such a re-fire is not limited to once per workflow version and is not a limit stop, so it never
  adds `needs-human`.

`version` stays 2.

## 2.11.4 - 2026-10-18

A write skill that commits through `commit_files` also gets `Bash(chmod +x *)`, and its commit
instruction says to run `chmod +x` on every new or changed file that starts with `#!` or ends in
`.sh` first: `commit_files` takes each file's mode from disk, and `Write` creates a file without
the executable bit, so lane PRs landed new scripts as `100644`
([pr-run-activity.md](pr-run-activity.md#skill-activities)). `prepare: merge-base` is unchanged:
the runner commits the staged index, whose modes the merge set. `version` stays 2.

## 2.11.3 - 2026-10-18

The verify-script wrapper for skill-quality's `check-skill.sh` runs it with `HOME` set to a fresh
`mktemp -d` directory and `CLAUDE_CONFIG_DIR` to that directory's `.claude`, so a skill test that
writes under `~/.claude` no longer fails on the runner's read-only one
([#8027](https://github.com/melodic-software/claude-code-plugins/issues/8027)). Other
verify-scripts keep the runner's `HOME`. `version` stays 2.

## 2.11.2 - 2026-10-18

The broker's `workflow-modified` refusal has one exception, for a lane's post-run report job
(`work-resolve-issue` `report-outcome`, `pr-unblock` `report-escalation`): it still mints when
every main commit that changed the workflow is signed, GitHub-made, on a linear range and landed
after run start, at most 50 minutes ago ([azure-iac#39](https://github.com/melodic-software/azure-iac/pull/39)).
The model step stays strict. `version` stays 2.

## 2.11.1 - 2026-10-18

The `resolve-issue` job passes `timeout-minutes: 25` to the write runner, down from 50, so a stuck
run frees its concurrency slot sooner. Of the 40 most recent successful runs the job took 3.5
minutes at the median, 10 at the 90th percentile and 15.4 at the maximum. `version` stays 2.

## 2.11.0 - 2026-10-18

[Changing this config](README.md#changing-this-config): a pull request that changes a lane and
lists a not-verified item that could stop the lane checks that item live before it merges. An item
only a merged run can exercise merges only once a tracked issue names the check and its owner; a
line in the pull request body does not count. `version` stays 2.

## 2.10.0 - 2026-10-18

`resolve-issue` lists `scripts/new-changelog-fragment.sh` as a `verify-script`, so the issue lane
can write a changelog fragment. The script now writes into the git work tree its caller stands
in (exit 2 outside one), not its own parent, refuses a plugin name with a path in it and a linked
`.changes` directory, and runs its own copy's `sync-shared-copies.sh` for `--carriers-of`, which
reads the checkout's registry. The verify-script prompt now says Bash runs only the named wrappers, each as its own command, that the
run inspects and changes files with Read, Grep, Glob, Edit and Write instead of `cd`, `;`, `&&`,
pipes or interpreter one-liners, and names the `git-mv-rm` wrapper for a rename or removal when
it is listed ([pr-run-activity.md](pr-run-activity.md#skill-activities)). `version` stays 2.

## 2.9.1 - 2026-10-18

`request-lane-token` also retries a broker 503 `github-rate-limited`, waiting exactly its
`Retry-After` plus up to 20 seconds of jitter, and fails red at once, naming the limit kind and its
reset time, when that wait would pass the 8-minute budget. A 503 `mint-unavailable` is never
retried, and its failure says it is final
([pr-run-activity.md](pr-run-activity.md#the-lane-token-broker)). `version` stays 2.

## 2.9.0 - 2026-10-17

`work-resolve-issue.yml` runs at most three `resolve-issue` jobs at once. A `pick-slot` job takes
the issue number modulo `SLOTS` (3, set in that job), and `resolve-issue` waits in the
`work-resolve-issue-slot-<n>` concurrency group with `queue: max`, so a burst of `agent-ready`
admissions queues instead of exhausting the lanes App's hourly API quota
([pr-run-activity.md, Issue mode](pr-run-activity.md#issue-mode)). The per-issue run group is
unchanged. `version` stays 2.

## 2.8.1 - 2026-10-17

`request-lane-token` retries a broker 503 whose reason is `github-unavailable`, with a fresh OIDC
token, after 60, 120 and 240 seconds plus up to 20 seconds of jitter, honoring a longer
`Retry-After` header and starting no retry more than 8 minutes after the first request. Every
other answer stays final ([pr-run-activity.md](pr-run-activity.md#the-lane-token-broker)).
`version` stays 2.

## 2.8.0 - 2026-10-17

An optional `limits` block sets the limit-stop restart values: `fallback-reset`,
`reset-clamp-min` and `reset-clamp-max` (hours), `restarts-per-run`, `limit-stops-per-head` and
`limit-stops-per-issue` ([README.md, Limits](README.md#limits)). Each defaults to the value the
lanes used before, and resolve-config emits all six. `version` stays 2.

## 2.7.0 - 2026-10-17

`resolve-issue` lists skill-quality's `check-skill.sh` and `check-evals-quality.sh` as
`verify-scripts`, so the issue lane can run the skill checks an issue's done-when names
([#7840](https://github.com/melodic-software/claude-code-plugins/issues/7840)). Every
verify-script wrapper now unsets `GH_TOKEN` and `GITHUB_TOKEN` before it runs the script, as
`scripts/run-test-file.sh` does for its test; code the script runs can still read the token from
an ancestor process's `/proc/<pid>/environ`. `check-skill.sh` runs each checked skill's
`scripts/*.test.sh` and the checkout's markdownlint: checkout code with the network open, the
power `run-test-file.sh` already gives the run ([pr-run-activity.md](pr-run-activity.md#skill-activities)).
`version` stays 2.

## 2.6.1 - 2026-10-17

`address-feedback.mjs select` now also keeps a thread the lane escalated (the lanes App's last
comment is an `INCORRECT`, `UNCERTAIN` or `VALID-defer` reply) when every comment after it is by a
human on the base's trusted-actor list, created after the escalation and edited by no one else.
Those replies are marked `direction: true` in the thread file. Before, every comment had to be the
reviewer bot's, so the lane never read a person's answer to its own escalation
([pr-run-activity.md](pr-run-activity.md)). `pr-feedback-dispatch.yml` judges a thread with the
same rule, so a review round that ends on a PR with such a thread dispatches address-feedback
([README.md](README.md)). `version` stays 2.

## 2.6.0 - 2026-10-17

A daily `maintenance` producer, the lane sweep ([README.md, The lane sweep](README.md#the-lane-sweep)):
a collect script, one read-only model leg per unit, and a file script that checks every quoted line
against main, de-duplicates by fingerprint, and files at most 5 `needs-triage` issues with the job's
own token. It labels nothing `agent-ready`. `version` stays 2.

## 2.5.0 - 2026-10-17

`scripts/run-test-file.sh` runs a `*.test.js` or `*.test.ts` file that imports `vitest` with the
package's locked vitest (`npx --no-install vitest run`, from the nearest `package.json` inside the
checkout), under the same checkout-path guard, after `npm ci --ignore-scripts` there when the
package has a `package-lock.json` and no `node_modules`. When it is a verify-script, the system prompt names
its wrapper as the test entry and says a compound `cd <dir>; <command>` is refused
([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). `version` stays 2.

## 2.4.0 - 2026-10-17

`models.routes` and `resolve-config`'s `model-route` take a fifth run route, `summarize-reuse`
([README.md, Models](README.md#models)); this repository maps it to a new `summary` profile
(`sonnet`, effort `medium`, 10 turns). When work-resolve-issue reuses a lane branch, the write
file's new summary job, which holds only `contents: read`, runs a read-only summary pass
([pr-run-activity.md, The summary job](pr-run-activity.md#the-summary-job)), and `report-outcome`
writes its summary and changes into the PR body when the summary names the issue, the branch and
its current tip. Every reuse PR lists the files the branch changes, denied paths marked, and
still carries the hold line. `version` stays 2.

## 2.3.0 - 2026-10-17

`pr-run-activity.md` run job steps 11 and 12 now copy the base's `scripts/setup-env.sh` before the
head checkout, then set up Python and run it before a skill activity, so the skill can run the
repository's Python and Node tests. `version` stays 2.

## 2.2.0 - 2026-10-17

`models.routes` and `resolve-config`'s `model-route` take three more run routes: `review-code` and
`review-security` for the code and security review lanes, and `triage-issue` for intake triage
([README.md, Models](README.md#models)). This repository adds two profiles, `pr-review` (`sonnet`,
effort `high`, 75 turns) for both review routes and `triage` (`sonnet`, effort `medium`, 30 turns)
for triage. No caller resolves these routes yet, so no run changes.

## 2.1.0 - 2026-10-17

The issue lane admits on the `agent-ready` label alone (owner decision, 2026-10-17), whoever added
it: a listed human, or the lanes App through work-unblock. The owner's ratification marker comment
is retired everywhere. `admission` loses `ratified` and now requires `classes`; resolve-issue sets
no `admission` and holds an issue labeled `needs-human`, `needs-owner-decision` or
`status: needs-decision` through `labels-absent`. The write runner's and check-trusted-trigger's
`ratified-app-label` input is renamed `app-label`, and the gate reads no comment or edit history
for the App's label. `write-issue.mjs` freezes the issue for every run when the account that
applied the label added it in the event that started the run (its newest `labeled` event no
later than the payload's issue `updated_at`; a limit-stop restart anchors at the label it
restarted), leaving out later comments and failing on a later title or body change.
resolve-issue also requires `agent-ready` on the issue when the run starts (`labels`), so removing
it stops a waiting run. label-unblocked no longer reads the marker or
resolve-issue's admission, and the pr-merge lane no longer refuses `not-ratified`. `version`
stays 2.

## 2.0.0 - 2026-10-17

A `models` block sets each model run's model, effort and turn budget as named profiles, with
`routes` from a skill activity or `verify-pr` to a profile and a `default-profile` for the rest
([README.md, Models](README.md#models)). It replaces an activity's `model` and `max-turns` and
`merge.verifier-model`, which the schema now rejects; a config with no `models` block gets the
built-in `standard` profile (model `default`, 75 turns). Model values are aliases only.
`resolve-config` outputs `profile`, `claude-args` and `settings-json` in place of `model`, takes a
`model-route` input for a run that is no lane activity, and rejects an undefined profile
(`undefined-profile`) or route (`undefined-route`). The runners pass `claude-args` and
`settings-json` to claude-code-action and drop their `default-model` and `default-max-turns`
inputs; `collect-base-activity` drops its `model` and `max-turns` inputs; `pr-verify.yml` resolves
`verify-pr`. The write runner's lane record gains `models` and `profile`, after `max-turns`. This
repository's block keeps every run as it was: `standard` for each skill activity, `review` (`opus`,
60 turns) for the verifier. `version` is now 2: the schema rejects a version 1 config.

Migration from version 1:

1. Set `version: 2`.
2. For each distinct `model` and `max-turns` pair an activity sets, add a profile under
   `models.profiles` (`{ model: <alias>, max-turns: <n> }`; `model: default` for no `--model`, an
   alias for a full model ID) and a `models.routes` entry from the activity to it; delete the
   activity's `model` and `max-turns`.
3. Replace `merge.verifier-model: <alias>` with a profile (`max-turns: 60` keeps pr-verify's
   former budget) and `models.routes.verify-pr`.
4. Set `models.default-profile`; `{ model: default, max-turns: 75 }` keeps the runners' former
   defaults. With no `models` block every run gets that profile.

The pr-pipeline-sandbox keeps its own schema copy at version 1 and migrates when it takes this one.

## 1.27.0 - 2026-10-17

`merge.diff-check` gains three optional pr-merge lane switches, each off when absent:
`high-path-floor`, `c2-contradictions` and `max-changed-files`. In the pr-merge lane an absent
`max-changed-lines` is now no cap, and an empty `denied-paths` denies no path instead of refusing
`denied-paths-unset`. The schema asks for `denied-paths` and `max-changed-lines` only under
authority `local-babysit`, which keeps every check whatever the switches say. This repository
empties `denied-paths` and drops `max-changed-lines: 400` (owner decision, 2026-10-17), so a lane
pull request may touch any path at any size; the residual risk is in "The pr-merge lane", "Risk
switches". `version` stays 1.

## 1.26.0 - 2026-10-17

The pr-merge lane reads no `work-class:` label. A pull request the lanes App opened, not a fork or
a dependency manager's, with exactly one closing issue in this repository and no denied path, is
class C2, and the diff-derived C2 checks of the risk score still apply. The pr-verify verdict is
the merge criterion: with a rung above off the gate refuses `verifier-verdict-not-required` unless
`merge.require-verifier-verdict` is true, and the schema rejects an enabled pr-merge lane
(`agent-identity` set, authority absent or `pr-merge`) at C2 or C3 without it. Right before the
enqueue the closing issue is read again, and a different one refuses
(`closing-issue-changed:<was>><now>`); a class label removed meanwhile no longer refuses. The
closing issue must carry the owner's ratification marker under resolve-issue's rule, read fresh
at eligibility and before the enqueue (`not-ratified`).
`admission.classes` is now optional: without it only the owner's ratification marker admits and no
`work-class:` label is read, and an `admission` must set `classes` or `ratified`. This repository's
resolve-issue now admits on `{ratified: true}` alone, so an issue labeled read-only or mechanical
with no marker no longer starts the lane, and a ratified issue carrying another class now does
("Merge authority", "Activities"). `version` stays 1.

## 1.25.1 - 2026-10-17

The review-dependency activity checks commit provenance
([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review)). Its classifier applies the
pr-merge lane's commit check as review reasons, so an unverified commit, one GitHub did not
commit, or one that is neither Dependabot's nor the version-bump commit sorts `review`, never
`auto`, and so does a commits listing short of the pull request's commit count
(`commits-listed:<listed>-of:<total>`). The select step skips `superseded-sha` when the head
moved since the gate, and records its start time before any model turn. The verdict job accepts
a `fix` only from commits GitHub signed for the lanes App during the run (author, committer
`web-flow`, a valid signature, a commit date no earlier than that start time) in a comparison
listed whole, else `dependency-invalid` or `superseded-sha`; it reads no Actions API. `run.json`
gains `files_truncated` and `started_at`, and a `merge` verdict on a truncated files listing
escalates the new reason `dependency-files-truncated`. `version` stays 1.

## 1.25.0 - 2026-10-17

Both Dependabot classifiers read the standards Dependabot policy at the base and make every update
to a dependency its `autoMerge.reviewOnly` lists tier `review` (`review-only:<dependency>`),
whatever the version change, and every Dependabot pull request tier `review`
(`dependabot-policy-unreadable`) when the policy does not read or a caller passes none. An entry's
`directory` covers a changed path in it, and a `github-actions` entry also covers the workflow and
action files the content rule gives its directory (README, "Review-only dependencies"). The
review-dependency activity gets the matched entries. Both classifiers also make an otherwise tier
`auto` npm or pip update tier `review` when its
registry provenance changed or cannot be read (`provenance-changed:<name>`,
`provenance-missing:<name>`, `provenance-unreadable:<name>`; README, "Registry provenance"). The
review-dependency select step outputs `controls`, `run.json` gains `controls`, and the write
runner gains a seventh dependency escalation reason, `dependency-control-uncited`: a `merge`
verdict on a review-only dependency that does not quote each matched entry's `control` in
`evidence`. The select step warns `classifier gap` when only a read failure sent a pull request
to review (README, "Classifier gaps"). `version` stays 1.

## 1.24.0 - 2026-10-17

`resolve-issue` lists two more `verify-scripts`, each wrapped by the same generator as the
can't-fail scan: `scripts/run-test-file.sh` runs one test file inside the checkout by name
(`test_*.py` under pytest, `*.test.sh` under bash, `*.test.mjs` under `node --test`, without
`GH_TOKEN` or `GITHUB_TOKEN`), and `scripts/git-mv-rm.sh` runs `git mv` or `git rm` inside the
checkout, recording an untracked path as intent-to-add first. Both refuse an absolute path, a `..`
segment, a leading `-` or `:` and a path that resolves outside the checkout (`scripts/lib/checkout-path.sh`).
`git-mv-rm.sh` sets `GIT_LITERAL_PATHSPECS=1`, so git reads no glob or pathspec magic, and
`run-test-file.sh` takes only `[A-Za-z0-9._/-]` names after `--`, so pytest reads no node id.
A write skill that commits also gets `mcp__github_file_ops__delete_files`, and the system prompt
tells it to delete each committed path it renamed or removed. When the stage grants the test-file
runner, the write runner sets up Python and installs the base's hash-pinned CI requirements before
the head checkout. `verify-scripts` may now list a script that changes files or runs checkout code
when the script limits itself. `version` stays 1.

## 1.23.0 - 2026-10-17

`merge.verify-authors` (`lane`, `any`; absent is `lane`) is a new optional key. Under `lane`
`.github/workflows/pr-verify.yml` judges only pull requests the lanes App opened (a `Bot` account
whose login is `merge.agent-identity`, compared as the pr-merge lane compares it) and skips any
other author's before the model runs, with the reason `author-not-lane`; `any` judges every
author's, and any other value judges none ("Verifier verdict"). `version` stays 1.

## 1.22.0 - 2026-10-17

`pr-unblock` gains `review-dependency` and `apply-dependency-verdict`, and `prepare` gains
`dependency-review` ([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review);
[ADR 0074](../../adr/0074-review-risky-dependabot-updates-in-a-model-job-and-act-in-a-scripted-job.md)).
`pr-unblock-dispatch.yml` also dispatches `review-dependency` for at most 2 review-tier Dependabot
pull requests per run whose head has no `pr-unblock / review-dependency` check run. The model job
(`mutate-branch`) reads a read-only context file, the checkout and the upstream release notes as
data, may push a fix outside `.github/` whose every commit carries `[dependabot skip]`, and returns
a `merge`, `fix`, `close` or `escalate` verdict as structured output. The verdict job
(`publish-artifact`, no model) validates it and posts the round marker, closes the pull request
with an ignore-entry issue (never a security update), or escalates. Neither merges: the pr-merge
lane merges a review-tier pull request on the `verdict=merge` marker at the current head (1.20.0,
[ADR 0073](../../adr/0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)). The
dispatcher sorts with the same tier and content rules as the pr-merge lane, and a base
`dependabot.yml` it cannot read is the reason `dependabot-config-unreadable`. `loop` gains
`dependency-review-rounds` (default 2; this repository sets 2), and the write runner gains the
`dependency-verdict`, `dependency-run-sha256` and `dependency-run-attempt` inputs and six
escalation reasons: `dependency-round-cap`, `dependency-invalid`, `dependency-fix-not-landed`,
`dependency-security-close`, `dependency-escalate` and `dependency-config-unreadable`. `version`
stays 1.

## 1.21.0 - 2026-10-17

`merge.require-verifier-verdict` and `merge.verifier-model` are new optional keys.
`.github/workflows/pr-verify.yml` judges each pull request head that passes `pr-require-checks`
and uploads a `pr-verify-<pr>-<head-sha>-<verdict>` artifact; with the first key true the pr-merge
lane refuses a merge, and dequeues a queued entry, without an allowing verdict at the head: a
counted `fail` under any pull request number or at an earlier head blocks, a pass needs every
linked issue written and last edited by a trusted human other than the author and unchanged since
the judgment, and a pull request older than 80 days goes to a human ("Verifier verdict" under
"Merge authority"). pr-merge.yml grants its job `actions: read` for the verdict reads. `version`
stays 1.

## 1.20.0 - 2026-10-16

`merge.dependabot.mode` (`off`, `report`, `enforce`; absent is `off`) adds the pr-merge lane's
Dependabot class (ADR 0073), and the pr-merge lane becomes the one merge authority for every
Dependabot pull request. The lane lists them unless the mode is `off`. Tier `auto` (every update
non-major, where major is a first-component change or, below 1.0, a second-component change;
Actions publishers `actions`, `github` or `anthropics` only; `ci-status` not red; read from the
verified commit metadata, else the title or body `Updates` lines, which must agree when both read)
merges on a green `ci-status`. Tier `review` merges only when the newest pr-unblock round marker
the lanes App authored names the current head with `verdict=merge`, and then also on a green
`ci-status`. Every commit must be a verified Dependabot commit, the `[dependabot skip]`
version-bump commit, or, after a review, the lanes App's `[dependabot skip]` fix; every push to
the head branch must be Dependabot's (or that commit's own pusher's), per the repository activity
API; and every changed path a manifest or lock file `.github/dependabot.yml` covers or a
`uses:`-only workflow or action repin; any other path makes the tier `review` with the reason
`dependabot-content:<path>`, while a failed push check always refuses. Both go through
the lane's gate as C2 with no closing issue, denied-path rule or diff risk score. The mode, not
`merge.report-only`, decides whether a Dependabot pull request writes, and the workflow starts the
post-merge full run when either can merge. `.github/workflows/pr-automerge-dependabot.yml` is
removed, and "Merge authority" no longer names it as an exception to the single authority.
`version` stays 1.

## 1.19.3 - 2026-10-16

"Outputs and skips" no longer says a leaf's verdict carries over to a commit with unchanged
content. A verdict and its findings belong to the commit the leaf judged, as "Activities" already
states, and a new commit gets a new verdict. `version` stays 1.

## 1.19.2 - 2026-10-16

`work-unblock.yml` also runs hourly (`schedule`, minute 47, from main only). A scheduled run lists
the issues closed in the last three hours (`LOOKBACK_HOURS` in `label-unblocked.mjs`; pull
requests and issues updated but closed earlier are left out), keeps those with a trusted close,
and applies the close path's rules to each issue they blocked, each once per run. It catches an
issue closed by a bot sender, such as a pull request merge, which the close-triggered run skips. A
scheduled run has no closer or re-runner to check; the kill switch and the `applies` gate still
run first, and the token request names no issue. On both paths, every blocking issue now counts as
done only when it was closed as completed with a trusted close, read fresh per blocker: its
`closed_by` is a listed human (by id), or a merge in this repository closed it: the `closer` of
the issue's last `ClosedEvent`, read with one GraphQL query, is a merged pull request or a commit
in this repository. The REST close event carries no link to the pull request, so GraphQL is the
read. Any other close, such as a workflow's `GITHUB_TOKEN`, does not count. A blocking pull
request counts only once merged, and a blocker in another repository never counts. An outside
author closing their own blocking issue therefore unblocks nothing. Both paths also refuse an
issue whose `agent-ready` label was ever removed, so removing it by hand stops the lane and
overlapping windows never put it back; a person adds it again to restart. The broker contract in
`pr-run-activity.md` lists `work-unblock.yml` as a `schedule` caller. `version` stays 1.

## 1.19.1 - 2026-10-16

The `verify-scripts` wrapper prints `exit status: <n>` to stderr and exits with the script's
status, and the system prompt tells the skill to run each wrapper as its own command: a chained
`; echo "$?"` needs approval the `dontAsk` lane denies. The write file's skill-run diagnostics
(`act-turns.json` and the step summary) gain `denied`, each command the permission mode denied,
redacted and cut to 300 characters. `version` stays 1.

## 1.19.0 - 2026-10-16

A skill leaf gains `verify-scripts`: exact paths of read-only checker scripts under `scripts/`,
`plugins/<plugin>/scripts/` or `plugins/<plugin>/skills/<skill>/scripts/`, no globs. For a skill
with an effect other than `read`, `collect-base-activity` copies each script's base plugin (or the
base `scripts/`) to a read-only `$RUNNER_TEMP/lane-verify`, denies `Edit` and `Write` on it, and
allows `Bash(<copy>/bin/<name> *)`, a wrapper that runs the script from the checkout with any
arguments except a path outside the checkout, with system, global, hook and fsmonitor git config
switched off. A leaf with effect `read` cannot set it. This repository's `resolve-issue` lists the
testing plugin's `cant-fail-scan.sh`. `version` stays 1.

## 1.18.5 - 2026-10-16

The write file gains the `ratified-app-label` input, issue mode only. `work-resolve-issue.yml`
sets it to `agent-ready` and no longer skips the lanes App's `agent-ready` label: the trigger gate
lets that one label from the App through only while the issue carries the owner's ratification
marker, read from the API when the run starts by the rule resolve-issue's admission uses
(`resolve-config/ratification.mjs`). Because the run reads the issue's title and body, a body
edit or title change after the newest marker also stops it. Any other App label or event, a
failed read, or no marker stops the run. The lanes token broker accepts the same labeler for an
`issues` mint, re-checking the marker. `version` stays 1.

## 1.18.4 - 2026-10-16

This repository's `pr-pipeline.yaml` adds the `work-unblock` lane (stage `work`) with one
activity, `label-unblocked` (a script, `mutate-tracker`). `work-unblock.yml` runs it when a
listed human closes an issue: each issue the closed one blocked gets `agent-ready` when it is
open, every blocker is closed as completed (not as not planned or duplicate), it carries none of
`needs-owner-decision`, `status: needs-decision` or `needs-human` in any casing, it holds the
owner's admission marker as resolve-issue reads it (the check now lives in
`resolve-config/ratification.mjs`, shared by both), and resolve-issue's `admission` admits it
(no `work-class:` label outside its classes; read from the config by
`resolve-config`'s `readAdmission`). The workflow stops before the token request when the
resolved activity does not apply (`enabled: false`). The label starts `work-resolve-issue` once
resolve-issue accepts App-added labels (follow-up by Automation Lanes). Everything is re-read
from the API when the run starts. A close whose sender is a bot (`sender.type` `Bot`), or whose
closer or re-runner is not a listed human (each is checked on its own; a re-runner may be
another listed human), is a clean skip. `version` stays 1.

## 1.18.3 - 2026-10-16

A verdict is bound to the commit it judged: the README no longer promises reuse by patch id or
content fingerprint. A `pr-merge` merge needs a verdict on the commit being merged, a precondition of
the lane's own merge rather than a required check, and a lane merge commit needs a fresh one. The
address-feedback round cap is `loop.review-rounds` (default 2) instead of a fixed 2. This
repository's `pr-pipeline.yaml` sets it to 3. `version` stays 1.

## 1.18.1 - 2026-10-16

`pr-merge.yml` no longer wakes on `workflow_run` completions of `pr-require-checks`,
`pr-review-hosted` and `pr-review-security-hosted`, and its schedule runs every 15 minutes
instead of hourly. Those completions arrived faster than the serialized runs finished, so the
`pr-merge` concurrency group's queue reached GitHub's 100-run cap and further runs were rejected.
Every run already reads every open PR, so the schedule finds what those wake-ups found.
`version` stays 1.

## 1.18.0 - 2026-10-16

`applies-when` gains `admission` (`classes`, optional `ratified`), an issues lane's admission
rule. An issue carrying a `work-class:` label outside `classes`, in any casing or spacing, is
refused with `not-applicable`, even beside a listed class. Otherwise an exact listed class label
admits it, or, with `ratified: true`, the owner's batch-ratification marker
`<!-- admission: admitted when unblocked, owner batch ratification YYYY-MM-DD -->` does: a line
in a never-edited comment by a human on the trusted-actor list, posted through no GitHub App. No
bot ratifies, the lanes App included. An `admission` predicate reads the issue's labels when the
run starts, and with `ratified: true` reads its comments; off an issues event, or when that read
is refused, the run fails. resolve-config logs the id, author and creation time of the ratifying
comment, never its text. This repository's `resolve-issue` replaces its `labels` allowlist with
`admission: { classes: [read-only, mechanical], ratified: true }`. `version` stays 1.

## 1.17.3 - 2026-10-16

This repository's `pr-pipeline.yaml` enables the address-feedback round: the `pr-unblock` lane now
runs `resolve-conflicts`, `address-feedback` (`source-control:pull-request comments --ci`,
`prepare: review-threads`, `mutate-branch`, held by `do-not-merge` or `needs-human`, skipping
drafts), `publish-feedback` (the reply script, `publish-artifact`) and `report-escalation`, which
now follows all three. `pr-feedback-dispatch.yml` starts dispatching on lanes App PRs from here
on. `version` stays 1.

## 1.17.2 - 2026-10-16

The write runner's promote step re-reads the PR's labels and draft flag with the job's
`GITHUB_TOKEN` right before it moves the PR branch: `do-not-merge`, the base's human-gated role
label, a label in the activity's `labels-absent` list, or a draft set while the activity ran drops
the lane's commits and skips `awaiting-human`, for every `mutate-branch` activity that promotes.
The hold labels are now read from the base by their own step for every PR-mode skill, not only
merge-base, and the merge commit step holds on the same list. `fix-docs` gains `draft: [false]`,
so it skips a draft before any model turn. `publish-feedback.mjs` re-reads the
PR branch before each post and each resolve and posts nothing more once it moved past the head the
job gated (`feedback-not-landed` before any reply, `feedback-partial` after one), and its round
marker names the model run, so a re-run of the reply job alone posts no second marker (a model run
that uploaded no replies names none and always posts). The
script needs `HEAD_REF`, `GITHUB_RUN_ID` and `MODEL_RUN_ATTEMPT`. `version` stays 1.

## 1.17.1 - 2026-10-16

`pr-feedback-dispatch.yml` no longer resolves the whole `pr-unblock` lane, which decided every
slot's `applies-when` and failed on `resolve-conflicts`' `mergeable` predicate with no head SHA.
`feedback-dispatch.mjs` finds the PR and its head first, then resolves only the `address-feedback`
slot for them, and dispatches only when the lane, `address-feedback` and `publish-feedback` are
enabled and `address-feedback` applies. A disabled slot no longer counts as present, and a lane with
no `address-feedback` slot still skips; a config the resolver refuses fails the run. resolve-config's
`resolve-config.mjs` exports `resolveFromBase`, which returns the resolved config or throws the
resolver's refusal (with `absentAsNull`, null for a valid config whose lane lacks the activity);
`main` wraps it. `resolve.mjs` exports `laneHasActivity`.

## 1.17.0 - 2026-10-15

`pr-unblock.yml` takes an `activity` input (`resolve-conflicts`, the default, or
`address-feedback`), and its dispatch concurrency group names the activity. `address-feedback`
runs as two jobs: the model job (`mutate-branch`), then, when its `feedback-round` output is
`true`, the `publish-feedback` script job (`publish-artifact`, `review-replies: true`, and the
model job's `feedback-run-sha256` as `review-run-sha256`), which posts the replies;
`report-escalation` takes any job's reason and its resume command names the activity. The
activity rules forbid `address-feedback` every effect that posts and `publish-feedback` every
effect that pushes. `pr-feedback-dispatch.yml`
dispatches `address-feedback` from `workflow_run` when both review lanes have reviewed a lanes App
PR's current head and a reviewer-bot thread is open; the trigger gate and the broker accept its
runs through the review run their record names, which a lanes App push or a listed human must have
started. The jobs after the model job pass its gated head as `expected-upstream-head`, so the gate
and the broker accept the review of that head when only commits GitHub signed for the lanes App
during the run (committer `web-flow`, signature `valid`) follow it. The dispatcher skips while a `pr-unblock address-feedback #<n>` run (the new
`run-name`) is queued or going, and dispatches nothing until the lane config holds both slots. The
write file gains the `expected-upstream-head` input and `head-sha` output. No effect grants both `contents: write` and
`pull-requests: write` but `merge`. No live activity sets either leaf yet. `version` stays 1.

## 1.16.0 - 2026-10-15

Schema: `prepare` takes `review-threads`. `pr-run-activity.md` "prepare: review-threads" says what
the write runner then does in two jobs. The model job keeps the reviewer bot's unresolved threads
on a marker-confirmed head before the mint, escalates `feedback-protected-path` or
`feedback-round-cap` before any model turn, stages the review-thread tool, pushes the fixes, and
uploads the replies the tool recorded; it posts nothing. A script job with the new
`review-replies` input and no model validates those replies, posts them and resolves only the
fixed `VALID` threads, posts the round marker, and escalates `feedback-uncertain`,
`feedback-not-landed`, `feedback-invalid`, `feedback-partial` (posting stopped partway),
`feedback-incomplete` (a kept thread has no disposition) or `feedback-disputed` (an INCORRECT
reply, left open for a person). The write file gains the `feedback-round` output. No
live activity sets it yet. `version` stays 1.

## 1.15.0 - 2026-10-14

Issue mode: `report-outcome` opens the PR ready, not draft, since the skill's CI mode now runs the
same prep the local pull-request prep does. A `report-statuses` job posts
`pipeline/<activity>` commit statuses for the lane's steps. Nothing is skipped on a success; a
failing one holds the pr-merge gate like any failing check.
`version` stays 1.

## 1.14.0 - 2026-10-14

Schema: a skill leaf's optional `web-access` (`enabled`, `domains`: `any` or host names), off when
absent; turning it on requires `reads-untrusted: true` and an effect other than `read`. `pr-run-activity.md` "Skill activities" says
what the write runner then allows: `WebSearch`, `WebFetch` to those domains (which also opens them
to sandboxed shell commands) and the research skills, with their plugins installed. The live config
turns it on for `resolve-issue` with `domains: any`; the token residual now says the model can send
its token to any allowed domain. `collect-base-activity`'s `plugin` output is now `plugins`, one per line. `version` stays 1.

## 1.13.2 - 2026-10-14

"The pr-merge lane" considers only pull requests the lanes App opened, and reads the work class from the pull request's single closing issue, never from a
label on the pull request, and counts a class label the lanes App or a human in person applied.
`report-outcome` no longer copies `work-class:` labels onto the PR, and `pr-merge.yml` shortlists
the lanes App's open PRs instead of PRs carrying the label. The live config's comment on
`merge` says so, and each `denied-paths` entry carries a one-line reason. `version` stays 1.

## 1.13.1 - 2026-10-14

The pr-merge workflow queues extra runs (`concurrency.queue: max`) instead of letting GitHub cancel
all but one waiting run, which left CANCELLED `merge` checks on PRs. No rule or schema change.
`version` stays 1.

## 1.13.0 - 2026-10-14

Schema: a skill leaf's optional `checks`, repository check scripts with fixed flags that a write
skill may run. `pr-run-activity.md` "Skill activities" says how the write runner runs them from the
base copy against the checkout. The live config gives `resolve-issue` the changelog fragment format check.
`version` stays 1.

## 1.12.4 - 2026-10-14

"The pr-merge lane" names three more reads it changes: the kill switch comes from the workflow's
own check (`--lane-kill-switch proceed`; missing or any other value stops), the rung cap from the
workflow's `vars` (`--lane-rung-cap`; empty is no cap), and the post-merge check
and in-flight rule count only merges the agent identity enqueued. In report-only mode the workflow
starts no full CI run. `version` stays 1.

## 1.12.3 - 2026-10-14

The `work-resolve-issue` lane's allowlist gains `work-class: mechanical` beside `work-class: read-only`,
and the comment above it names both. `labeled-after` is unchanged. `version` stays 1.

## 1.12.2 - 2026-10-14

The `work-resolve-issue` lane goes live: its `labeled-after` is now 2026-10-14T19:21:59Z, so issues
labeled `agent-ready` after that time start a run. The allowlist stays `work-class: read-only`
only. `version` stays 1.

## 1.12.1 - 2026-10-14

The live config gains the `pr-merge` lane with one `merge-pr` activity (effect `merge`, the babysit
wrapper under `--authority pr-merge`), run by `.github/workflows/pr-merge.yml`. `version` stays 1.

## 1.12.0 - 2026-10-14

Issue mode. Schema: stage `work`, and the `labeled-after` predicate, an issues lane's go-live time.
`pr-run-activity.md` gains "Issue mode": the write runner's `issue-number` input runs a lane on an
`issues` event with no PR. The live config gains the `work-resolve-issue` lane (`resolve-issue`,
then `report-outcome`), admitting `work-class: read-only` issues labeled after a go-live time that
ships in the far future, so the lane starts nothing until the owner sets it. `version` stays 1.

## 1.11.1 - 2026-10-14

`pr-run-activity.md` "The lane token broker": the request body gains `issue_number`, which the
broker requires on an `issues` event, sent by `request-lane-token`'s new `issue-number` input.
`version` stays 1.

## 1.11.0 - 2026-10-14

Schema: `merge.report-only` (boolean, default false). README "Merge authority" describes it and
adds "The pr-merge lane": the babysit wrapper under `--authority pr-merge`. The live config gains a
`merge:` block for the pr-merge lane with `report-only: true`. `version` stays 1.

## 1.10.5 - 2026-10-12

README: `ci-status` on a draft passes its skipped lanes; the `ready_for_review` run tests the head
and the merge queue re-runs every lane before a merge. `version` stays 1.

## 1.10.4 - 2026-10-12

README gains "Planning lane work": a one-page plan per sub-topic, design and stress tests only for
trust-boundary changes, ADRs only for trust-boundary or irreversible choices, and stops limited to
owner-reserved items when the owner pre-approved the recommendations. `version` stays 1.

## 1.10.3 - 2026-10-12

`pr-run-activity.md` run job step 14: the lane-token revoke step never fails the job. A DELETE
other than 204 is a `::warning::`, and a 204 whose `GET /installation/repositories` is not yet
refused with 401 is a `::notice::`. A confirmed revoke is recorded in the step log.
`scripts/write-runner-revoke-step.test.sh` runs the step's script against each case. `version`
stays 1.

## 1.10.2 - 2026-10-12

`pr-run-activity.md` "The lane token broker": the broker now also requires the dispatcher run's `pr-unblock-dispatched-<ids>` record to list the requesting run, read once with no wait. `version` stays 1.

## 1.10.1 - 2026-10-12

`check-trusted-trigger` refuses a `pr-unblock.yml` run sent by `github-actions[bot]` with `untrusted-actor` unless the dispatcher run it names uploaded an unexpired `pr-unblock-dispatched-<id>[-<id>...]` artifact listing this run's id, waiting up to 2 minutes for it. `version` stays 1.

## 1.10.0 - 2026-10-12

The config names its merge authority and the identity the local babysit lane acts as. Additive:
`version` stays 1, and the live config gains no `merge:` block, so its rung stays `off`.

- `merge.authority` (`local-babysit` or `pr-merge`) names the repository's one merge authority.
  Absent means `pr-merge`, the meaning a rung had before this key existed, so an existing
  `rung: C2` config still validates; the babysit wrapper merges only when it reads `local-babysit`.
- `merge.agent-identity` (the `[bot]` login of a dedicated GitHub App; any other login, and the
  shared `github-actions[bot]` and `dependabot[bot]` in any letter case, fail the schema) names the
  login the local babysit lane acts as. The schema requires it when `merge.authority` is `local-babysit`.
- `resolve-config` ignores both keys, so its resolved output is unchanged.
- README "Merge authority" gains "The local babysit lane": the effective rung, same-repository
  heads only, LOW risk only, review evidence bound to the pinned head SHA, the human-only cap
  variable `CLAUDE_LANES_MERGE_RUNG_CAP` and its 404 rule, the kill-switch reads, the demotion
  issue and how a human clears it, the opt-in label `merge: agent-allowed`, the HIGH path floor,
  the merge queue with `--match-head-commit`, one merge in flight, and
  `pr-automerge-dependabot.yml` as the one exception to a single merge authority. A verdict
  carried over by content fingerprint now applies to `pr-merge` only. "Outside this repository"
  gains the agent identity row.
- The example config shows both keys, commented out.

## 1.9.1 - 2026-10-12

The lanes token broker denies a repository whose `CLAUDE_LANES_REPO_DISABLED` variable is absent,
on both its token and check endpoints, with reason `kill-switch` (the detail reads
`not-false: the repository switch CLAUDE_LANES_REPO_DISABLED is not set`; azure-iac#24). `version` stays 1. Every repository on the
broker's allowlist must declare the variable as `false`.

## 1.9.0 - 2026-10-11

The read runner asks the lanes token broker before its model step. `version` stays 1; callers of
the read file must grant `id-token: write`.

- `pr-run-activity-read.yml` gains a `broker-check` job that the run job `needs`. It holds
  `contents: read` and `id-token: write`, runs only default-branch-tip actions, and never checks
  out the PR head. After a local kill-switch stop it ends green without a broker call, so the run
  job stops the lane neutral as before. Otherwise it posts once to the broker's check endpoint
  (`LANES_BROKER_URL` with `/token` replaced by `/check`), which mints nothing, and fails on any
  answer but an allow (`lane-check-denied`) or on none (`broker-unreachable`). The report job
  reads that failure as the run result, so the check is a failure, not neutral. The run job still
  holds no OIDC token, and fails red with `kill-switch` unless the broker-check job allowed its own
  run attempt, so "Re-run failed jobs" cannot reuse an earlier allow.
- `request-lane-token` gains `mode: check`, which takes only the broker variables, lane and
  activity and fails red on any write-path input.
- `scripts/check-read-caller-keys.sh` allows `id-token` in the read file only inside its
  `broker-check` job, and fails when that job is a reusable call or checks out anything but this
  repository's default branch tip, when the read file's top level is not `permissions: {}` or a
  job has no permissions map, and on `permissions: write-all` in any file of a read run.
- Callers of either file grant `id-token: write` on the calling job.
- The broker's check endpoint sees a repository variable named `CLAUDE_LANES_DISABLED` that
  shadows the org value, so a shadow no longer lets a read lane run.

## 1.8.0 - 2026-10-11

The `pr-unblock` dispatcher lands, and the write runner trusts its dispatches. `version` stays 1.

- New workflow `.github/workflows/pr-unblock-dispatch.yml` (script
  `.github/scripts/pr-unblock/dispatch.mjs`) runs on each push to `main` and dispatches
  `pr-unblock.yml` for the open, non-draft, same-repository PRs GitHub reports as conflicting, at
  most 3 per run, skipping a head that already carries a `pr-unblock` check run.
- `pr-run-activity-write.yml` passes `check-trusted-trigger` its `dispatcher-run-id` with the
  `pr-unblock-dispatch.yml` and `pr-unblock.yml` paths, so a `github-actions[bot]` dispatch runs
  only through a checked dispatcher run instead of always stopping `untrusted-actor`.

## 1.7.0 - 2026-10-11

The `pr-unblock` lane gets its caller and live config. `version` stays 1.

- New caller `.github/workflows/pr-unblock.yml`, `workflow_dispatch` only (inputs `pr-number`,
  `dispatcher-run-id`): job `resolve-conflicts`, then job `report-escalation` only when the first
  job's `escalation-reason` output is set, which it passes on as that job's `escalation-reason`.
  Both jobs pass `dispatcher-run-id` and `trusted-base: default-tip`.
- Every write caller job, `pr-refine`'s included, queues in one per-PR job group
  `pr-pipeline-write-<n>` (`queue: max`); `pr-unblock` also has the workflow group
  `pr-unblock-<n>`. `pr-refine`'s caller job now also skips the lanes App's own `pull_request`
  events, so a lane push never waits in that group. README: new [Concurrency](README.md#concurrency)
  section.
- The live config adds the leaves `resolve-conflicts` (applies only to a conflicting, non-draft
  PR without `do-not-merge` or `needs-human`) and `report-escalation`, and the lane `pr-unblock`;
  `pr-refine / fix-docs` also skips while `do-not-merge` or `needs-human` is on the PR.
- README: a base merge escalates only on a conflicted `.github/workflows/` path or a model-staged
  change under it; a workflow change that merges cleanly from the base is pushed.

## 1.6.0 - 2026-10-11

The write runner performs `prepare: merge-base` and takes the pr-unblock lane's inputs. `version`
stays 1.

- `pr-run-activity-write.yml` passes `prepare-supported: true` to resolve-config and runs a
  `prepare: merge-base` leaf around a merge of the trusted base: the base's `prepare.sh` before
  any model turn (a clean merge skips the skill), the skill without the commit tool, `post.sh`,
  then a two-parent merge commit through the Git Data API, promoted onto the PR branch.
  `collect-base-activity` takes a `prepare` input that leaves out the commit tool and the
  instruction to commit. Paths and checks: `pr-run-activity.md`, "prepare: merge-base".
- New inputs `dispatcher-run-id` (passed to `check-trusted-trigger` with no dispatcher or
  dispatched workflow named, so every `github-actions[bot]` dispatch stops `untrusted-actor` until
  the dispatcher change names both), `trusted-base` (`pr-base` or `default-tip`, passed to
  `check-trusted-base` as `mode`; `default-tip` trusts the default branch tip for config, actions
  and the merge's second parent) and `escalation-reason` (enum-checked, exported to a script as
  `ESCALATION_REASON`). New `workflow_call` output `escalation-reason`.
- The write runner sends `dispatcher-run-id` to the lanes token broker as `dispatcher_run_id`, a
  positive JSON integer that the broker reads only for a run sent by `github-actions[bot]`
  (broker side: azure-iac#20).
- Every `mutate-branch` activity re-reads its PR branch from `git/ref` before the mint; a moved
  branch skips neutral `superseded-sha` with no token and no model turn. This changes pr-refine:
  such a run used to run the skill and then fail at promote.
- The promote step confirms the PR branch through `git/ref` after moving it, and the report job
  re-reads `GET /pulls/{n}` until its head matches that ref, at most 5 reads 2 s apart.
- New scripted leaf `.github/scripts/pr-unblock/report-escalation.sh` (effect
  `publish-artifact`): labels the PR with the human-gated role label and posts one comment with
  the reason and a resume key. The write runner hands a script the base's
  `.work-item-tracker.json` as `TRACKER_CONFIG`, copied before the head checkout and hash-checked.
- Hardening of the merge-base steps: workflow commands stop while the merge scripts and git run,
  `GIT_NO_REPLACE_OBJECTS=1`, an allowlisted environment and absolute binaries in the commit
  step, a fresh label read that stops the commit on `do-not-merge` or the human-gated label, and
  a promote that moves the PR branch only to the commit step's own commit.
- `scripts/write-runner-never-rules.test.sh` asserts the write runner's structure against the
  resolve-conflicts `never` row: no forced ref update, no commit unless `post.sh` cleared the
  merge, the mint before the head checkout, and base scripts run only after their hash check.

## 1.5.0 - 2026-10-11

Composite activities, three new predicates and the `unblock` stage. `version` stays 1: no config
in this repository or the sandbox used the removed `respond` stage or the retired lanes.

- The `respond` stage is now `unblock`. `lane-rules.json` gains `pr-unblock` (stage `unblock`,
  forbidden effect `merge`) and drops `pr-address-feedback`, `pr-fix-ci` and `pr-update`, so a
  config that still names one of those lanes fails `lane-stage`.
- An activity is a leaf or a composite. A composite lists `children:` slots and may set
  `applies-when`; it declares no effect. The reader expands it into its leaves, applies lane rules
  to each, ANDs `enabled` down the path, requires every predicate on the path to match, and
  rejects an undefined child, a non-sibling `needs:`, a cycle, a composite inside a composite, and
  a leaf that appears twice in a lane. `resolveGrant` grants a leaf only.
- A leaf may set `prepare: merge-base` (a writing skill only); resolve-config outputs it.
- New predicates: `mergeable` (`conflicting`, `clean`; read only from `GET /pulls/{n}` at the new
  `head-sha` input, re-read while unknown, then `prerequisite-missing`), `labels-absent` (a listed
  label on the PR skips with `awaiting-human`) and `draft`.
- New trust-root `resolve-config/activity-rules.json`: per-leaf `never` text and optional
  `forbidden-effects`. A leaf with no row is valid.
- The example config replaces the three `respond` lanes with `pr-unblock` and its
  `resolve-conflicts` and `report-escalation` leaves.

## 1.4.2 - 2026-10-10

Docs only. `version` stays 1.

- README: "Outside this repository" names where each external piece the lanes depend on is
  documented (broker, Lanes App, org variables, rulesets, sandbox, standards, ci-workflows).

## 1.4.1 - 2026-10-10

A skill activity can read its own plugin and a write activity commits its edits. `version` stays 1.

- Every skill gets `Read` on `$RUNNER_TEMP/base-marketplace`, where its plugin loads from.
- A write skill gets a scratch directory (`--add-dir` plus an `Edit` rule) and an appended system
  prompt naming it; when the grant can commit, the prompt tells it to commit every file it changed
  with `mcp__github_file_ops__commit_files`. `collect-base-activity` takes a `can-commit` input.

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
