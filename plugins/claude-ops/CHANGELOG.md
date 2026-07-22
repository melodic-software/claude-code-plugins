# Changelog

All notable changes to the `claude-ops` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.18.2]

### Changed

- Internal: synced the shared hook utility library (`hook-utils.sh`) carried
  by this plugin. This plugin's hooks do not use the changed file-membership
  guard, so there is no behavior change; the version bump ships the updated
  library to consumers that do.

## [0.18.1]

### Changed

- **`lanes` skill — document that a relaunch is the only context reset a loop
  lane gets.** A `/loop` lane re-invokes in the same session and cannot `/clear`
  itself, so the "restart at ~N% context" discipline has no in-session
  enforcement; the skill's `restart` (fresh session from the canonical prompt) is
  the actual reset, and it is operator- or launcher-initiated, not automatic. The
  SKILL.md now states this so a lane prompt does not wrongly assume per-cycle
  freshness. Interim documentation ahead of an automatic relaunch trigger. (#551)

## [0.18.0]

### Added

- **`statusMessage` declared on every hook's `hooks.json` handler** (8 handlers)
  (hook-observability convention, `docs/conventions/hook-observability/`).

### Fixed

- **`skill-usage-audit` and `skill-usage-expansion-audit`'s config-invalid /
  destination-unwritable skip paths are now user-visible.** Previously
  agent-only (`additionalContext`), matching neither channel a missing
  runtime prerequisite requires per the doctrine. Both now route through
  `hook::emit_skip_notice` gated by `hook::notice_once` (once-per-session
  `systemMessage` + `additionalContext`).

## [0.17.4]

### Fixed

- **`morning-brief` test coverage gaps and `usage()` fragility.** Three non-blocking
  nits deferred from the PR #569 review: added a regression test for the
  `any=0` telemetry path (a non-empty comments array where none carry a `lane:`
  field), added a regression test for `--rec-maxlen 0` (full, untruncated
  RECOMMENDED preview), and replaced `usage()`'s hardcoded `sed -n '2,35p'` line
  range with a sentinel-based extraction (shebang to first blank line) so the
  header comment can grow or shrink without silently truncating or over-running
  `--help` output.

## [0.17.3]

### Changed

- **lanes: recorded why the mid-session staleness git probe is not `!`-injected.**
  Evaluated the lanes skill's git probes against the precompute convention (#864).
  The two `git rev-parse --show-toplevel` probes in `SKILL.md`'s front matter are
  already `!` dynamic-context injections (fallback + `shell: bash`), so nothing to
  convert there. The `context/refresh.md` staleness probe correctly stays a body
  instruction — it fails all four conditions: conditional (only when weighing a
  restart), needs a computed `<lane-launch-commit>` argument, and its `git fetch`
  is an unbounded network round-trip that mutates remote-tracking refs. Added that
  reason inline so a future reader does not re-litigate the decision.

## [0.17.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.17.1]

### Fixed

- **`install_new` userConfig had no `default` key.** SKILL.md's `plugins` skill renders
  `${user_config.install_new}` expecting Claude Code to substitute the configured value, falling
  back to `"ask"` when unset; with no declared default, the literal placeholder leaked through
  unrendered instead. Added `"default": "ask"` to the `install_new` entry in `plugin.json`,
  matching what the entry's own description already documented and the pattern every boolean
  option in the manifest already follows (e.g. `api_error_audit_enabled`).

## [0.17.0]

### Added

- **`lanes` skill — scripted two per-cycle lane mechanics that need no reasoning.**
  A `/loop` lane otherwise hand-assembles both every session; now the prompt
  references a script and the output is deterministic and testable.
  - **`machine-behavior.sh`** emits the MACHINE-BEHAVIOR block — gh identity, clone
    path, worktree inventory (root + count + per-worktree branch), and installed
    plugin versions — as a verbatim-printable text block. It emits only
    mechanically unambiguous facts: it deliberately does NOT compute "deviations
    from standing rules" (a model judgment over prose rules, not a scripted field).
    Plugin versions are the INSTALLED runtime versions (read from
    `installed_plugins.json`), which can lag repo HEAD mid-session per
    `context/refresh.md` — the honest number for a running lane. `--plugin <id>`
    (repeatable) scopes the block to the plugins a lane runs.
  - **`telemetry-upsert.sh`** maintains exactly ONE marker-identified telemetry
    comment on a tracking issue, editing it in place instead of posting a second
    (the interim home of the #502 telemetry contract). It writes a
    machine-detectable sentinel `<!-- claude-ops:lane-telemetry marker=STR -->`,
    finds it across all comments (paginated, so a match on any page prevents a
    duplicate) and PATCHes it; failing that, adopts the most recent comment by the
    authenticated user carrying the raw marker as a whole token (boundary-matched,
    so a shorter marker never adopts a longer lane's comment); else creates one. The marker
    charset excludes `>` so it can never close the HTML comment early. Because the
    script is prompt-driven, inputs are hardened against exfiltration: `--repo` is
    validated as `owner/repo` before URL interpolation, a real `--body-file` must
    resolve under `--body-dir`/`$CLAUDE_PLUGIN_DATA` and may not be a symlink
    (pipe an in-memory body via `-`), and the body is capped at 64 KiB.

  Both ship with a sibling `.test.sh` (PATH-stubbed `gh`/`git`, fixture
  `installed_plugins.json` and comment lists — no network) and are documented in
  the skill's `SKILL.md`. (#538)

## [0.16.0]

### Added

- **`plugins` skill — `fleet-state.sh` now emits `missing_from_user_install`.**
  A new user-scope completeness field (catalog ids not installed at `user`
  scope, minus any explicitly opted out) alongside the existing all-scope
  `missing_from_install`. `sync` Step 4 now keys its user-scope install offer
  off this field: a plugin installed only at `project`/`local` scope was absent
  from all-scope `missing_from_install` and so was never offered a user-scope
  install, silently breaking the "usable from any directory" guarantee for it.
  The existing `missing_from_install` field and its all-scope semantics are
  unchanged; the report template (`SKILL.md`) references the new field for its
  "needs install" action. (#254)

### Fixed

- **`plugins` skill — `fleet-state.sh` shape validation now checks each plugin
  entry, not just the top-level type.** A drifted individual entry (a non-array
  value) passed the `{plugins: {...}}` object check, then failed inside the
  installed-flatten `jq` pipeline in a command substitution; with `set -uo
  pipefail` but no `set -e` the failure was swallowed and the script exited 0
  with `installed: []` instead of failing loud per its stated design. The check
  now asserts every entry is an array and exits 2 on drift. (#254)
- **`plugins` skill — `fleet-state.sh --marketplace` with no name now exits 2
  instead of infinite-looping.** With one positional param left, `shift 2`
  failed silently (no `set -e`), leaving `$1` unchanged so the arg loop re-read
  `--marketplace` forever and the post-loop guard was never reached. The empty
  check now runs inside the `--marketplace` branch, before `shift`. (#254)

## [0.15.4]

### Changed

- **`changelog` skill — installed CC version is now precomputed via `!`
  dynamic-context injection.** The version-awareness step previously told Claude
  to run `claude --version` as a body instruction (a per-invocation tool
  round-trip); it now inlines the probe at load time with
  `` !`claude --version || echo "(CC version unavailable)"` ``. The probe is
  deterministic and read-only, carries the mandated `|| echo` defensive
  fallback, and drops the bash-only `2>/dev/null` redirect so the command and
  its fallback stay valid on both the bash default and the Windows PowerShell
  host. No behavior change.

## [0.15.3]

### Added

- **`lanes` skill — mid-session staleness & restart-cadence guidance
  (`context/refresh.md`).** Loop lanes merge fixes to the very plugins they run on,
  but a running lane keeps the skill versions it loaded at launch. New
  documentation establishes, against current Claude Code docs, that a true
  mid-session hot-reload of a running loop lane is not achievable — a live session
  retains its launch-time plugin versions, `/loop` never re-reads a skill's body on
  later cycles, and a loop cannot self-trigger `/reload-plugins` — so restart is the
  honest refresh mechanism (composing with the #496 context-reset cadence). Adds a
  read-only git probe to detect an unconsumed self-fix on `origin/main` and a
  trigger-based + periodic-floor restart cadence keyed to `/claude-ops:lanes
  restart`. The probe resolves the repo's default branch rather than assuming
  `main`. SKILL.md gains a summary section, a cross-reference, and an eval. No
  script or behavior change. (#514)

## [0.15.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.15.1]

### Fixed

- **`lanes` skill — launch aborts on a failed pre-launch refresh.** `start` /
  `restart` previously ran `refresh_repo_and_plugins || rc=1` and launched lanes
  regardless, so a failed `git pull --ff-only` (divergent/dirty checkout) or
  `claude plugin marketplace update` still seeded background lanes from stale
  repo/plugin state. The refresh is a documented launch prerequisite, so an
  unexpected failure now hard-stops the launch (exit non-zero) with an actionable
  message; `--no-pull` / `--no-update` remain the intentional-skip path (a
  skipped step is not a failure). (#639)

- **`lanes` skill — unknown restart/stop targets are rejected before any refresh
  mutation.** `restart does-not-exist` ran `git pull --ff-only` +
  `claude plugin marketplace update` before discovering the target was unknown.
  The `TARGET_LANES` existence check now runs up front in `main`, ahead of the
  refresh step, so a misspelled target fails fast (exit 3) with no repo/plugin
  mutation — matching `stop`'s fail-first behaviour. (#639)

## [0.15.0]

### Added

- **`lanes` skill** — a scripted launcher that starts, restarts, stops, and
  reports loop lanes as **named background Claude Code sessions** seeded from
  canonical prompt files, replacing the manual morning refresh (cancel loop,
  clear, re-paste the canonical prompt) across N lanes. `start` (default) and
  `restart` first `git pull --ff-only` and `claude plugin marketplace update`,
  then launch each configured lane with `claude --bg -n <lane>` mirroring the
  lane's `model`/`effort`; `status` prints a per-lane running/stopped table with
  the live sessionId; `stop` ends a lane via `claude stop <sessionId>` (resolved
  from `claude agents --json` — there is no `claude agents stop` verb). Acts on a
  session **only** when its name is a configured lane, so a hand-started session
  is never touched. Lanes come from a JSON config (`--config`, else
  `$CLAUDE_OPS_LANES_CONFIG`, else `<repo>/.work/lanes.json`); `--dry-run`,
  `--no-pull`, `--no-update`, and `--agents-json` support previewing and offline
  reuse. Prompt files are read from a session-local `.work` dir today via the
  single `prompt_dir`/`resolve_prompt_dir` seam, which composes with #480
  (loop-prompt authoring skill) when durable prompt storage lands.

## [0.14.0]

### Added

- **`morning-brief` skill** — a read-only, `gh`-based operator morning view for
  the current repo, collapsing the daily hand-run queries into one 5-second
  picture: open counts per queue label (`priority: needs-triage`, `status: ready`,
  `status: needs-decision`, `needs-human`), the gh-native merge-ready PR list
  (non-draft + `mergeStateStatus=CLEAN`), parked `status: needs-decision` issues
  with their RECOMMENDED lines (uppercase marker preferred, case-insensitive
  fallback), and loop-lane telemetry freshness (per-lane `last-cycle` age, marked
  `STALE` past `--stale-hours`, plus any `flags:`). Owner/repo is derived from
  `gh repo view`, never hardcoded; the telemetry issue is auto-discovered by title
  (`--telemetry-issue` to pin) and degrades to "no telemetry issue found" where
  absent. The authoritative PR merge gate remains `/source-control:babysit-prs`;
  this list is a fast glance, not a substitute for that skill's classification.

## [0.13.1]

### Changed

- **`hook-telemetry-sink` quiet jq skip documented at the site** with a
  `silent-skip-ok` annotation (the marketplace's new silent-skip CI gate). No
  behavior change: the sink is fire-and-forget — its producer discards
  stdout+stderr, so prerequisite visibility is owned by the producer side.

## [0.13.0]

### Changed

- **BREAKING: `known-issues scan` is read-only on bare invocation** (fleet
  conformance wave: the naming doctrine's `scan` verb contract). It reports
  untracked references and prints the registering invocation; the registry
  write now requires the explicit `scan --add` override.

## [0.12.0]

### Changed

- **`setup` skill refactored onto the uniform check/apply contract** (fleet conformance wave).
  `/claude-ops:setup` replaces the interactive-validation shape with `check` (default, read-only:
  reports the effective `registry_dir` and `skill_usage_dir` destinations, their defaults, and
  containment status as PASS/FAIL/INFO) and `apply` (non-interactive: states the
  per-machine-vs-repository-resident tradeoff and routes reconfiguration through Claude Code's native
  prompt, with the fresh-install-only `--config` headless semantics). Containment validation, the
  personal-not-team-policy framing, and the dated `pluginConfigs` claim are unchanged. Setup still
  never writes user settings or `pluginConfigs`.

## [0.11.3]

### Changed

- **Freshness riders on platform-fact docs** (fleet conformance wave). The
  `plugins` skill's scope-semantics doc now carries a verified-date header
  (all version-gated claims re-verified: `/reload-plugins --force` ≥ 2.1.163,
  renames ≥ 2.1.193, `plugin prune` ≥ 2.1.121, `userConfig` type set); the
  monitor-restart claim now cites its actual source (plugins-reference). The
  setup skill's `pluginConfigs` claim is dated and pinned to ≥ 2.1.207.

## [0.11.2]

### Changed

- Refresh of the bundled shared hook-utils library, which gains the git argv-grammar parser used by
  the guardrails plugin's git guards. No behavioral change to this plugin's hooks.

## [0.11.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's audit hooks. README now states the hook
  runtime (Bash via Git Bash on native Windows, jq) and the jq fail-open
  behavior.

## [0.11.0]

### Changed

- **Per-hook kill switches migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling). Each audit hook's toggle is now a `userConfig`
  boolean (default `true`), read by the hooks through the native
  `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror: `api_error_audit_enabled`,
  `config_change_audit_enabled`, `instructions_loaded_audit_enabled`,
  `permission_denied_audit_enabled`, `pre_compact_audit_enabled`,
  `skill_usage_audit_enabled` (shared by both skill-usage audit hooks), and
  `tool_failure_audit_enabled`. The `instructions-loaded-audit` session_start
  opt-in is now the `instructions_loaded_audit_log_session_start` option
  (default `false`), and the stdin read bound is the `stdin_read_timeout` option
  (default `2`). Configure interactively with `/plugin configure claude-ops` or
  headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED` and
  `HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START` environment variables are
  retired and no longer read. A consumer that set any of these in a settings
  `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all audit hooks on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.

## [0.10.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.10.0]

### Changed

- **Breaking:** renamed the `troubleshoot` skill to `known-issues` (plugin ID `claude-ops` is
  unchanged). Update any old invocations: `/claude-ops:troubleshoot` → `/claude-ops:known-issues`.
  The skill looks up and tracks known upstream Claude product issues; it never diagnoses or fixes
  local problems, so the old name over-promised. Behavior, actions, and the `registry_dir` option
  are unchanged; the registry is now referred to as the known-issues registry.

## [0.9.0]

### Added

- New `plugins` skill (`/claude-ops:plugins`): brings a machine's plugin fleet current on demand.
  `sync` (default) refreshes marketplaces, updates in-repo project/local-scope installs plus the
  user-scope sweep, installs new catalog plugins per the `install_new` policy, and fills any
  `enabledPlugins` completeness gap — all CLI-mediated, never hand-editing Claude Code's internal
  state files. `audit` runs the same algorithm read-only. `converge` is the one action that can
  touch a committed `.claude/settings.json`: it detects actionable (version-behind) scope
  divergence, previews and confirms per plugin, then surfaces the resulting diff for review — never
  auto-committed, and it aborts outright in an autonomous session. Adds a read-only
  `scripts/fleet-state.sh` state-inspection script and the `install_new` userConfig scalar
  (`ask` default / `all` / `none`).

## [0.8.0]

### Changed

- Rewired OTEL retention to stop, poll, and start the provisioning-owned `otelcol-contrib`
  Windows service. A failed stop or status query aborts before mutation; the prune lock remains
  held through restart, and a failed restart is visible to the caller.

### Removed

- Removed the duplicate Collector configuration and the private/public `start-collector.sh`
  process launchers. Machine provisioning is now the sole Collector lifecycle and configuration
  owner.

## [0.7.0]

### Changed

- Moved long-running telemetry lifecycle to machine provisioning: the boot-time
  `otelcol-contrib` Windows service owns collection, and the provisioning Compose stack owns the
  optional Aspire dashboards.

### Removed

- Removed the private and public `start-dashboard.sh` entry points and their tests. Claude
  sessions no longer create or replace machine-owned dashboard containers.

## [0.6.0]

### Changed

- Renamed three skills (plugin ID `claude-ops` is unchanged, only the leaf names moved). Update any
  old invocations:
  - `claude-observability` → `observability` (`/claude-ops:observability`)
  - `claude-troubleshooting` → `troubleshoot` (`/claude-ops:troubleshoot`)
  - `claude-code-changelog` → `changelog` (`/claude-ops:changelog`)
