# Independent resolution dispatch

The route a **current** bot review thread takes once its finding is addressed but the addressing
context is not allowed to retire it. This file is the single owner of that contract; callers name
when they dispatch and what bounds their own tier adds, and point here for how the dispatch runs.

## Why a dispatch exists at all

`babysit_resolve_thread.py --autonomous` resolves only a thread GitHub reports `isOutdated`,
because that is the one deterministic "addressed" signal it can check — otherwise the actor is, in
the script's own words, "signing its own permission slip" on the merge gate's zero-unresolved-threads
predicate. The Worker Contract (`orchestration.md`) is tighter still: pre-push outdatedness only.

Two eligible D7.5 dispositions (`reference/review-discipline.md`) leave a thread **current** by
construction, so neither can ever satisfy either guard:

- `INCORRECT` with counter-evidence — a disproved finding ships no fix, so nothing moves the anchor.
- `VALID (defer)` grounded per D4.6 — the fix is deliberately not in this PR.

A prose fix does it a third way: rewriting elsewhere in the file addresses the finding without
moving the anchored lines.

Widening `--autonomous` is the wrong answer — it deletes the anti-self-certification property for
exactly the actor it was written to constrain. The property being preserved is **the context that
authored the evidence is not the context that acts on it**, and `isOutdated` was only ever the
cheapest available proxy for it. This dispatch keeps the property and drops the proxy: a fresh
context that authored neither the fix nor the counter-evidence, and is not the context trying to
merge, adjudicates the disposition and resolves through the guarded wrapper's
`--independent-resolver` mode (`safety.md`).

## Who may dispatch

A context that holds the PR's worker lease and is **not** the context whose merge the resolution
unblocks. Two callers today:

- `babysit-prs`'s orchestrator **in a thread-resolving tier** (`worker`, `autopilot`), for a thread a
  fix worker reported as addressed-but-unresolvable (`orchestration.md`, Main Agent
  Responsibilities). This is the ordinary worker-tier route. The **safe tier never dispatches** — it
  never resolves threads (`SKILL.md`), and dispatching a resolver would resolve one at one remove.
- `babysit-loop`'s explicit-`autopilot` pre-escalation dispatch, which adds its own widening-only
  bounds (`skills/babysit-loop/reference/pre-escalation-dispatch.md`).

## The independence contract

Independence is a property of the **dispatch**, not a credential the dispatched agent presents, and
no script can verify it — which is precisely why the evidence half is machine-checked. A run that
cannot establish it escalates rather than dispatching.

- **A fresh subagent.** It shares no conversation history with whatever produced the PR, with the
  worker that fixed it, or with any context that previously replied on the blocking thread. A
  continuation of the authoring session, or a re-invocation of the subagent that already commented
  on the thread, never qualifies regardless of what it claims about itself.
- **Never the merging context.** The dispatching orchestrator does not resolve the thread itself.
  It holds the merge decision, so adjudicating its own unblock is the same self-satisfaction one hop
  up.
- **Evidence is read from the world, not from the brief.** The brief names the thread and the
  claimed disposition; the dispatched agent re-derives the evidence at the live head — the
  counter-evidence read from the code or docs, the tracker item re-queried, the fix commit confirmed
  present. `verify_counter_evidence` only requires the text appear in a reply by someone other than
  the thread's **opener**, so a worker's own reply under a `--self-logins` identity is admissible
  input to the wrapper. Passing the worker's asserted evidence string straight through would make
  the dispatch a laundering hop rather than an adjudication.

## The D7.5 verification ledger, per finding, before the wrapper is called

The guarded wrapper checks authorship, severity, comment-state pins, and the evidence's existence in
the world; it cannot check whether a finding was actually **addressed**. Without a ledger the
dispatched agent could resolve a current thread over an unaddressed finding and clear the merge
gate's zero-unresolved-threads predicate — the same self-satisfaction the worker-side outdated-only
guard exists to prevent, moved one hop.

Extract every finding in the thread (one comment carrying N findings is N work items) and record for
each one the disposition plus its evidence:

<!-- contract-restatement-begin: D7.5-thread-eligibility -->

- `VALID (fix now)`: the pushed commit SHA that fixes it, verified present on the live PR head, and
  the D7 follow-up citing it.
- `VALID (defer)`: grounded per D4.6 — the provenance test passed (the defect reproduces on the base <!-- contract-restatement-begin: D4.6-deferral-grounding -->
  branch), and the tracker item exists, carries the finding's own evidence, and its cited id
  re-queries successfully. <!-- contract-restatement-end: D4.6-deferral-grounding -->
- `INCORRECT`: the counter-evidence, read from the code or docs at the live head rather than
  asserted.
- `UNCERTAIN`: not resolvable. It escalates, and so does the thread.

**Every** finding in the thread must hold an eligible disposition; one addressed finding never makes
the thread eligible while a sibling finding is open, because a resolved thread drops all of its
comments from the readiness count. Any finding the dispatched agent cannot verify to this standard
means **no resolution**. The ledger is reported back with the dispatch result, so what was verified
is inspectable rather than asserted.

<!-- contract-restatement-end: D7.5-thread-eligibility -->

## Read the pins fresh; never forward the dispatch snapshot's

