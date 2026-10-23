# Changelog for the PR pipeline convention

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
