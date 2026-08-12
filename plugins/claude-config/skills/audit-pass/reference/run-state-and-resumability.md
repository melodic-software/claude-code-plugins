# audit-pass — run state, concurrency, and resumability

This file owns §3 and §5: the state key, the applying lock, the lease that tells a live run from an
abandoned one, and what `--resume` re-runs rather than carries forward.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

## 3. Run state, keying, and concurrency

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project, so state keyed by working directory would
collide or fragment depending on where the operator happened to stand.

**`<state-key>` = `<repo-identity>/<worktree-discriminator>`.**

- **`repo-identity`** — for a git repository, the first configured remote URL normalized to
  `host/owner/repo`, lowercased, `.git` suffix and credentials stripped. With no remote,
  `local/<sha256 of the canonicalized repo root>` truncated to 12.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository on different branches legitimately hold different content and must not
  share a run report.

Suppressions are keyed differently on purpose (§4): they are a decision about the *repository*, not
about a checkout, so they are shared across worktrees and committed where the operator owns the
target.

**Concurrency.**

- A read-only run takes **no lock**; concurrent read-only runs are safe and are not serialized.
- An applying run takes an **exclusive advisory lock** at `runs/<state-key>/lock`, containing the
  process id, the platform's process **start identity** where one exists, an ISO-8601 start
  timestamp, and the holder's **run id** — the run id because reclamation must be able to find the
  holder's lease, which is keyed by it.
- A second applying run for the same state key **refuses and exits non-zero**, naming the holder's
  pid and start time. It does not wait — a pass over a large tree runs long, and a silent queue looks
  like a hang.
- A lock is stale and is reclaimed — with the reclamation reported in the run output — when its
  timestamp is older than 30 minutes **and** its holder is not alive, where *alive* means the
  recorded pid **and its recorded start identity** both match. Process ids are reused, so a bare
  liveness test on a crashed run's pid can answer "alive" about an unrelated long-lived process: the
  conjunction then never fires and every later `--fix` for that state key refuses forever, with no
  documented way out.
- **Where the platform supplies no start identity, age alone does not reclaim — the holder's lease
  is the second conjunct.** Reclamation reads the lease at `runs/<state-key>/<holder run id>/lease`
  and applies the *same* two-sided liveness test §3 already defines below. Past 30 minutes with a
  **stale** or `released` lease, the lock is reclaimed and the reclamation says so; past 30 minutes
  with a **live** lease, the second run **refuses exactly as it would inside the window**, naming the
  holder's run id and its `heartbeat_at`. A run that exceeds 30 minutes while still heartbeating is
  slow, not dead, and assertion 3.1 must hold for it — age-only reclamation there hands the lock to a
  second applying run and breaks "exactly one proceeds" on precisely the platform that can least
  detect it.
- **On that same no-start-identity platform, a lock carrying no run id — one written before this
  rule — is not reclaimed on age either.** Where a start identity *is* available the bullet above
  already decides such a lock: pid and start identity together answer liveness definitively, and no
  lease is consulted. Only where neither identity is available does the second conjunct have to be
  established the other way round, by enumerating `runs/<state-key>/*/lease` — every lease
  under this state key, which is a bounded read of the run tree the state key already scopes. Any
  one of them live by the same two-sided test defers the reclaim exactly as a named holder's live
  lease would; only when none is live does the age bound reclaim. An upgrade mid-run is otherwise
  the one moment this contract would hand a live holder's lock away, and it is precisely the moment
  a second applying run is most likely — the operator has just changed something and is re-running.
  The enumeration deliberately over-defers: a lease records no run mode, so a live **read-only**
  run's lease also defers the reclaim of a legacy lock. That is the fail-closed direction and it is
  bounded — a read-only run's lease goes `released` or stale on the same terms as any other — and it
  applies only to locks predating this rule, since a lock carrying a run id names its holder exactly.