The pins the worker was dispatched with are **pre-reply**. The worker's own mandated D5
classification reply moves both `commentCount` and `lastCommentUpdatedAt`, so forwarding them
produces `refused-stale-pin` deterministically. List the thread first, take
`commentCount` and `lastCommentUpdatedAt` from that output, then resolve on those values — the same
thread-pin pair rule `safety.md` states for every pinned resolve.

List mode validates the evidence too, so the list call proves the evidence rather than predicting
the resolve:

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --independent-resolver --thread-id <id> --disposition incorrect --counter-evidence "<verbatim text from a reply on the thread>"
```

Then resolve on the pins that call reported:

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --independent-resolver --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts> --disposition incorrect --counter-evidence "<verbatim text from a reply on the thread>"
```

Swap the disposition pair for the claim actually being made: `--disposition deferred --tracker-item
<owner/repo#N>`, or `--disposition fixed --fix-commit <sha>`. Exactly one evidence flag is
admissible per disposition; a mismatched or surplus flag is a usage error before any lookup.
`--self-logins` is not optional here — omit it and the worker's own reply flips `botOnly` false and
the thread returns `skipped-human-thread`. Parse the per-thread `action` field; a thread is cleared
only when its own entry reads `"action": "resolved"`.

## Bounds the dispatch does not cross

Each of these leaves the thread **unresolved**, and the fail-closed fallback is identical in every
case: **leave the thread unresolved, do not merge, and report the PR with the
addressed-but-unresolvable thread named.** An unreachable or refused authorization is never a licence
to self-resolve, and never a reason to reach past the wrapper to raw `resolveReviewThread`.

- **Security/P1 threads.** `--independent-resolver` retains the severity bright line
  (`skipped-severity-marked`): "never a security or P1 thread" is unconditional on every unattended
  path, and no evidence buys past it. The scan keys on **structured** markers — shields badges and
  bracketed `[P0]`/`[P1]` — not prose mentions of P1 in a P2 thread's body (#1939). Vetted
  `--resolve --thread-id` (with TOCTOU pins) applies **no** severity screen; it trusts the calling
  agent's vetting. That asymmetry is deliberate. This is a bound of **the mode**, not of the callers. It is
  terminal on the `babysit-prs` orchestrator route, whose only resolve form for a current thread is
  this mode — such a thread escalates. `babysit-loop`'s widening carries the one named exception
  (`safety.md`, Security/P1 escalation), and which guarded form that exception uses is its own
  contract's call, not this file's: this file governs the mode and the discipline every dispatch
  owes, and it neither widens nor narrows what a caller's tier already permits.
- **Multi-finding threads.** Refused outright (`skipped-multi-finding-thread`): one disposition is a
  claim about one finding, while resolution clears the whole thread. An unknown count — a truncated
  comment page could hide another finding — refuses the same way.
- **Unpinned or bulk resolves.** A single pinned `--thread-id` carrying both TOCTOU pins is the only
  admissible shape; bulk resolves and `--allow-unpinned-thread` are refused alongside this mode.
  Everything `--autonomous` guards other than `isOutdated` still binds.
- **Human-authored threads.** `--include-human` is refused alongside this mode. A human closes their
  own thread.
- **Evidence the world rejects or cannot confirm.** Every `refused-*` action refuses the resolve.
  `refused-evidence-unverifiable` means the API could not be consulted — retry, never replace the
  evidence.
- **No subagent tools, or a non-resolving tier.** There is no dispatch without an independent
  context to dispatch to, and the orchestrator never substitutes itself. The safe tier makes no
  dispatch at all.

## Lease and sequencing

The dispatch always runs **under the PR's worker lease** — never unleased. The guarded wrappers pin
comment state, not concurrency ownership, so the lease is the only thing keeping a second actor off
the PR. Which context holds it differs by caller, and the two are not interchangeable:

- **`babysit-prs`'s orchestrator already holds the lease** for the whole of that PR's cycle, and
  `orchestration.md`'s Cleanup releases it at the end of integration. The dispatch fires **inside**
  that held lease, before Cleanup — the dispatched subagent operates under it and acquires nothing
  of its own. Attempting an acquire here would refuse against the lease its own dispatcher holds.
- **`babysit-loop`'s pre-escalation dispatch holds no lease** when it fires, so it acquires and
  heartbeats before the subagent starts and releases after, exactly as any per-PR fix or worker
  assignment requires (`safety.md`, `orchestration.md`). A lease another worker already holds means
  no dispatch at all.

**A blocker needing a code change runs the full per-PR worker lifecycle** — isolated PR worktree,
HEAD asserted at the live PR head, commit and refspec push (`safety.md`) — not the wrappers alone,
which implement merge and thread resolution and create no worktree; a lane launched from a neutral
directory has no usable tree without it. This applies to a caller whose dispatch may push code,
which `babysit-loop`'s does. It does not arise on the `babysit-prs` orchestrator route: there the fix
already landed through the ordinary worker, and what remains is a current thread to adjudicate, so
that dispatch resolves and never pushes.

## After the dispatch

Re-snapshot the PR before anything acts on the result. A resolution that pushed code can have moved
the head, and a merge-capable caller re-runs its own class partition on the post-push diff before
any merge — the verdict authorizes a head SHA, not the PR. If the dispatch cannot resolve the
thread — including any case where the dispatched agent is itself uncertain the resolution is
correct — the fail-closed fallback above applies unchanged. This dispatch adds one resolution
attempt; it never removes an escalation path or lowers a gate's bar.
