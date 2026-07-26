# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.2]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no hook block/allow behavior changes.

## [0.3.1]

### Fixed

- **Setup's headless reconfigure recipe no longer claims `-y` is CLI-required for a non-TTY
  `uninstall`.** Verified against the live CLI (2.1.220) and current docs: `-y` only skips
  `uninstall`'s `--prune` confirmation, and this recipe never passes `--prune` — so `-y` had no
  effect and is no longer part of the recipe (#1410).

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
- **`setup apply`** — the skill is no longer check-only. `apply` installs the shim (byte-identical
  copy to `~/.claude/rate-limit-guard/bin/statusline-shim.sh`, idempotent, inert until the operator
  wires it) and writes nothing else; `settings.json` stays the operator's to edit.

### Changed

- **Wiring is now the shim, not the tee** (breaking for the printed wiring only; existing wiring
  keeps working until the next update). `setup check` prints
  `bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh …`, gained an installed-shim state check,
  and reclassifies a statusline wired to a version-pinned plugin-cache path as LEGACY wiring
  regardless of whether that file currently exists — the old state only flagged a missing file.
  Rationale: `${CLAUDE_PLUGIN_ROOT}` is version-pinned and the old version directory is pruned
  ~14 days after an update, so cache-path wiring stops teeing at the next bump and then breaks the
  operator's whole statusline (`bash <missing>` → 127).
- `setup check` prints the sibling-composition wiring when `context-guard` is also installed, and
  states the measured per-tee refresh cost (~0.6–0.9 s on Windows/Git Bash, spawn-bound).
- `setup check` **unwraps recognized guard shims before composing the wiring it prints**, so a
  statusline already wired through the sibling shim (or through this one) is not wrapped a
  second time. Re-wrapping produced a chain running one tee twice — a duplicated write and
  another 0.6–0.9 s on every refresh — whenever the plugins were configured in sequence or
  `check` was simply re-run.
- The **combined sibling wiring is gated on the sibling shim actually existing**. `context-guard`
  being installed is not enough: its shim is written by its own `setup apply`, and printing a
  command that names a missing file reintroduces the `bash <missing>` → 127 failure this whole
  change exists to remove. When the shim is absent the single-shim form is printed instead,
  with the sibling's `apply` named as the step that unlocks the combined form.
- **Uninstall guidance is now ordered**: unwrap `statusLine` FIRST, then remove
  `~/.claude/rate-limit-guard/`. The previous "either order" wording let an operator delete the shim
  while the wiring still named it, which is the 127 failure again — and the shim's own fallback
  cannot cover it, because the fallback lives in the deleted file.

## [0.2.1]

### Changed

- **Setup states the accurate reason it is check-only.** It claimed the check-only carve-out as
  scoped to plugins whose entire configuration is native `userConfig` — a premise this plugin does
  not meet, since its statusline wiring lives in the user's own `settings.json`. The conclusion was
  right and the justification was not. The Purpose now names the condition that actually holds: no
  writable owned artifact anywhere in the surface. Each of the three surfaces is enumerated with why
  setup cannot write it, and the machine files under `~/.claude/rate-limit-guard/` are called out as
  runtime-owned plugin data rather than a fourth, operator-editable surface — which is what
  distinguishes a plugin that must not invent an `apply` from one that owes a narrow one.
- **Setup documents the headless reconfiguration route beside the interactive one.** The kill
  switch's only route was `/plugin configure rate-limit-guard`, leaving a headless consumer with
  nothing; the obvious guess, re-running `claude plugin install --config`, silently no-ops on an
  installed plugin. The fresh-install-only behavior and the uninstall-then-reinstall route it forces
  are now stated where the reconfiguration guidance lives. The recipe passes `-s <scope>` on both
  halves and `-y` on the uninstall: both commands default to `-s user`, so an unscoped pair removes a
  separate user record while a project- or local-scoped install keeps loading, and a non-TTY
  uninstall requires the confirmation flag to run at all.
- **The reader contract no longer cites a repository-level document.** Its no-`experimental.monitors`
  note pointed at `docs/PLUGIN-PHILOSOPHY.md`, a path that does not exist in an installed plugin's
  cache — where this contract is read by sibling-plugin consumers, the citation resolves to nothing.
  The note now states the reason a reader needs (Monitors is experimental; this plugin takes no
  dependency on one until it stabilizes) without a pointer that cannot be followed.

## [0.2.0]

### Changed

- **The single-account-per-machine text is repointed at its owner.** This reader contract
  carried its own copy of the assumption while naming loop-lane §6 as its owner, so the copy would
  contradict §6 the moment §6 moved — which it now has: §6 reframes the assumption as a known gap.
  §6 owns the framing; what stays here cites it rather than asserting it independently. What is
  local to the guard stays local: the writer already
  forward-passes any top-level `account`-matching key, so an identity field costs no plugin change
  the release one appears. The account-identity design itself is `TODO(#1218)`.

## [0.1.0]

### Added

- **Statusline tee wrapper** (`scripts/statusline-tee.sh`): transparent passthrough around the
  user's statusline command that atomically tees `rate_limits`, `captured_at`, and every
  session-distinguishing stdin field to the fixed contract path
  `~/.claude/rate-limit-guard/rate-limits.json` (temp file + rename; Windows locked-target renames
  retried then skipped without ever affecting the statusline pipeline). Standalone minimal
  statusline when invoked with no wrapped command; visible notice instead of a silent skip when
  `jq` is absent.
- **StopFailure detection hook** (`hooks/record-rate-limit-stop.sh`, matcher `rate_limit`):
  side-effect-only, jq-free reactive fallback appending bounded JSONL detection records to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. Kill switch via the `rate_limit_guard_enabled`
  `userConfig` boolean.
- **Reader contract** (`reference/reader-contract.md`): the operable floor consumers inline —
  fixed tee path, 90%-of-either-window pause threshold, tripped-window `resets_at` pause end
  (later `resets_at` only when both windows trip), 10-minute staleness rule with mandatory
  session-Monitor arming while paused, capability-detect fail-open (absent/absurd values →
  reactive-only), and drain-then-pause.
- **Check-only `setup` skill**: verifies `jq`, tee freshness (distinguishing "no statusline
  configured" from "wrapper missing" and from a cache path gone stale after a plugin update), and
  the hook kill switch; prints the exact `settings.json` statusline edit for the operator — the
  skill never mutates user settings.
