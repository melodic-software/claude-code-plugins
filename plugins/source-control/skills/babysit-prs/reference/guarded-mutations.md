# Guarded mutations: deterministic gates, agent judgment

The per-mutation gate catalog for `/source-control:babysit-prs`
([`../SKILL.md`](../SKILL.md)). Every mutation the skill may attempt is gated by a deterministic
precondition the script checks, then by the agent judgment the resolved tier permits. This file
owns the gate list, what each gate reads, and the failure disposition when a gate cannot be
evaluated.

The two mutation gates are invoked ONLY through their wrapper scripts, by the bundled `bin/`-path form,
never the bare command name nor the raw Python behind them. Each `source-control-babysit-<x> …` spelled in the bullets below is that wrapper launched by its `bin/`-path form; the exact form is the single
home in [reference/safety.md](safety.md). Both fail closed without `--allowed-owners`.

- **Merge readiness**. `source-control-babysit-merge owner/repo#N --allowed-owners
  <watched-owners> --self-logins @me,<self-logins>` (read-only; add `--merge --expected-head
  <vetted-head-sha>` to merge, and `--method <merge-method>` when configured). `--self-logins`
  exempts your own PRs from the unprotected-base hold **on the default branch only**: `@me` resolves to your gh login, plus any
  `babysit_self_logins` extras (drop the trailing `,<self-logins>` when that value is empty). It gates on GitHub's own
  `mergeStateStatus == CLEAN` plus explicit cross-checks (branch rules, review decision,
  unresolved threads, check rollup keyed by check type and name, head match) and reports the
  exact `blockers`. When `babysit_review_bot_logins` and `babysit_review_settle_minutes` are both
  set, append `--review-bot-logins "<value>" --review-settle-minutes "<value>"` on every form: the
  gate then holds a head that reviewer has not reviewed yet until the window elapses, because
  `CLEAN` is reported throughout a re-review's latency and merging inside it merges past findings
  that have not landed (safety.md, §Review-Settle Hold). Supply both or neither, either alone is
  a usage error, never a silently inert flag. If the expected-head pin is missing or no longer matches the live head, the
  gate refuses the merge; re-snapshot and reassess the new head instead of using
  `--allow-unpinned-head`, the wrapper rejects that flag outright, so no unattended unpinned
  merge exists. The pin is carried to GitHub's server-side match-head-commit guard. It refuses
  a dependency-manager-authored PR absent `--allow-dependency` (held set: built-in dependabot/renovate
  plus any `babysit_extra_dependency_manager_logins`, which you MUST append via
  `--extra-dependency-manager-logins "<value>"` when set, see safety.md's merge command forms, or
  those extra bots are silently not held), refuses merge on an unprotected
  base (zero required reviews and zero required contexts) for a non-self author, and for a self
  author whenever that base is not the repository's default branch, a stack layer or any other
  feature-onto-feature merge, where the default branch's required checks never governed the merge,
  absent `--allow-unprotected`, never uses `--admin`, and cannot resolve threads, reply, or
  force-push. React to `blockers`; do not bypass the gate. A `ready:false` immediately following a `ready:true` on the same expected head is often GitHub's own mergeability recompute lag. Re-run the read-only check once before treating it as a real block. **This gate's `ready` field is the sole authority for calling a PR merge-ready**, never the finding-classification gate's `READINESS_OK` ([reference/safety.md](safety.md) "Two Gates, One Merge-Ready Authority").

- **Once ready, stop.** When the gate proves a PR ready (safe mode) or its merge is deferred to
  a human (Pinned-Command Degradation, [reference/safety.md](safety.md)), report that
  outcome and end the PR's cycle. The no-background-monitor clause (Worker Contract,
  [reference/orchestration.md](orchestration.md)) governs this gate-completion step
  exactly as it governs a worker's turn. Proving readiness is never a license to arm a watch.

- **Thread resolution**. `source-control-babysit-resolve-thread owner/repo#N --allowed-owners
  <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins>` (lists by
  default; add `--resolve`). By default it touches only bot-authored threads (structural
  `__typename == "Bot"` or the `[bot]` login suffix, no hardcoded identity list) and never a human
  thread; `--extra-bot-logins` extends that set with the configured non-structural bot accounts (dropping it silently reclassifies their threads as human), and `--self-logins` rides on every form too, omitting it lets the worker's OWN bot-thread reply flip `botOnly` false and strand the thread outside every resolution scope (safety.md). In worker tier pass `--autonomous`, which
  resolves only threads GitHub marks `isOutdated`, each pinned via `--expected-comment-count` and
  `--expected-last-updated`. Those pins enforce comment-state only. They block a thread whose
  comment count or latest comment-edit timestamp drifted after vetting. The worker must additionally
  confine resolves to threads already outdated in the PRE-push snapshot
  ([reference/orchestration.md](orchestration.md)); that pre-push-outdated rule is agent
  discipline, not machine-enforced, so a thread a worker's own push merely displaced (`isOutdated`
  flipped while both comment pins still match) is still resolvable, the machine-enforced fix for
  that displacement bypass is tracked in #571. In autopilot pass `--resolve --include-human` for
  threads the agent has addressed; the script still cannot merge, reply, or dismiss reviews. Never
  treat exit code 0 alone as proof a specific thread was resolved. Always parse the per-thread JSON
  `action` field (`resolved` vs `skipped-*` / `refused-stale-pin` / `resolve-failed`) and the
  `resolvedCount`/`eligibleCount` summary before reporting or re-checking the merge gate. `--resolve
  --thread-id` without matching `--expected-comment-count` and `--expected-last-updated` (or an
  explicit `--allow-unpinned-thread` override) is refused before anything is fetched or resolved.

- **Independent resolution**. `--independent-resolver` is a THIRD mode, parallel to `--autonomous`
  and never a relaxation of it. `isOutdated` means the referenced code moved, so on a prose or
  documentation PR a genuinely addressed finding never becomes outdated and the worker guard refuses
  forever. This mode is dispatched to a FRESH context that is not the merging worker and did not
  author the fix, that independence is what replaces `isOutdated` as the anti-self-certification
  property, and the script cannot verify it, which is why the other half is machine-checked. Pass
  one `--thread-id` (bulk refused in every mode here, list included), both pins, and
  `--disposition fixed|deferred|incorrect` with its own evidence flag: `--fix-commit <sha>` must be
  reachable from the PR head, `--tracker-item <id>` must exist and be open, `--counter-evidence
  <text>` must already appear in a reply on the thread posted by someone OTHER than the thread's
  opener. The script validates evidence against the world, not against the claim, in list mode too
  anything missing, unparsable, or unverifiable refuses with its own `refused-*` action rather
  than warning, and only a confirmed HTTP 404 is read as the world saying no. A thread carrying
  more than one finding is refused outright (`skipped-multi-finding-thread`) and escalates: one
  disposition cannot clear a thread whose other findings nothing validated. Bot-only and the
  security/P1 bright line still hold, and `--autonomous`, `--include-human`, and
  `--allow-unpinned-thread` are all refused alongside it. Who dispatches this mode, the per-finding
  D7.5 ledger owed before the wrapper is called, the fresh-pin rule, and the fail-closed fallback
  for every bound it cannot cross are the single home in
  [reference/independent-resolution.md](independent-resolution.md).

- **The agent** decides severity (is this security/P1?), whether a finding is genuinely addressed,
  what a label means, and every fix-vs-escalate call, never a script. Escalate a security/P1
  thread instead of resolving it, in every tier and mode and with no exception, the wrappers refuse
  a severity-flagged thread whoever asks (`safety.md`, "Security/P1 escalation has no exception").