- **This does not reintroduce the unreclaimable lock the age bound exists to prevent.** That failure
  needs a holder that is both past the age bound and *provably* alive; a crashed or killed run stops
  refreshing, so its lease goes stale once its own recorded `stale_after_s` elapses and the lock is
  reclaimable from then on. A
  lease that is missing or unreadable is treated as stale for this test — the absence of a heartbeat
  is not evidence of life. This is the shape `claude-ops`' restart-consumer settled for the same
  defect class (`plugins/claude-ops/skills/lanes/context/restart-consumer.md`, "**age alone never
  reclaims**"): without a start identity a live holder only **defers** the reclaim. The bound on that
  deferral differs by design — restart-consumer, whose holder publishes no lease, needs a hard
  24-hour ceiling; a lease-bearing run needs none, because a dead holder's heartbeat stops and the
  deferral ends on its own once that lease's recorded threshold elapses.

### The lease — how `--resume` tells a live run from an abandoned one

Every run writes a lease; only an applying run also takes the lock above. The two are separate
mechanisms and the lease grants no exclusivity: it exists solely so `--resume` can classify an
incomplete run, which the no-lock read-only policy otherwise makes undecidable.

**The lease is written and classified by a script, not by hand.** `scripts/run-state.sh` owns the
write and the verdict:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh" paths \
  --plugin-data "${CLAUDE_PLUGIN_DATA}" --run-id <run-id>
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh" lease acquire \
  --run-dir <run-dir> --run-id <run-id> --plugin-data "${CLAUDE_PLUGIN_DATA}"
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh" lease heartbeat --run-dir <run-dir>
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh" lease classify  --run-dir <run-dir>
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh" lease release   --run-dir <run-dir>
```

`classify` prints `live`, `stale`, `released`, or `missing` and exits 0 — refusing `--resume` against
a `live` lease is the caller's move, not the script's. Pass `--plugin-data` explicitly: the
`${CLAUDE_PLUGIN_DATA}` placeholder substitutes in *this text* but is not exported to the Bash tool's
environment (§2), so a shell cannot expand it.

**`acquire` requires `--plugin-data` because it is the only command that creates a directory**, and
that is where the write tree is pinned: a run directory not under `<plugin-data>/runs/` is refused
rather than created. Without the check, a wrong or invented `--run-dir` — the target root, say —
would get created and a lease written into it, and this skill keeps Bash specifically for state
writes while promising that a bare audit writes nothing into the target. Every later command operates
on a run directory `acquire` already validated.

**What is executable here, and what is not.** Everything below through the two-sided liveness test is
enforced by that script and covered by `run-state.test.sh`, negative tests included. Two clauses are
**not**: stale-lease **adoption** (the `owner_epoch` compare-and-set) and §7 **assembly**
(highest-epoch, highest-terminated-attempt selection). The script writes `owner_epoch` into the lease
and names the partial after it, so the epoch is a value on disk rather than a notion — but nothing
increments it or fences a previous holder, and a run performing an adoption is performing it itself.
Stated here because the rest of this section reads as machinery, and a contract that reads as
enforced while nothing enforces it is the defect this section was carrying.

**An applying run writes its lease before it takes the lock**, and the order is normative rather
than incidental: reclamation reads the holder's lease as its second conjunct, so a lock whose lease
does not yet exist would be classified stale and reclaimed on age alone — the failure this section
removes, reappearing through a window between the two writes. Writing the lease first closes the
window in the safe direction: a lease with no lock is simply a run that has not acquired yet, which
no reclamation test consults.

- **Path** — `runs/<state-key>/<run-id>/lease`, beside that run's own partial artifact, so one lease
  describes exactly one run and concurrent read-only runs never contend for it.
- **Contents** — the run id, the process id, an ISO-8601 start timestamp, a **`heartbeat_at`**
  timestamp the run rewrites in place, an **`owner_epoch`** integer starting at 1, and the
  **`stale_after_s`** and **`skew_grace_s`** thresholds this writer committed to.
- **Refresh is boundary-driven, not timed.** The holder rewrites `heartbeat_at` at acquisition, at
  every lane's persistence point, and at release. It is **not** rewritten on a wall clock: a
  skill-driven run acts between tool calls and has no timer, so a 60-second cadence — which this
  section specified before the script existed — named a mechanism no run could keep, which is the
  same defect as specifying a lease and shipping no writer.
- **Liveness — the thresholds live in the lease, and the classifier reads them from there.** The lease
  is **live** when `now - heartbeat_at < stale_after_s`; otherwise it is **stale**. Putting the
  threshold in the artifact is what makes "live or abandoned" a function of what was *written* rather
  than of what the classifier happens to believe — the concern this section closes at the end of the
  subsection, resolved by the artifact instead of by an asserted constant.
- **The default `stale_after_s` is 30 minutes, not the 5 the timed cadence implied.** Five minutes was
  five 60-second refresh intervals; with refreshes at lane boundaries, a single delegated lane can
  outlast it, and a threshold shorter than a lane classifies a *running* pass as abandoned — the one
  direction that is unsafe, because it lets `--resume` adopt a live run's artifact. Longer only ever
  costs an operator a wait, and the `released` tombstone below removes that cost from every clean
  exit. A run that knows its lanes are short may commit to a shorter threshold via `--stale-after`;
  the classifier honors whatever the lease records, with one floor — **`--stale-after 0` is refused**,
  because a lease recording a zero window satisfies the staleness test the moment it is written and is
  therefore born abandoned, adoptable by `--resume` out from under the run that just wrote it. It is
  refused rather than clamped: a clamp would hand a caller a window it did not choose and then report
  on it.
- **A run that exits cleanly writes a `released` state into its lease** — a tombstone — rather than
  leaving its last heartbeat to age out. Without it, a run that finished normally while deliberately
  leaving a lane incomplete (the `/doctor` handoff is exactly this) looks live for the full five
  minutes after its process is gone, so the operator who does the fastest correct thing — run
  `/doctor`, come straight back with `--resume` — is the one refused. The mechanism designed to
  protect an in-flight run would be punishing the intended workflow.
- **`--resume` therefore distinguishes three lease states, not two**: `released` is resumable
  immediately; a **stale** lease is resumable and adoption is reported, since it means an interrupted
  run rather than a finished one; and a **live** lease exits non-zero, naming the run id and its
  `heartbeat_at`, without attaching. A crash still leaves no tombstone, which is precisely why the
  staleness path stays as the fallback — the tombstone is an optimization for the clean case, never
  the only way out.
- **Adoption fences the previous holder; a stale lease is not assumed abandoned.** A suspended
  process can wake at any time, so "it stopped refreshing" is evidence, never proof. The lease
  therefore carries an **`owner_epoch`**, a monotonically increasing integer. Adopting a stale lease
  increments it in a single atomic write conditioned on the observed value — the compare-and-set is
  what makes two simultaneous adopters resolve to one — and the adopter then owns that epoch.
  **Every heartbeat refresh re-reads `owner_epoch` and aborts the run if it is no longer the writer's
  own**, so a woken holder stops at its next refresh rather than resuming alongside the adopter.

- **Checking the epoch before appending is not enough, and the artifact is what makes it safe rather
  than the check.** A check and a write are two operations: the old holder can read its epoch an
  instant before the adopter's compare-and-set and append an instant after, and no ordering of two
  separate steps closes that window. So the partial artifact is **epoch-scoped** —
  `findings.partial.<owner_epoch>.jsonl` — and a writer only ever appends to the file named for the
  epoch it holds. A stale writer therefore appends to its **own** superseded file, physically unable
  to interleave into the adopter's, and **assembly reads only the highest epoch present**. The race
  is removed rather than narrowed, which a lock around check-and-append would not achieve across
  processes on every filesystem this runs on. Superseded files are retained, not deleted: they are
  the evidence that an adoption happened, and a run that was fenced mid-flight is worth being able to
  inspect.
- Without fencing, both processes could reach a not-yet-started lane and assign it the **same attempt
  ordinal** — and §7's delimiters distinguish attempts, not writers, so two interleaved streams under
  one ordinal are indistinguishable at assembly. That is the one failure the attempt machinery cannot
  absorb, which is why the check is on every append rather than only at adoption.
- **A stale lease is therefore never fatal, and never a silent double-write**: the worst case is that
  a merely-slow run is fenced out and must be re-run, which is visible and recoverable, rather than
  two runs quietly interleaving records into one artifact.
- **`heartbeat_at` must not move backwards, and must not run away forwards.** A clock adjustment that
  rewinds it would make a live run read stale, so a refresh writes `max(now, previous)`. But
  `max(now, previous)` alone preserves a timestamp written during a *forward* jump that is later
  corrected — and since liveness only tests `now - heartbeat_at < 5 minutes`, a future timestamp
  keeps the lease live for the whole skew interval **even if the process has since crashed**, so
  every `--resume` refuses an abandoned run indefinitely. That is the worse failure of the two,
  because the backwards case costs a re-run and this one costs the artifact.
- So liveness is **two-sided**: the lease is live when
  `-skew_grace_s ≤ now - heartbeat_at < stale_after_s`, both read from the lease (`skew_grace_s`
  defaults to 60). A heartbeat further ahead than the grace is not evidence of life — it is a clock
  artifact — and the lease is classified **stale**, with the skew reported so the operator sees why.
  Both bounds are needed: the lower one keeps a corrected clock from pinning a dead run live, the
  upper one is the ordinary staleness test. `run-state.test.sh` carries a negative test for the lower
  bound specifically: it deletes that branch from a copy of the script and asserts the future
  heartbeat then reads `live`, because a bound whose removal changes nothing is not a bound.

The thresholds travel in the lease rather than in an implementation's head because "live or
abandoned" is a classification two readers must reach identically or `--resume` is nondeterministic.

| # | Assertion |
|---|---|
| 3.1 | Two applying runs launched concurrently against one target: exactly one proceeds, the other exits non-zero naming the holder. |
| 3.6 | `--resume` against a run whose lease was refreshed within the threshold exits non-zero naming the run id, and the live run's partial artifact is byte-identical afterwards. |
| 3.7 | `--resume` against a run whose lease has not been refreshed past the threshold adopts the artifact, increments `owner_epoch`, and refreshes the lease itself. |
| 3.8 | A holder whose lease was adopted while it was suspended writes nothing into the adopter's epoch file: any append it still makes lands in its own superseded epoch file, and the adopter's file contains records from exactly one writer per attempt ordinal. It aborts at its next heartbeat refresh, which bounds how long it keeps writing but is not what provides the isolation. |
| 3.9 | A lease whose `heartbeat_at` is further in the future than one refresh interval is classified stale and is adoptable, with the skew reported — a forward clock jump cannot make an abandoned run permanently unresumable. |
| 3.10 | A run that exits cleanly leaving a lane incomplete writes a `released` lease, and an immediately following `--resume` is accepted rather than refused as live. |
| 3.11 | A fenced writer's appends land in `findings.partial.<its own epoch>.jsonl` and never in the adopter's; assembly reads only the highest epoch present, and superseded files are retained. |
| 5.4 | A lane whose delegate reported no catalog version or prompt digest re-runs on every `--resume` rather than being carried forward, and the delegate is named in the report's coverage notes as owing a detection declaration. |
| 6.1d | The scan baseline is computable on a worktree containing an untracked directory: paths come from `git status --porcelain --untracked-files=all`, so no `git hash-object` is attempted on a directory. |
| 3.2 | Two read-only runs launched concurrently both complete, and their derived identity sets are equal. |
| 3.3 | A run launched from a subdirectory produces the same state key as one launched from the root. Working directory is never an input. |
| 3.12 | On a platform supplying no process start identity, a second applying run against a lock older than 30 minutes whose holder's lease is still live refuses non-zero, naming the holder's run id and `heartbeat_at`, and does not reclaim. The holder's `--fix` completes and 3.1 holds across the whole run, not only its first 30 minutes. |
| 3.13 | The same lock, once the holder's lease has gone stale by the two-sided test — or is `released`, missing, or unreadable — is reclaimed by the next applying run, with the reclamation reported. A crashed holder therefore blocks for at most the liveness threshold past the age bound, never permanently. |
| 3.14 | On a platform supplying no process start identity, a lock written before this rule, carrying no run id, is not reclaimed on age while any lease under `runs/<state-key>/` is live by the same two-sided test: the second applying run refuses, naming the live lease. With no live lease under the state key, the age bound reclaims as it did before. Where a start identity is available, the same lock is decided by the pid-and-start-identity test instead, and an unrelated live lease does not defer it. Upgrading mid-run therefore never hands a live holder's lock away. |

## 5. Mid-run resumability

A pass over a large corpus plus three scopes can be interrupted by compaction, a rate limit, or a
crash. Restarting from zero wastes the run and tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — never buffered to the end.
  The write is
  `scripts/run-state.sh partial append --run-dir <run-dir> --record '<json-line>' --epoch <held>`,
  which appends one line to `findings.partial.<epoch>.jsonl`. A lease must exist, so the partial
  cannot outlive the thing that classifies it.

  **Pass the epoch you hold.** The filename is the *writer's* epoch, never whatever the lease
  currently carries: a stale holder that wakes after an adopter incremented it would otherwise read
  the adopter's value and append into the adopter's file, so two writers interleave under one attempt
  ordinal — the one failure the attempt machinery cannot absorb. When the two differ the script says
  `FENCED` on stderr and writes to the writer's own file; the run aborts on that signal. Omitting
  `--epoch` falls back to the lease's current value, correct only for a run whose epoch nothing has
  moved.

  **A record is validated, not merely sniffed.** A malformed row in an append-only artifact is
  permanent, and resume and assembly are its only readers, so a quoting slip in the caller would cost
  the run's persisted state rather than one record. The script refuses anything that is not a
  well-formed single-line JSON object — `jq` decides where it is installed, and a scan that tracks
  string context and escapes decides where it is not, which still rejects `{bad json}`, a truncated
  row, and an unbalanced one. `jq` is deliberately not a hard requirement here: failing the state
  path closed on a missing optional tool would cost the artifact the check exists to protect.
- **The run manifest is the partial's own lane records, not a second file.** A lane's start record
  carries the lane id and its **input digest**; its terminating record carries the completion state.
  §7 already requires that `--resume` read the partial "so completion state is derivable from the
  artifact rather than tracked beside it and able to disagree with it" — a manifest written beside the
  partial is exactly the thing that can disagree with it, so there is one artifact and the manifest is
  a view over it. This also removes the second broken link in the resume path: making the partial real
  while leaving completion state in a file nothing writes would have moved the defect rather than
  fixed it.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash,
  **plus its detection configuration** — the lane's detection version (catalog version and the
  check's prompt digest), the harness version, and every behavior-affecting argument the resumed
  invocation carries, `--opinion` among them.
- **A file-only digest is what makes a resume mix configurations.** Update a delegated plugin or
  catalog between the interruption and the `--resume`, or resume with a different `--opinion`, and the
  audited files stay byte-identical — so completed lanes are carried forward from the old detection
  configuration while unfinished lanes run under the new one, and the assembled report presents one
  resolved version over findings produced under two. That is worse than restarting, because the
  report looks coherent. Including the configuration means such a resume re-runs the affected lanes
  instead of blending them.
- **What the pass may hash is bounded by what the delegate reports, and the gap is closed by
  re-running rather than by reaching in.** This pass dispatches skills and never reads inside one, so
  a delegate's catalog version and prompt digest are available only if that delegate *emits* them —
  and today none does: `claude-memory:audit` takes an action verb and returns findings and counts.
  Requiring metadata no interface supplies would make the rule unimplementable, and hashing it by
  reading another plugin's files would break the boundary the whole design rests on. So each lane is
  classified by what its own delegate returned:
  - **Detection-qualified** — the invocation reported its catalog version and prompt digest. Both go
    into the input digest, and the lane resumes normally when they are unchanged.
  - **Detection-unqualified** — the invocation reported neither, the state of every delegated catalog
    today. The lane is **not resumable**: it re-runs on every `--resume`, and the report's coverage
    notes name that delegate as owing a detection declaration.

  Fail-closed, and deliberately the expensive direction: re-running a lane costs tokens, while
  carrying one forward across an unobservable catalog change produces a report mixing two rule sets
  and presenting them as one. The observable half — the plugin's own semver from the marketplace
  manifest, and the harness version, which are the pass's own to read — is still recorded, so the
  report can say *what changed* even where it could not have prevented the mix. The upgrade path is a
  change to the delegated interfaces, not to this pass, and it is the same declaration `claim`
  templates already ask of them.
- **Resume** re-runs only lanes that are incomplete, detection-unqualified, or whose input digest has
  changed. A lane whose digest is unchanged, whose state is complete, and which is
  detection-qualified is skipped and its findings carried forward.
- A re-attempted lane appends a **supersession record** and opens a new attempt, per §7. Attempt
  boundaries are what let an interrupted re-attempt be discarded deterministically.

| # | Assertion |
|---|---|
| 5.1 | Kill a run after lane *k* completes, resume, and the final report equals an uninterrupted run's over the same tree. |
| 5.2 | Modify one file belonging to a completed lane, then resume: that lane re-runs and no other completed lane does. |
| 5.3 | Invalidate a completed lane on resume, kill its re-attempt after it has appended findings but before its terminating record, then resume again: the abandoned attempt's rows appear in neither the assembled report nor any later attempt's carry-forward, and no finding is duplicated. |
