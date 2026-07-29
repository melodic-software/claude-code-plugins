# Changelog

All notable changes to the `context-guard` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
