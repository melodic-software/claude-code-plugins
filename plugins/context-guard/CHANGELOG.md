# Changelog

All notable changes to the `context-guard` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.17]

### Added

- **The cloud/headless capture verdict is now a shipped reference, and `unknown` there is documented
  as structural (#2957).** The snapshot rides the statusline tee, so a session with no configured
  `statusLine` has no instrument at all — cloud and headless sessions by default. Measured in a live
  Claude Code on the web container on 2026-08-21: no `statusLine` in any settings scope, no
  `<session_id>.json` snapshot, and `context-zone.sh` answering `unknown`. One correction to the
  reported symptom, and it is the finding the rest rests on: `~/.claude/context-guard/` *does* exist
  there, created by the `PostCompact` hook — plugin hooks run fine in cloud, only the statusline
  writer is silent, which is why hook stdin was the first channel checked. New
  `reference/cloud-headless-capture.md` records the writer-side channel inventory: every channel
  checked with its live URL and the date read (all 2026-08-21), what each does and does not carry,
  and what would have to change upstream. **Verdict: no documented channel other than the status
  line carries per-session context-window telemetry.** Hook stdin carries `session_id`, `prompt_id`,
  `transcript_path`, `cwd`, `permission_mode`, `effort`, `hook_event_name` and event-specific
  fields, and no context, token, usage, or window field on any event. Also rejected with the reason
  recorded: `subagentStatusLine` (subagent rows only, and itself a status-line surface),
  non-interactive JSON/stream output (per-invocation and after the fact), OpenTelemetry (a
  cumulative token counter, no occupancy gauge), and the session transcript — reachable from every
  hook through the documented `transcript_path` and carrying exactly the right numbers, but its
  entry format is documented as internal and version-unstable, so a capture built on it would
  warrant a zone with nothing and would break on a Claude Code release rather than on a change here.
  A wrong zone is strictly worse than `unknown`.

### Changed

- **`reference/reader-contract.md` tells consumers how to report a missing instrument (#2957).** A
  new cloud-and-headless section states that `unknown` in a session with no configured `statusLine`
  is structural and permanent, to be reported as "no instrument in this environment" and never as a
  defect or a broken install; that no zone may be synthesized from another source, naming the two
  reachable near-substitutes and how each fails toward a confident wrong answer; and that `unknown`
  carries no direction, so a fork or handoff trigger in such a session must come from somewhere else
  and must not be presented as instrument-backed. It also gives the discriminator the previous text
  lacked: structural absence and a broken install both print `unknown`, and only the writer side
  separates them — read `statusLine` from every scope that can carry it.
- **`/context-guard:setup` `check` stops prescribing a remediation that cannot work (#2957).** No
  `statusLine` in a session that refreshes none is now INFO with the structural explanation instead
  of printed wiring the operator cannot make run, and an absent snapshot with no `statusLine`
  configured anywhere is INFO rather than the FAIL branch that assumes correct wiring.

## [0.7.16]

### Added

- **The auto-compact configuration surfaces and their interplay with zones are now documented
  (#2995).** `reference/reader-contract.md` said no auto-compaction threshold is documented and
  stopped there, which left readers with the impression that the trigger is entirely opaque. The
  *default* is unpublished, but the trigger is operator-tunable, and none of the surfaces that tune
  it appeared anywhere in the plugin. The contract now names all four — `autoCompactWindow`
  (`settings.json`, 100,000–1,000,000 tokens, no numeric default), `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  (environment, highest precedence, plain integer only), `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
  (percentage of the window, lower-only), and `autoCompactEnabled` / `DISABLE_AUTO_COMPACT` —
  verified 2026-08-17 against two independent pools (the official settings reference and the shipped
  binary's schema strings) and re-verified 2026-08-19 against the live settings, env-vars, and
  model-config pages. Added with them: the **bands-below-the-trigger** rule and its rationale
  (a firing means the boundary decision was reached too late), the explicit position that
  auto-compact nonetheless stays *enabled* as a last-resort safety net because unattended sessions
  have no human at the boundary, and the vendored Boris §64 rot figure recorded as a named
  practitioner anchor — carrying its Opus 5 amendment — never as an adopted number. The README
  points at the contract for all of it. Documentation only; no behavior change.
- **The trigger comparison is stated in the percentage shape, not occupancy.** The contract already
  forbids equating its two zone shapes without normalizing; the new guidance now honors that rule
  explicitly. A configured auto-compact window is a fill threshold in the percentage shape's
  input-token accounting, not the token shape's occupancy, so the worked example normalizes: a
  400,000-token window on a 1M-class model puts the trigger at 40% of the full window — inside the
  shipped `smart` band, meaning auto-compact fires while every zone still reads green. Records the
  docs' own consequence with it: `used_percentage` always measures against the model's **full**
  context window, so a lowered auto-compact window stops being visible in the percentage at all.

### Changed

- **The "no documented threshold" paragraph carries a dated refinement.** Upstream is now more
  specific than the "when approaching context limits" phrasing the paragraph quotes: with no window
  configured, compaction fires at the model's context limit, with enumerated exceptions that fire
  earlier (cloud sessions, 200K-boundary model/configuration combinations, unrecognized model IDs,
  and Sonnet 5 at "about 967K tokens by default" on its 1M window). That Sonnet 5 figure is the one
  published number in the set; at ~97% of the window it sits well above the shipped `dumb` band, so
  it is recorded as context rather than as a reason to move the bands. A percentage default is
  implied by `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` but still unpublished as a number, so the conclusion
  is unchanged — the bands stay declared judgment defaults — while the trigger is now documented as
  model- and environment-dependent, which is why no single band set is correct everywhere. Verified
  2026-08-19.
- **The evidence-degraded marker's `trigger` field now has consumer guidance.** The field's values
  were documented; what a consumer should *do* with them was not. The contract now states that
  consumers deliberately do not differentiate on `trigger` (evidence degradation is
  trigger-independent) and records the track-on-event condition under which that stance would be
  revisited, with the recorded field as its observable.

## [0.7.15]

### Fixed

- **`reference/reader-contract.md` described pre-0.5.0 advisory injection (#2973).** The
  zone-crossing hooks section still called the injection "a minimal generic continuation tree plus
  a presence-gated pointer to `session-flow:workflow`'s router", as one undifferentiated block —
  the shape before the 0.5.0 audience split moved the menu off the model channel. The reference
  therefore misdescribed shipped behavior to every reader of the seam. It now states what each
  channel carries — `additionalContext`: the determination plus the counter-steer, and the
  durable-note addendum in `dumb`; `systemMessage`: the same crossing plus the continuation menu
  and the router pointer — that neither the menu nor the pointer ever reaches the model channel,
  and the I23 rationale for the split. Verified against `hooks/zone-crossing-inject.sh`'s actual
  emission rather than its header summary. Documentation only; no behavior change.

## [0.7.14]

### Changed

- **Both zone-crossing message channels compressed** (owner report: the operator message was
  overly verbose). The operator `systemMessage` drops from 908 to 460 characters — measured with
  `LC_ALL=C.UTF-8 wc -m` on the template literal before interpolation, trailing newline excluded.
  The locale matters: these strings carry multibyte punctuation (`→`, `—`), so `wc -m` without a
  UTF-8 locale silently counts bytes and reads 914 → 470 instead. The shape:
  menu-first, one clause per option, keeping the four continuation options, the `zones.json`
  tunability pointer, the `/session-flow:workflow` router, the test-pinned "yours to choose"
  ownership phrase, and the "(if installed)" hedges. Option 3 also keeps a terse manual
  alternative — "or a hand-written resume note" — because context-guard installs standalone: a
  menu whose only durable-state path names an absent plugin leaves such an install with no
  actionable option at exactly the moment state must survive. That clause is now **contract-pinned
  by its own assertion** rather than left to the menu check: naming `/session-flow:handoff` and
  offering something a solo install can act on are different properties, and the menu assertion
  passes on a menu that has become unactionable. This clause was dropped once with the whole suite
  still green, which is the case for the separate pin. Dropped: the snapshot-seam
  provenance parenthetical and the vendor-variance hedge. The model-channel `additionalContext`
  gets the matching conservative trim
  (737 → 552 characters, or 973 → 733 with the dumb-zone addendum appended, same measurement):
  all four semantics survive verbatim where the contract test pins them —
  measurement-not-instruction, "Do not volunteer", "operator's call", and the dumb-zone
  durable-notes rider — and the "crossed from the <previous>" phrasing stays for the
  partial-write recovery assertion. The evidence-degraded label shortens to
  "dumb (evidence-degraded: this session was compacted)". No behavior change; the two-channel
  contract (menu to operator only, counter-steer to model only) is untouched and the full test
  suite passes unchanged.

## [0.7.13]

### Changed

- Sync `hook-utils.sh` from `lib/` — two header-echo comments removed in
  `hook::emit_telemetry` (comment-only; no behavior change).

## [0.7.12]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.7.11]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.7.10]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.7.9]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.7.8]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.7.7]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.7.6]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811).

## [0.7.5]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.7.4]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.7.3]

### Fixed

- **The 0.7.1/0.7.2 collision is now on the record, and one claim that was never executed is
  withdrawn (#2355).** Two PRs fixed the same defect in parallel and both landed: #2344 shipped
  **0.7.1**, re-arming on a **dwell** (three consecutive strictly-better observations), and #2345
  shipped **0.7.2**, re-arming on a **return to `smart`**, replacing the dwell implementation
  wholesale. The behaviour on `main` is 0.7.2's and it is tested — but the record of the swap was
  lost in the collision, so this release repairs the record. Documentation and tests only: **no
  behaviour change**, and nothing here alters what the suite demands of the hook's logic.

  - **`reference/reader-contract.md` credited the wrong version.** It read "the marker decays only
    when the session returns to `smart` (**since 0.7.1**)". The return-to-`smart` rule is **0.7.2**;
    0.7.1 is the dwell. The sentence was written while the change was still numbered 0.7.1 and the
    reference did not move with the bump. Corrected, and it now names the dwell it replaced.

  - **0.7.2's entry argued only against 0.7.0 and never against the 0.7.1 it superseded — and two
    of its claims are false relative to the version it actually followed.** It was written with
    0.7.0 as the parent, so "the sole behavioural delta is `acceptable → smart` re-arming" and
    "every 0.7.0 assertion still passes unmodified" were verified against 0.7.0 and quietly became
    misleading when 0.7.1 landed first: against 0.7.1's dwell the delta is the whole re-arm rule and
    **13 assertions of this suite differ**, measured against `f57fb788`. Both are scoped in an
    erratum on that entry rather than rewritten. The underlying difference is load-bearing, not
    stylistic: under a three-observation dwell, `acceptable → smart → acceptable` — a genuine
    recovery observed **once** — does not re-inject, which is the exact sequence 0.7.2 exists to
    make re-inject. A dwell wide enough to absorb a band-edge flap cannot also honour a
    single-observation recovery; 0.7.2 chose the recovery and accepted the residual flap at the
    `smart`/`acceptable` edge. That trade is now stated where the two versions meet.

  - **An unverified comparative is withdrawn.** 0.7.2's residual paragraph said the edge cadence was
    "the pre-0.7.0 cadence at that one boundary, and no worse". 0.6.6's hook was never run to
    measure that, so the comparative was reasoned rather than executed, and it is retracted here
    rather than left standing. What replaces it is measured: the cadence is **one announcement per
    down-up cycle**, now pinned by assertions (a second recovery buys a second announcement and no
    more), so "bounded rather than runaway" no longer rests on reading the code.

  - **Cross-version state compatibility is pinned.** 0.7.1 wrote `.armed` with TWO fields
    (`<zone> <streak>`, e.g. `dumb 0`); 0.7.2 writes one word and reads with `tr -cd '[:lower:]'`,
    which strips the digit and the separator. A session that started under 0.7.1 and continued under
    0.7.2 therefore reads back correctly and stays suppressed rather than re-announcing a zone it
    has already reported. That held by construction and now holds by assertion — no migration step,
    exactly as with the 0.6.6 → 0.7.0 legacy-state seed.

## [0.7.2]

**Erratum (0.7.3):** three corrections, and the first two turn on *which version this entry was
written against*. It was authored with **0.7.0** as the parent; by the time it merged the parent was
**0.7.1's dwell**, and two of its sentences are true only of the former:

- "the sole behavioural delta is `acceptable → smart` re-arming" — true against 0.7.0. Against
  0.7.1 the delta is the entire re-arm rule.
- "Every 0.7.0 assertion … still passes unmodified against the new rule" — true, and still true, of
  0.7.0's assertions. It is not a statement about 0.7.1: this suite reports **13 failures** against
  0.7.1's hook (measured against `f57fb788`; the run is in #2364).

Third, the residual paragraph's "(the pre-0.7.0 cadence at that one boundary, and no worse)" was
never executed against 0.6.6 and is **withdrawn**; the measured statement is one announcement per
down-up cycle, now pinned by tests. The rest of this entry — the property, the residual itself, the
corrected mechanism, and the write-ordering fix — stands as written and is tested against the code
on `main`.

### Fixed

- **`zone-crossing-inject`: the armed rank now decays on a return to `smart` rather than after a
  fixed two-rank improvement, because only `dumb` could ever satisfy a two-rank improvement
  (#2343).** 0.7.0 shipped the hysteresis this plugin needed and then applied it with a rule the
  ladder cannot express. Ranks are `smart`=0, `acceptable`=1, `dumb`=2, so from an armed rank of
  `acceptable` the largest available improvement is ONE rank and `armed_rank - new_rank >= 2` is
  **unsatisfiable**. A session that armed at `acceptable` could therefore never re-arm: it could
  recover fully to `smart` and relapse to `acceptable` any number of times and stay silent for the
  rest of its life, unless it first escalated all the way to `dumb`. That is #2220 inverted rather
  than fixed — the flapping session 0.7.0 set out to quiet became a session that never speaks on
  the middle band, and `acceptable → smart → acceptable` was silent while the structurally
  identical `dumb → smart → dumb` re-injected, as 0.7.0's own test proved.

  **The corrected mechanism: a target on the ladder, not a distance along it.** The armed rank now
  decays when — and only when — the session returns to the BEST band, `smart`. Every band can reach
  it, so the rule fires uniformly; a fixed delta cannot, on a scale three ranks wide. Raising the
  constant to one rank was the tempting over-correction and is exactly #2220 again, since
  `dumb → acceptable → dumb` would re-arm on edge noise.

  **The property this guarantees**, stated so it can be falsified: within one arming cycle each zone
  is announced at most once, and only a return to `smart` opens a new cycle — so a genuine recovery
  followed by a relapse re-injects **exactly once for the band it relapses into, from any armed
  band**, and a flap that never reaches `smart` stays silent however long it oscillates. The
  `dumb`-band behaviour is bit-for-bit what 0.7.0 shipped: the old predicate was satisfiable only at
  `armed=dumb, new=smart`, which the new rule also admits, so the sole behavioural delta is
  `acceptable → smart` re-arming. Every 0.7.0 assertion — the flap, the `dumb → smart → dumb`
  recovery, the legacy-state seed — still passes unmodified against the new rule, alongside a new
  `acceptable → smart → acceptable` session that fails against 0.7.0.

  **The residual, stated rather than papered over**: at the `smart`/`acceptable` edge a flap and a
  full recovery are the SAME observation — `smart` is both the far side of that boundary and the
  bottom of the ladder — so a session oscillating there re-announces `acceptable` once per down-up
  cycle (the pre-0.7.0 cadence at that one boundary, and no worse). Rank granularity cannot separate
  the two: this hook sees one word per observation and never the occupancy behind it, because band
  logic lives in `scripts/context-zone.sh` and only there. Closing it needs either a numeric deadband
  below the band edge or a dwell requirement on the improved reading — and a dwell wide enough to
  absorb the flap would also silence the single-observation recovery this fix exists to restore.

- **`zone-crossing-inject`: the emit gate no longer advances when its companion write fails, so a
  warning that was never reported cannot be lost (#2343).** 0.7.0 wrote the `.armed` gate FIRST, on
  the reasoning that a partial write should leave behind the marker that suppresses. That reasoning
  was wrong: suppression is not the safe side when the notice being suppressed was never delivered.
  With `.armed` written first, a failed `.zone` write (a transient FS error, or a directory
  occupying the path) exited without emitting while leaving the gate advanced — and after recovery
  the next identical observation was suppressed by `new_rank > armed_rank`, permanently losing the
  first warning of that zone. The order is now label first, gate second, with the label rolled back
  best-effort if the gate write fails; either failure leaves the gate unmoved, so the session is
  still owed its injection and the next observation issues it. Fail-open-silently and the
  `status=error` telemetry are unchanged; the telemetry payload gains a `marker` field naming which
  write failed. 0.7.0's persistence test created exactly this partial-write state and never retried
  after clearing the obstruction, so it passed while the defect stood — it now retries, on both
  markers.

## [0.7.1]

### Fixed

- **The 0.7.0 re-arm rule permanently silenced the middle band; it now decays on a DWELL rather than
  a rank distance (#2220).** `REARM_MARGIN=2` is satisfiable only from `dumb`: the largest
  improvement available from `acceptable` is one rank, so `armed_rank - new_rank >= 2` could never
  hold there. A session that armed at `acceptable` could never decay again — a full recovery to
  `smart` followed by a relapse stayed silent for the rest of the session, however many times it
  happened, unless the session first escalated all the way to `dumb`. Reproduced against the shipped
  hook side by side with the structurally identical `dumb` sequence, which did re-inject:

  ```
  acceptable -> INJECTED   armed=acceptable        dumb  -> INJECTED   armed=dumb
  smart      -> silent     armed=acceptable        smart -> silent     armed=smart
  acceptable -> silent     armed=acceptable        dumb  -> INJECTED   armed=dumb
  smart      -> silent     armed=acceptable
  acceptable -> silent     armed=acceptable
  ```

  This was **0.7.0's own defect inverted** — never re-inject instead of always re-inject — so the
  fix is not a smaller constant: a delta of 1 simply restores the flap 0.7.0 set out to remove. The
  rule now counts **time instead of distance**. Any observation strictly better than the armed rank
  extends a streak, returning to the armed rank breaks it, and **three consecutive better
  observations** decay the armed rank. A streak is expressible from every rung of a three-rung
  ladder while a two-rank drop is not, so every band now behaves identically: an unsustained dip
  never re-arms, and a sustained one always does — from `acceptable` exactly as from `dumb`.

  The dwell is a declared judgment default on the same footing as the bands themselves
  (`reference/reader-contract.md` records their provenance); nothing here is doc- or
  benchmark-derived. A band-edge oscillation resolves within a single observation as one batch's
  results land and are released, so one better observation is precisely what noise looks like; three
  span more than a full PostToolBatch/UserPromptSubmit cycle, which a session alternating across the
  edge turn by turn never accumulates.

- **The armed gate no longer advances on a turn that emitted nothing, which could lose a warning
  permanently.** 0.7.0 wrote the markers gate-first, on the reasoning that a stale gate merely
  withholds a repeat. That was backwards. If `.armed` landed and the companion `.zone` write then
  failed (a transient full or read-only filesystem, or a directory occupying the path), the hook
  exited without emitting while leaving the gate advanced — so once the filesystem recovered, the
  next identical observation was no longer worse than the armed rank and the **first** warning was
  never delivered at all. Losing the first warning is strictly worse than the repeat the ordering
  was protecting against.

  `.zone` is now written first and `.armed` installed afterwards, all-or-nothing: if either step
  fails the gate is left exactly where it was and the same observation is free to emit on a later
  call. `.armed` is installed by **rename** rather than written in place, because `>` truncates
  before it writes — a failure partway through would otherwise leave an empty marker, which parses
  as no marker, which seeds from a `.zone` already updated to the current zone, suppressing the very
  warning the ordering exists to protect.

### Changed

- **A transition into a zone BETTER than the worst already reported is now silent.** 0.7.0 still
  injected on `dumb` → `smart` → `acceptable`, because a single `smart` observation re-armed the
  ladder outright and `acceptable` was then worse than the armed `smart`. Under the dwell it is
  silent: one observation is not a sustained improvement, so the armed rank is still `dumb` and
  `acceptable` is not worse than `dumb`. The operator has already been told this session reached
  `dumb`; announcing a better zone afterwards is the noise #2220 is about. The pre-existing test
  that asserted the old behaviour was updated rather than deleted, and says so at its site.

### Notes

- **Erratum, not a rewrite — the 0.7.0 entry below keeps the wording it shipped with.** Its
  description of the re-arm rule ("an improvement of at least **two ranks**") is accurate about what
  0.7.0 did; what it does not say is that the rule was unsatisfiable from `acceptable`. The claim it
  makes about `dumb → acceptable → dumb` injecting once remains true. Read it as superseded by this
  entry rather than as wrong (`docs/conventions/upstream-drift/README.md` §Adopters: history is
  never rewritten).
- **The test gap that allowed this is closed at the same time.** 0.7.0's suite exercised only
  `dumb → smart → dumb`, which the rank-delta rule happened to get right; the
  `acceptable → smart → acceptable` path — the one it got permanently wrong — had no case. Case 4d
  now covers that band's flap and its sustained-recovery half on a session of its own. The
  persistence test likewise now clears the obstruction and re-runs the identical observation, which
  is what makes it discriminating; previously it stopped at "it stayed silent", a state a gate that
  had advanced would also have passed.
- `.armed` now holds `"<zone-word> <streak>"` and is parsed field-wise, with both fields validated
  against their own vocabulary so a truncated or hand-edited marker falls back to seeding rather
  than silently disarming the gate. A 0.7.0 marker holds a bare zone word: the streak parses as 0,
  which is exactly the right starting point, so no migration step and no state-format version are
  needed.
- No blocking behaviour, no permission, no new hook registration, and no external read or write
  changes; the plugin's trust surface is untouched.

## [0.7.0]

### Changed

- **`zone-crossing-inject`: the injection gate is now the worst zone this session has already
  REPORTED, not the zone it last SAW — zone bands had no hysteresis, so a session flapping across a
  boundary re-injected on every crossing (#2220).** The bands are hard thresholds and occupancy does
  not climb monotonically: tool results land and are released, so a session sitting near a boundary
  crosses it repeatedly. The old latch compared each observation against the last-seen zone and
  persisted state in both directions, which made every re-crossing a fresh transition — the ~1KB
  (~250 token) guidance block re-emitted each time, with an *improvement* of any size silently
  re-arming the injection and nothing counting or capping the flap.

  A second per-session marker (`<session>.armed`) now holds the worst zone already reported, and the
  emit gate compares against it. It decays only on an improvement of at least **two ranks** — the
  full width of the `smart`/`acceptable`/`dumb` ladder. The margin is a declared judgment default on
  exactly the same footing as the bands themselves (`reference/reader-contract.md` records their
  provenance); nothing here is doc- or benchmark-derived, and the reasoning is stated rather than
  asserted: a one-rank dip at a band edge is the oscillation described above and says nothing new,
  while `dumb → smart` cannot be edge noise. A `/clear` needs no margin — it starts a new session
  id, hence a fresh state file and a fresh baseline.

  Net effect: a zone is announced at most once per session unless the session genuinely recovers,
  after which the ladder re-arms and the next worsening is reported normally. `dumb → acceptable →
  dumb` now injects **once**; `dumb → smart → dumb` still injects **twice**. Both are pinned by
  tests, on separate sessions so the two paths cannot share state.

  A sibling file rather than a second line in the existing one: the state reader is
  `tr -cd '[:lower:]'`, which strips the newline, so two lines would fuse into `dumbacceptable` and
  rank as `smart`. Sessions already running when this version lands have a `.zone` file and no
  `.armed` file; the armed rank seeds from the last-seen zone, so the first call after the upgrade
  decides exactly as 0.6.6 would have and latches from there — no migration step, no state-format
  version. The armed marker is written **first** of the two, so a partial write failure can never
  leave the gate open against a marker that already moved.

  **Not the recurring 10s-timeout defect, and not a duplicate of it.** That one
  (`20260730-182801-context-guard-zone-crossing-hook-times-out-100-percent`) was four `hooks.json`
  registrations declaring `timeout: 10` against measured 10.6–21.4s runtimes, so the hook **died
  rather than ran**; it was fixed in 0.4.8 via PR #2001 by raising all four to 60. This release is
  about how often the hook injects **when it does run**. A triager reaching for that item should
  stop here.

  Deliberately preserved, because they are load-bearing and easy to refactor away: the two-channel
  split with the continuation menu kept out of model context, the hook's refusal to claim an
  operator is present, the inert default posture, the worsening-only latch itself, and
  `zone-gate.sh`'s structural no-deadlock exemptions. No blocking behaviour, no permission, and no
  external read or write changes; the plugin's trust surface is untouched.

## [0.6.6]

### Changed

- **Shared `hook-utils.sh`: the jq gate now has a fail-CLOSED sibling, and the posture reasoning
  lives at the helper (#2146).** `hook::require_jq` is unchanged and still fails OPEN — one visible
  skip notice per session, then exit 0 — which is the correct posture for every hook in this plugin,
  so **nothing in this plugin's behaviour changes**. What is new is `hook::require_jq_blocking`, a
  second named function that denies the tool call instead, for the narrow class of guards whose job
  is blocking an irreversible operation (today only two, both in `guardrails`). A sibling function
  rather than a parameter, because a flag's omitted value would default to fail-open and a guard
  whose flag someone forgot would then fail open *silently* — the exact defect #2146 reports,
  reintroduced at the API. The two postures are now argued together in one block above both
  functions, which is what #2146 asked for: previously each call site asserted a posture in a
  comment and nothing where the decision is made explained it. Synced from `lib/hook-utils.sh`.

## [0.6.5]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.6.4]

### Fixed

- **A cited plugins-reference section had been renamed upstream.** `scripts/statusline-shim.sh`
  attributed the 14-day orphaned-cache-directory grace period to a section called "Plugin cache and
  file access". That section is now titled **"Plugin caching and file resolution"**, and the cache
  root it documents is `~/.claude/plugins/cache`. The behaviour cited is unchanged and still stated
  verbatim; only the section title a reader would search for had moved, which is exactly the kind of
  silent rot that makes a citation unfollowable. The comment now names the current title and records
  the former one so the rename is traceable.

- **The 2.1.132 token-semantics floor no longer has an upstream source, and the reader contract now
  says so.** `reference/reader-contract.md` quoted the statusline page as stating "Before v2.1.132
  these were cumulative session totals". Re-checked 2026-08-10 against the complete raw page
  (`https://code.claude.com/docs/en/statusline.md`, not a summarized fetch): that sentence is gone,
  and with it the version number. What the page still states is only the present-tense semantics the
  floor depends on — "Token counts currently in the context window, from the most recent API
  response" and "**Combined totals** (`total_input_tokens`, `total_output_tokens`): tokens currently
  in the context window". The dead quote is removed and replaced with an explicit sourcing-status
  note; `statusline-tee.sh` carries the same note at its `cli_version` comment. **The floor itself is
  unchanged** — `TOKEN_SEMANTICS_MIN_VERSION` still gates the token shape at `>= 2.1.132`, and no
  behaviour, test, or zone result moves. Dropping it could only widen which payloads the token shape
  trusts, and the misfire it prevents (a pre-2.1.132 cumulative 170k reading as a plausible current
  occupancy) is silent, so it stays as a deliberate conservative lower bound. Re-source it before any
  change that relaxes it.

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each claim below was
  re-checked against the complete raw markdown source of the page it cites, and confirmed by a
  verbatim quote before its stamp was refreshed.

  - `hooks/post-compact-mark.sh` — "PostCompact hooks have no decision control", still stated
    verbatim, which is what makes the hook side-effect-only.
  - `scripts/statusline-shim.sh` — the 14-day orphaned-version-directory grace period, quoted
    verbatim from the plugins reference.
  - `scripts/statusline-tee.sh` — the statusline payload's top-level `version` field carrying the
    Claude Code version.
  - `reference/reader-contract.md` — the `context_window` field list, `current_usage` being null
    before the first API call and again immediately after `/compact`, `used_percentage` /
    `remaining_percentage` being nullable early in a session, and the `${CLAUDE_SESSION_ID}`
    substitution in the skills reference's substitution table. Also the auto-compaction negative:
    no numeric threshold is published anywhere, and `costs` still says only that auto-compaction
    "summarizes conversation history when approaching context limits" — a negative that is
    trustworthy here because the check ran against complete pages rather than truncated fetches.

## [0.6.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.6.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.6.2]

### Fixed

- **Shared `hook-utils.sh`: `env -S` / `--split-string` no longer hides a whole command from the
  git guards (#2124).** `-S` exists so a shebang line can pass OPTIONS to env
  (`#!/usr/bin/env -S -i prog`), so the words it splits out are env's own arguments. The resolver
  spliced them back into the scan but resumed at the COMMAND dispatcher, which read a leading
  option in the split string as the command NAME and gave up — `env -S '-C <dir> git push --force'`
  resolved to no git at all, so every guard built on `hook::git_resolve_index` skipped the command
  unexamined. Parsing now resumes inside env's own option loop. That also keeps env's single chdir
  slot last-wins across the splice, so `env -C a -S '-C b git …'` reports `b`, matching GNU env.
  Synced from `lib/hook-utils.sh`.

## [0.6.1]

### Fixed

- **Shared `hook-utils.sh`: a NUL byte inside a payload value no longer makes `hook::jq_fields`
  come back empty (#2120).** The helper delimits its batched fields with NUL, and a JSON string may
  legitimately encode one — a `Write`/`Edit`/`NotebookEdit` content field can. jq emitted the raw
  byte, the read split that value in two, the cardinality check saw one value too many, and the
  helper returned non-zero — which every caller treats as "skip", so the hook exited without doing
  its work. Each value is now NUL-stripped INSIDE the jq filter, so the delimiter provably cannot
  occur in a value. Stripping is not a lesser alternative to an encoding scheme, it is the only
  representable behavior: a bash variable cannot hold a NUL byte, and the per-field command
  substitution this helper replaced dropped the byte and kept the rest of the value — so content
  AFTER a NUL is returned and scanned exactly as it was before the batching. Synced from
  `lib/hook-utils.sh`.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.3]

### Fixed

- **`setup check` FAILs a pre-revision-3 installed shim instead of reporting INFO.** The rule
  already described the defect accurately — a copy predating `# shim-revision: 3` picks the newest
  tee by mtime alone and keeps teeing from an UNINSTALLED plugin for the whole orphan window — but
  still classified it INFO because the statusline keeps rendering. Rendering is not the property
  that matters; what the operator is running has a behavior defect, and INFO files it under a
  heading operators are told they can defer. Classification now turns on the installed revision:
  `>= 3` stays INFO, below 3 or unmarked is FAIL.

  **Existing installs need one `apply`.** The statusline runs the durable copy at
  `~/.claude/context-guard/bin/statusline-shim.sh`, which a plugin update never overwrites, so an
  operator who ran `apply` before revision 3 shipped keeps running the old shim until they re-run
  it. Uninstalling first is the trap worth naming: the setup skill goes with the plugin while the
  stale shim stays behind, leaving no in-product path to the remediation. Kept in step with the
  identical `rate-limit-guard` change (#1866) — the two shims are a deliberate byte-identical
  cluster, so their setup contracts must not drift apart.

## [0.5.2]

### Fixed

- **The statusline shell-syntax guard no longer counts quoting as a trigger, so an operator's own
  `sh -c '<command>'` renderer stops being wrapped in a second one.** 0.4.4 stopped the unwrap rules
  from PEELING an `sh -c` the operator wrote themselves. The guard that decides whether to EMIT an
  adapter still listed bare quoting among the syntax needing one, so the preserved renderer reached
  it, matched on its own quote characters, and was printed back as
  `sh -c 'sh -c '\''ulimit -n'\'''` — one more shell on every refresh, exactly the compounding the
  peel rule exists to prevent. A faithful reading of the guard failed this skill's own eval 9.

  Quoting was never a valid trigger *for the reason the guard gave*. The `statusLine` `command`
  field "runs in a shell" (<https://code.claude.com/docs/en/statusline>, fetched 2026-08-07), so
  that shell consumes the quotes and hands words to `statusline-shim.sh`, which `exec`s them
  unchanged. A quoted argument — and an operator's `sh -c '<string>'`, where `sh` is the executable
  and `-c` and the carried string are two ordinary ARGV words — already survives the plain wrapped
  form intact. The trigger is now the syntax no ARGV word can express — an inline env assignment, a
  pipe, `&&`, `||`, `;`, a trailing `&`, or a redirection — and only where it stands UNQUOTED at the
  top level, so syntax sealed inside a quoted argument no longer counts either.

  **Quoting was, however, doing one job by accident, and that job is now done on purpose.** A
  renderer whose command word is a shell BUILTIN — `ulimit '-n'`, which exists as no executable at
  all — needs a shell for reasons that have nothing to do with syntax, and it was reaching the
  adapter only because its quotes tripped the old trigger. Removing quoting with no replacement
  would have sent it to `exec ulimit -n` and exit 127 on every refresh. So the guard gains a second,
  independent trigger: the command word does not resolve as an executable (`type -P` finds nothing
  while `type -t` reports `builtin`, `function`, or `alias`). Resolved the way the shim resolves it,
  never against a hardcoded list of builtin names.

  Scoping the guard that way rescoped the peel rule with it, because the peel rule cites the guard
  to define "carries shell syntax". Its provenance test is now three explicit branches, two of them
  keyed to the SHAPE of the carried string rather than the syntax in it, so neither inherits the
  top-level scoping:

  - The carried string is itself an `sh -c '<string>'` — a generated layer whatever the guard would
    say, since an operator's renderer is at most one `sh -c` deep. Without this branch the peel
    stops one layer early and hands back the two-layer wrap it was supposed to collapse.
  - The carried string begins with a guard-shim prefix. This skill never puts a shim inside an
    adapter, and sealing one there hides it from the prefix rule, which strips only leading
    prefixes — so the composed wiring named that sibling shim a SECOND time and ran its tee twice
    on every refresh.
  - The carried string is a command the guard would wrap — the only shape this skill's own adapter
    ever carries.

  Absent all three the `sh -c` is the operator's and is preserved. One shape stays ambiguous by
  design: a single `sh -c` over a merely-quoted command, which the buggy guard also emitted and
  which carries no evidence either way. It is preserved, at the cost of one spurious shell per
  refresh, because peeling on a guess costs a broken statusline.

  What makes a re-run byte-identical is that peel and wrap are inverses — not a fixed layer count.
  The printed wiring carries no `sh -c` for a plain renderer, one for a renderer with top-level
  syntax, and two where an operator's own `sh -c` sits inside one that needs wrapping (an
  unwrappable `&&`, say). Each of those is idempotent at its own count.

- **`check` no longer reports a differing installed shim as harmless.** The report said an older or
  hand-edited copy "still resolves the newest tee", which stopped being true when
  `# shim-revision: 3` added the orphan skip: a copy predating it picks by mtime alone, so it also
  resolves a tee left behind by an UNINSTALLED plugin and keeps teeing for the whole ~14-day grace
  window. `check` now states which of the two behaviors the installed copy has.

## [0.5.1]

### Changed

- **`setup`'s shell-wrapped statusline step now verifies its escaping by running a command instead
  of asking for a mental round-trip.** The check is `printf '%s\n' '<escaped original command>'`,
  compared against the original. Its single-quoted argument reproduces exactly the quoting context
  the emitted `sh -c '<escaped>'` uses; a double-quoted wrapper would instead let the outer shell
  expand any `$(...)` or backticks in the operator's own command before the check ever ran.

## [0.5.0]

### Changed

- **The zone-crossing report is split by audience: the continuation menu goes to the operator, the
  counter-steer goes to the model.** The hook injected one block into model context naming the zone
  and then enumerating four continuation options — continue, `/clear`, handoff-then-`/clear`,
  `/compact` — plus the `/session-flow:workflow` router. Those are precisely the behaviors a model
  guide reports current models are already predisposed to volunteer, and handing them to the model
  as a menu manufactures that initiative rather than replacing it: the measurement decides only
  *when to ask*, while the model still decides *whether to stop*. That is a live finding under the
  `claude-config` instruction-audit catalog's check I23, which this repository ships.

  The menu now renders on `systemMessage` — the operator channel, whose whole content is a human's
  choice to make — and `additionalContext` carries the zone determination plus the counter-steer:
  this is a measurement and not a decay signal, degradation shows up in the model's own output
  rather than in a zone word, so do not volunteer to end the session, summarize, hand off, or trim
  work on the strength of the reading. The `dumb` zone keeps its extra clause, restated as the
  model-independent fact it always was — compaction distance is short, so write expensive
  conclusions to a durable note as they stabilize.

  **The counter-steer is stated inline rather than delegated** to the `playbooks:fable-5` doctrine
  that also carries it. The two plugins are independently installable with no dependency wiring, so
  a `context-guard`-only install previously received the menu with nothing in context to interpret
  it against.

  **The model channel states ownership, never delivery.** It says continuation is the operator's
  call; it does not say the operator has seen the menu. No documented hook behavior tells a hook
  whether an operator is present — `systemMessage` is documented only as a message shown to the
  user, with nothing said about non-interactive runs — so a delivery claim would be a fact the hook
  cannot know in *any* mode, not only headless ones. Emitting to an unread operator channel is
  harmless; telling the model a human holds the choice when none does is not. A regression assertion
  locks it, because the sentence is the kind that creeps back on a rewording pass.

  **The `hook-observability` convention is amended in the same change**, because this is the first
  fleet payload that is neither a prerequisite-skip nor a content-mutation notice. Its
  advisory-findings exclusion now names its own predicate — *who can act* — and admits a carve-out
  only on three conditions together: the payload is a choice whose only legitimate actor is the
  human, the model channel separately carries the determination the model does need, and the
  emission is keyed to a state transition. The convention also now forbids any model-channel text
  from asserting operator presence, fleet-wide. This **creates** an exception rather than codifying
  practice — every other `systemMessage` site in the fleet is a prerequisite skip or a formatter's
  content-mutation notice — and the conformance section says so, so a second site re-reads the
  conditions instead of following the precedent.

  **Firing cadence is unchanged**, deliberately. Whether a four-option exit menu belonged on the
  `smart → acceptable` crossing was an open calibration question; it dissolves rather than gets
  answered, because the model-facing payload no longer carries a menu at any zone, and a budget
  rendered to a human is outside I23's subject entirely. Zone mechanics, bands, state, kill switch,
  and telemetry are untouched.

## [0.4.9]

### Changed

- **Zone-crossing guidance no longer asserts context degradation as a universal fact.** The
  injected text stated "Response quality degrades as context occupancy grows" unconditionally and
  told the model the dumb zone means measurable degradation — a premise that is stale on models
  whose vendor guides state consistency through the full window (the Opus 5 prompting guide's
  long-context bullet), while the bands can resolve `dumb` at 400k of a 1M window where compaction
  is not in play. The guidance now conditions the degradation claim ("on many models… onset varies
  by model"), names the bands as tunable defaults (`zones.json`), and keeps the model-independent
  part — compaction distance shrinks regardless — unconditional. Zone mechanics, bands, and
  telemetry unchanged.

## [0.4.8]

### Fixed

- **All four hooks declared a 10-second timeout they could not meet on Windows, so the hook was
  cancelled instead of run.** A consuming session on Windows/Git Bash reported
  `zone-crossing-inject.sh` overrunning on essentially every firing across a ten-session chain
  (10.6–21.4 s observed against `timeout: 10`), which meant the zone enforcement never took effect
  while still charging its full wall-time cost. Every registration in `hooks/hooks.json` now
  declares `60`.

  Re-measured on Windows 11 / Git Bash after the 0.4.6 spawn reduction, 18 samples per path: the
  typical case now fits comfortably (means 2.7–10.6 s), but the tail does not.
  `zone-crossing-inject.sh` still reached **22.0 s**, and `post-compact-mark.sh` — whose exposure
  the report could only infer — reached **12.4 s**, both over the old cap. `zone-gate.sh` peaked at
  2.8 s and showed no overrun; it is raised for uniformity and tail-safety, not because it was
  failing. The tail is environmental, not payload-driven: a small `UserPromptSubmit` payload took
  22.0 s while a 150 KB `PostToolBatch` payload took 6.7 s, on a host with Defender real-time
  protection enabled. Sizing has to survive an antivirus-stalled process spawn, not just the median.

  Why 60 and not 30: the measurement times the script alone and excludes the harness's own
  hook-launch overhead, so 22.0 s is a floor rather than a p100 — 30 would leave under 8 s of margin
  on an already-optimistic number. 60 is ~2.7x the observed floor while staying an order of
  magnitude below the harness's own 600 s `command` default, so a genuinely hung hook still cannot
  stall a session for ten minutes. `guardrails` and `disk-hygiene` already declare 60 in this
  marketplace.

  Contract note, verified against <https://code.claude.com/docs/en/hooks> (fetched 2026-08-08):
  `timeout` is *"Seconds before canceling. Defaults: 600 for `command`, `http`, and `mcp_tool`; 30
  for `prompt`; 60 for `agent`. `UserPromptSubmit` lowers the `command`, `http`, and `mcp_tool`
  default to 30, and `MessageDisplay` lowers it to 10."* So 10 was never a harness default here — it
  was authored, narrowing the `PostToolBatch`, `PreToolUse`, and `PostCompact` budgets to 1/60th of
  what the harness allows. The 30 documented for `UserPromptSubmit` is stated as a *default*; the
  page does not say whether it also caps an explicit larger value, so 60 is declared there on the
  understanding that a clamp to 30 would still clear the measurement. The page likewise says only
  "Seconds before canceling" about exceeding the budget — what a cancelled hook reports, and whether
  sibling hooks continue, is not documented and is not assumed here.

  This is the immediate remedy, not the durable one: the underlying per-invocation cost on Windows
  is still real, and a 60 s cap only stops a slow hook from becoming an absent one. Consumers who
  want the overrun visible can point `HOOK_TELEMETRY_SINK` at a sink — every hook already emits
  `duration_ms` per invocation.

## [0.4.7]

### Fixed

- **Every hook loads again; the manifest was pointing at a file Claude Code had already loaded
  (#1985).** `plugin.json` set `"hooks": "./hooks/hooks.json"` — the default path the harness
  discovers on its own. The second registration was rejected as a duplicate and the whole hook file
  failed to load with it, so zone-crossing injection, the blocking gate, and the PostCompact
  evidence-degraded marker were inert on every machine that installed the plugin, and the
  `context_guard_hooks_enabled` and `zone_hook_mode` settings had nothing to switch. The manifest
  field exists for hook files at non-default paths; the default one needs no entry. `claude-ops` and
  `guardrails` already ship `hooks/hooks.json` with no manifest key, which is the shape this now
  matches.

## [0.4.6]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.4.5]

### Fixed

- **The reader contract withdraws an unresolvable citation behind the token shape.** The token-shape
  rationale co-cited "Anthropic system-card fixed-point evals" as evidence that degradation tracks
  absolute tokens rather than window fraction — a claim carried at "Primary research + official /
  High confidence" on #1475's provenance table. The citation names no card, and the only Anthropic
  system card in this workstream's corpus (Claude Opus 5, re-fetched 2026-08-04 and byte-identical
  to its capture) contains no evaluation of any name measuring degradation as a function of context
  length. An exhaustive sweep of that card found zero occurrences of "fixed point", zero of every
  standard long-context benchmark name, and no length axis on the two near-misses ("character
  drift" is an LLM-judge score averaged over ~3,200 investigations with no length variable; "context
  drift" is prose in a cyber benchmark's design rationale). The card's sole long-context section
  (§8.9, ProgramBench) reports pass rate across five episodes, each starting from a *fresh* context
  budget, and the score **rises** 83%→93% — a reset-and-continue improvement curve, not a
  within-context degradation curve.

  The clause now cites the Chroma context-rot report alone, plus a one-line standing rule that a
  system card is cited here by name and section or not at all — the full reasoning lives in this
  entry rather than in the contract, which is a live document and not a place for dated
  withdrawal narration. Deliberately **not** substituted: the
  card's 200k compaction trigger in the BrowseComp harness — the tempting replacement, being the one
  absolute-token threshold inside a 1M window, but it is a harness choice about *when to compact*
  with no stated rationale, not evidence about quality. Other Anthropic cards do publish
  long-context retrieval evals at absolute context lengths, so the underlying proposition may be
  supportable; it is not supportable from an unnamed card, and no replacement is asserted until one
  is read and cited by name.

  **No behavior changes.** The token shape's other two rationales — output tokens occupy the window;
  50% of a 1M window is not 50% of a 200k window — are independent of this citation, and the band
  values themselves were always declared judgment defaults rather than derived from it.

## [0.4.4]

### Fixed

- **The shim no longer runs an uninstalled plugin's tee (#1787).** `claude plugin uninstall` does
  not delete the version directory: the plugins reference documents that updating or uninstalling
  marks the previous version directory orphaned and removes it automatically 14 days later, so the
  files — `scripts/statusline-tee.sh` included — stay on disk for that whole window. `resolve_tee()`
  matched on the glob and mtime alone, so a removed plugin kept teeing and kept writing snapshots
  with no signal to the operator. A candidate whose version directory carries the orphan marker is
  now skipped, so uninstalling stops the tee at the next statusline refresh. The marking is
  documented; the marker's on-disk spelling was measured (Claude Code 2.1.220, against a relocated
  `CLAUDE_CONFIG_DIR`) and the shim's header records both, along with the fallback: should upstream
  rename or drop the marker, resolution degrades to exactly what it does today — a stale tee, never
  a broken statusline. The undocumented `installed_plugins.json` the header previously rejected
  stays rejected.
- **`setup` no longer adds an `sh -c` layer per run (#1787).** "Unwrap before you compose" stripped
  guard-shim prefixes but not the `sh -c '<escaped …>'` adapter the skill's own shell-syntax guard
  prints, so a rerun read that adapter as the renderer, found shell syntax in it, and wrapped it
  again — one layer per run. Unwrapping is now two rules applied until a pass strips nothing, so
  several layers from earlier reruns collapse rather than only the outermost, and a rerun over
  already-correct wiring prints byte-identical wiring. The adapter rule establishes provenance
  before it peels: because the skill emits an adapter only for a renderer carrying shell syntax, an
  `sh -c` over a string carrying none is the operator's own and is preserved — peeling
  `sh -c 'ulimit -n'` would leave the shim `exec`-ing a shell builtin with no shell, exiting 127.

## [0.4.3]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.4.2]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.4.1]

### Changed

- **`context-zone.sh`/`statusline-tee.sh` (and their test files) annotated
  for the shell-portability-lint gate's newly-active `date -d` class
  (#1510).** These scripts' GNU-first/BSD-fallback `date -d ... || date -j
  ...` chains are correct dual-dialect code; most span a line break so the
  gate's same-line auto-guard doesn't recognize them. Each site now carries
  a `portability-ok:` annotation. No behavior change.

## [0.4.0]

### Added

- **Zone-crossing hooks — the first shipped consumer of the plugin's own seam (#1475).**
  `hooks/hooks.json` registers four handlers, all fail-open, all covered by co-located
  `*.test.sh` contract tests:
  - `zone-crossing-inject.sh` (`PostToolBatch` + `UserPromptSubmit`): injects continuation
    guidance via `additionalContext` ONCE per transition into a worse zone — silent while the
    zone is unchanged, improving, or `unknown` (no data is not a transition, and `unknown` never
    updates the per-session state). PostToolBatch fires once per parallel batch before the next
    model call, which replaces the per-tool dedupe a PostToolUse design would have needed;
    UserPromptSubmit covers turns that begin without a prior batch. The injected message carries
    a minimal generic continuation tree plus presence-gated pointers to `session-flow:handoff`
    and `session-flow:workflow`.
  - `zone-gate.sh` (`PreToolUse`, matcher `Write|Edit|NotebookEdit|Agent|Workflow`): the
    `blocking` posture — inert under the default `advisory` mode; in `blocking` mode it denies
    matched calls only on a FRESH dumb-zone snapshot past a per-session grace budget
    (`zone_gate_grace_calls`, in-script default 20). Fail-open on `unknown` and on every missing
    prerequisite. Handoff-path writes are exempt, and read-only tools, Bash, and Skill
    invocations never match — a session told to stop can always write its handoff and always run
    the handoff skill (no deadlock by construction).
  - `post-compact-mark.sh` (`PostCompact`, side-effect-only per the upstream event contract):
    persists the evidence-degraded marker
    `~/.claude/context-guard/context/<session_id>.compacted` (`compacted_at`, `trigger`
    manual|auto|unknown), closing the reader contract's documented "the snapshot cannot tell you
    compaction happened" gap, re-arms the blocking gate's grace budget (a fresh budget, not a
    disarmed gate — both zone consumers treat a marked session's effective zone as dumb
    regardless of its post-compaction numbers, so the marker is never write-only), and prunes
    sibling markers on the tee's 14-day cutoff. jq-free by design, mirroring the
    rate-limit-guard StopFailure recorder.
  - All three hooks read stdin through a plugin-local chunked drain loop (`hooks/payload.sh`,
    mirroring the tee's proven `read -N` pattern) instead of the shared lib's single bounded
    read, which on Windows/MSYS pipes times out on exactly the payloads these events carry —
    PostCompact's full `compact_summary`, a large Write's `tool_input`, PostToolBatch's
    serialized results (measured: ~80KB payloads already lost, which silently suppressed the
    marker and failed the blocking gate open for the biggest writes). Each hook carries a
    large-payload regression test that fails against the single-read form.
  - Config per `docs/conventions/hook-config-delivery`: non-safety knobs over channel B
    (`CLAUDE_PLUGIN_OPTION_<KEY>` env mirrors) with in-script defaults (the declared `default`
    field is not delivered to hook processes). New `userConfig`: `context_guard_hooks_enabled`,
    `zone_hook_mode` (`advisory` | `blocking`, matching the repo's shipped gate-posture enum),
    `zone_gate_grace_calls`. Telemetry envelopes registered as `zone-crossing-inject`,
    `zone-gate`, and `post-compact-mark` producers with data schemas under
    `docs/conventions/hook-telemetry/data/`. Hook state (last-seen zone, gate counters) lives
    under `${CLAUDE_PLUGIN_DATA}` — plugin-private, not part of the reader-contract seam.
- **Window-class token bands + combination rule in the zone resolver (#1475).** The resolver now
  computes two zone shapes and combines them conservatively (the worse computable zone wins; one
  computable shape stands alone; neither → `unknown` — the rule is stated verbatim in the reader
  contract for consumers to inline): the existing percentage shape over `used_percentage`
  (distance to compaction; upstream computes it input-only), and a token shape over occupancy
  `total_input_tokens + total_output_tokens` (distance to quality loss — degradation evidence
  tracks absolute tokens, not window fraction) against per-window-class bands selected by the
  largest class key ≤ `context_window_size`. Shipped token defaults: 200k class 100000/160000,
  1M class 200000/400000 — declared judgment defaults with named anchors (provenance table on
  #1475), equally low confidence on both rows; `zones.json` is the correction path. TWO
  independent gates protect the token shape: a **version floor** (the snapshot's new `cli_version`
  must be present, purely numeric dotted, and ≥ 2.1.132 — before that release the token fields
  were cumulative session totals, and a cumulative value BELOW the window size is
  indistinguishable from a real occupancy, so numbers alone can never rule it out), and the
  **plausibility guard** (occupancy > window size → not computable) for corrupt or forged data.
  `zones.json`
  gains an optional `token_bands` object validated independently of the percentage keys — absent
  is zero-config, so every existing v1 file keeps working unchanged; the percentage keys are
  retained with a recorded retirement trigger (they answer distance-to-compaction, which the
  token shape cannot; they retire when no shipped consumer inlines the percentage floor).
- **`statusline-tee.sh` tees `cli_version`** — the statusline payload's top-level `version` field
  (the Claude Code version), copied only when it is a string and never fabricated. It is the
  signal the token-shape version floor above needs; an absent one simply leaves the percentage
  shape standing alone.
- Setup skill seeds/repairs the v2 `zones.json` shape (including adding shipped `token_bands` to
  a v1 file on `apply`), and `check` now reports hook **registration**, hook-set **activation**
  (the `context_guard_hooks_enabled` kill switch read from its configured value, `UNKNOWN` rather
  than "active" when unreadable), and **gate posture** (`zone_hook_mode`) as three separate facts
  — equating plugin-enablement with active hooks reported the opposite of the runtime state
  exactly when an operator was diagnosing missing injections or gating. Reader contract documents
  the occupancy definition, combination rule, version floor and plausibility guard,
  evidence-degraded marker, hook surface, and band provenance, and its capability table now
  classifies per shape rather than dropping the whole reading to `unknown` on one missing field
  (which contradicted the combination rule it sits above); README updated to the five-part
  overview.

### Fixed

- **The blocking gate's grace counter is now atomic.** Claude starts matched tools in parallel, so
  several `PreToolUse` hook processes ran concurrently against one session's counter; a
  read-modify-write let them all read the same count and record the same increment, so far more
  than the configured budget was allowed (measured 6–7 allowed of 24 concurrent calls against a
  budget of 4). Each call now appends one byte and takes the file size as its count — single-byte
  `O_APPEND` writes do not interleave, so at most `zone_gate_grace_calls` calls can observe a
  count within budget, and the only residual error is over-denial, the conservative direction for
  a gate.
- **`zone_gate_grace_calls` is parsed as base 10.** A digit-only value with a leading zero (`08`)
  cleared validation but is an octal literal in Bash arithmetic: the comparison errored on the
  invalid digit, evaluated false, and denied the FIRST call instead of allowing eight. The value
  is now length-bounded and normalized once, which also keeps the deny reason and the telemetry
  payload carrying a canonical decimal (`{"grace":08}` was invalid JSON).
- **`zone-crossing-inject.sh` fails open silently when the zone state file cannot be persisted**
  (full or newly read-only filesystem). The write failure was previously swallowed (`|| true`),
  so the hook fell through and compared the current zone against the same stale `last` on every
  subsequent `PostToolBatch`/`UserPromptSubmit`, re-injecting the ~1KB guidance block every call
  instead of once per transition — the worst time to spend extra context. The hook now emits
  telemetry `status:error` and exits immediately on a persist failure instead of injecting.
- **`post-compact-mark.sh` reports the marker's actual write outcome in telemetry.** A failed
  temp-file write or a failed atomic rename into place was swallowed, and the hook still emitted
  telemetry `status:ok` — telling operators the evidence-degraded marker was recorded when
  consumers will never see it. The write-and-rename result is now tracked and telemetry reports
  `error` on either failure path; the hook still always exits 0 (PostCompact has no decision
  control, so the marker's own success is signaled through telemetry, not the exit code). A
  directory occupying the contract marker path counts as a persist failure for the same reason:
  `mv` onto a directory SUCCEEDS by moving the temp file inside it, so the hook reported `ok`
  while consumers found nothing readable at the path. The rename is now refused up front, which
  also stops a temp file being stranded in that directory on every compaction.
- **Both stateful hooks fail open instead of writing state into the working directory.**
  `zone-gate.sh` and `zone-crossing-inject.sh` resolved their state root as
  `${CLAUDE_PLUGIN_DATA:-${HOME:-.}/.claude/context-guard}`, so with neither variable set the
  blocking gate's grace counter and the injector's last-seen zone landed under `./.claude/` —
  relative to whatever directory the hook process happened to start in. A counter that resets
  with the working directory is not a budget, and a last-seen zone that moves with it cannot
  hold the once-per-transition contract (the injector would re-emit on every `cd`). Both now
  require an explicit root and exit 0 without it, matching the doctrine `post-compact-mark.sh`
  already applied to its marker path. `HOME` is set by Claude Code in practice, so this changes
  no normal session.
- **The handoff exemption's path extraction uses the file's own jq helper.** `zone-gate.sh` read
  the target path with an open-coded `jq -r … <<<"$INPUT"` while its other two extractions went
  through `hook::jq_field`; it now uses the helper too, which is the idiom for whole-payload
  reads, CR-strips the value, and keeps the exemption path off bash's here-string size heuristic.
  No behavior change was observed — a 200KB here-string completes on bash 5.3.9 (Cygwin), which
  routes an over-capacity here-string through a temp file rather than a pipe — so this is
  consistency, not a hang fix. A 70KB handoff-path Write is now covered end-to-end, which does
  exercise the chunked payload drain.

## [0.3.0]

### Added

- `scripts/statusline-shim.sh` — the durable statusline wiring target. The operator wires the shim
  once; it resolves the newest installed `statusline-tee.sh` at run time (newest by mtime across
  marketplaces under the effective `${CLAUDE_CONFIG_DIR:-~/.claude}` config root, skipping
  transient `temp_*` cache clones), so plugin version bumps never require re-wiring. Transparent
  in every path: no tee installed degrades to running the wrapped statusline alone, and a
  wired-standalone shim prints one diagnostic line instead of leaving a blank bar.
  Pure Bash builtins — no subprocess on the statusline path. Black-box test harness with 31
  assertions, including the two-shim chaining case and a relocated `CLAUDE_CONFIG_DIR`.
- `skills/setup` `apply` now installs the shim (byte-identical copy to
  `~/.claude/context-guard/bin/statusline-shim.sh`, idempotent, inert until the operator wires it)
  alongside the existing zones.json seed/repair.

### Changed

- **Wiring is now the shim, not the tee** (breaking for the printed wiring only; existing wiring
  keeps working until the next update). `setup check` prints
  `bash ~/.claude/context-guard/bin/statusline-shim.sh …`, gained an installed-shim state check,
  and reclassifies a statusline wired to a version-pinned plugin-cache path as LEGACY wiring
  regardless of whether that file currently exists — the old state only flagged a path mismatch.
  Rationale: `${CLAUDE_PLUGIN_ROOT}` is version-pinned and the old version directory is pruned
  ~14 days after an update, so cache-path wiring stops teeing at the next bump and then breaks the
  operator's whole statusline (`bash <missing>` → 127).
- `setup check` prints the sibling-composition wiring when `rate-limit-guard` is also installed,
  and states the measured per-tee refresh cost (~0.6–0.9 s on Windows/Git Bash, spawn-bound).
- `setup check` **unwraps recognized guard shims before composing the wiring it prints**, so a
  statusline already wired through the sibling shim (or through this one) is not wrapped a
  second time. Re-wrapping produced a chain running one tee twice — a duplicated write and
  another 0.6–0.9 s on every refresh — whenever the plugins were configured in sequence or
  `check` was simply re-run.
- The **combined sibling wiring is gated on the sibling shim actually existing**. `rate-limit-guard`
  being installed is not enough: its shim is written by its own `setup apply`, and printing a
  command that names a missing file reintroduces the `bash <missing>` → 127 failure this whole
  change exists to remove. When the shim is absent the single-shim form is printed instead,
  with the sibling's `apply` named as the step that unlocks the combined form.
- **Uninstall guidance is now ordered**: unwrap `statusLine` FIRST, then remove
  `~/.claude/context-guard/`. The previous "either order" wording let an operator delete the shim
  while the wiring still named it, which is the 127 failure again — and the shim's own fallback
  cannot cover it, because the fallback lives in the deleted file.

## [0.2.0] - 2026-07-24

### Changed

- **`/context-guard:setup apply reset` is renamed `apply defaults`.** The setup contract reserves
  `reset` for teardown-plus-apply — converging to the *absence* of the plugin's config, then
  reconfiguring. This action does the opposite: it converges forward, setting both recognized band
  keys to the shipped defaults while preserving every unrecognized key and never removing the file.
  An operator reading `reset` against the contract's meaning would expect their custom keys gone.
  The argument now says what it does. Callers passing the old token get no silent fallback — there
  is no compatibility alias, per the contract's clean-break stance.
- **The setup skill states the reason it owes an `apply` at all.** It cited the "narrow-write
  carve-out" and a repository-level document, which named the shape without naming the condition
  that selects it. The Purpose now says it directly: the statusline surface and the `jq`
  prerequisite are unwritable, but this plugin also owns exactly one writable artifact —
  `zones.json`, whose schema it defines and whose values the operator may edit — and one writable
  owned artifact is what obliges a narrow `apply` rather than a check-only setup.

### Fixed

- **The reader contract no longer cites a repository-level document.** Its no-`experimental.monitors`
  note pointed at `docs/PLUGIN-PHILOSOPHY.md`, a path absent from an installed plugin's cache —
  which is exactly where sibling-plugin consumers read this contract, so the citation resolved to
  nothing for its real audience. The note now states the reason itself (Monitors is experimental;
  this plugin takes no dependency on one until it stabilizes) rather than pointing somewhere
  unreachable.

## [0.1.0] - 2026-07-24

### Added

- `scripts/statusline-tee.sh` — transparent statusline wrapper teeing `captured_at` +
  `session_id` + the verbatim `context_window` object to the per-session snapshot path
  `~/.claude/context-guard/context/<session_id>.json` (atomic temp+rename, Windows rename retry,
  jq-missing visible degrade, session-id sanitization, 14-day sibling pruning, standalone mode).
- `scripts/context-zone.sh` — fail-open zone resolver printing `smart` / `acceptable` / `dumb` /
  `unknown`; shipped default bands 50/75 with `~/.claude/context-guard/zones.json` as the
  machine-scope override; malformed zones fall back visibly.
- `reference/reader-contract.md` — consumer contract: snapshot path pattern, file shape,
  10-minute staleness rule, fail-open capability table, zones.json shape, `${CLAUDE_SESSION_ID}`
  discovery + fallback, inline-floor byte-identity rule, zone-is-not-a-compaction-indicator rule.
- `skills/setup` — `check` (read-only: jq, wiring with stale-cache-path detection, live-session
  snapshot freshness, zones state, printed operator edit) and `apply` (seeds/refreshes zones.json
  only), with evals.
- Black-box test harnesses for both scripts (sandboxed `HOME`, 80 assertions total).
