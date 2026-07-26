# Changelog

All notable changes to the `context-guard` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1]

### Changed

- **`context-zone.sh`/`statusline-tee.sh` (and their test files) annotated
  for the shell-portability-lint gate's newly-active `date -d` class
  (#1510).** These scripts' GNU-first/BSD-fallback `date -d ... || date -j
  ...` chains are correct dual-dialect code; most span a line break so the
  gate's same-line auto-guard doesn't recognize them. Each site now carries
  a `portability-ok:` annotation. Also fixed a real gate false positive: the
  gate's `sed -i` class (already active) flagged `context-zone.test.sh`'s
  unsuffixed `sed -i` fallback probe, whose actual portability comes from
  its `perl -pi -e` fallback, not the auto-recognized empty-suffix idiom —
  annotated. No behavior change.

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
