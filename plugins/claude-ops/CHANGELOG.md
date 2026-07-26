# Changelog

All notable changes to the `claude-ops` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.21.6]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became a true idle bound: `read -t` is a deadline for the whole requested read rather
  than an inactivity timer, so a timed-out read that nevertheless returned bytes is now treated as
  progress — its partial chunk is kept and a fresh window is armed. Only a window that delivers
  nothing at all is a stall. `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS
  system bash), so the pre-4.1 path falls back to the delimiter read inside the same re-arming
  loop. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`.
- **`skill-usage-expansion-audit` could hang on a large payload.** It read `expansion_type` with a
  jq here-string. Bash fills a here-string's pipe itself, so a payload at or above the pipe capacity
  (65536 bytes) blocks the hook forever before jq is exec'd. The bounded stdin read used to reject
  anything that large before it got here; now that it does not, the call goes through
  `printf | jq` instead. Reproduced on the shared library's own equivalent call: a 65536-byte buffer
  hung indefinitely while 65000 returned immediately.

### Changed

- **`stdin_read_timeout` is documented as the idle bound it now is.** This plugin already exposed
  the option, and its README and manifest description both described it as bounding "how long each
  hook waits for its payload before failing open" — a total read deadline. It is now an inactivity
  deadline: any byte resets it, so a producer that keeps emitting is bounded by Claude Code's own
  hook timeout rather than by this value, and the bound is read in four slices so a stall is detected
  within a quarter of the configured interval. Documentation only — the configuration contract users
  read was materially misleading after the shared-library change above.

## [0.21.5]

### Fixed

- **`known-issues` contact links now point at the migrated documentation domain.** Anthropic moved
  the Claude Code docs from `docs.claude.com/en/docs/claude-code/<slug>` to
  `code.claude.com/docs/en/<slug>`; the three links in
  `skills/known-issues/context/issue-templates.md` still used the old host and survived only on a
  301. Each replacement was verified by fetching the old URL, observing the redirect, and
  confirming the target page's topic. The bare docs root does not redirect like the others (302 to
  `platform.claude.com`, then 307 to `code.claude.com/docs`), so it now points at the Overview
  page, which matches this repo's dominant `/docs/en/<slug>` convention.

## [0.21.4]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`claude-ops-test-helpers.sh`).

## [0.21.3]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. This plugin's
  `permission-denied-audit` and `tool-failure-audit` hooks compute their
  subject through this helper, so the leak was reachable here. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no audit hook's outcome changes.

## [0.21.2]

### Fixed

- **`plugins` skill's `converge.md` no longer overstates when `uninstall` needs `-y`.** It claimed
  any non-TTY `uninstall` requires `-y` "by the CLI itself." Verified against the live CLI (2.1.220)
  and current docs: `-y` only skips `uninstall`'s `--prune` confirmation, and this action's
  `uninstall` calls never pass `--prune` — so `-y` was never warranted here and adding it would only
  ever bypass a different, unused prompt, not Step 3's per-plugin confirm (#1410).

## [0.21.1]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.21.0]

### Added

- **`lanes` skill: `lane-launcher.sh` now captures and persists the launch commit
  (`#792`).** `context/refresh.md`'s git staleness probe referenced a
  `<lane-launch-commit>` placeholder with no producer — the repo HEAD when
  `lanes start`/`restart` last ran was advisory-only, with no automated way to
  retrieve it. `lane-launcher.sh` now captures `git rev-parse HEAD` right after
  the pre-launch pull (a pure read, so it also previews correctly under
  `--dry-run`) and writes it, for every lane actually (re)started that run, to
  `<data-dir>/lanes/<lane>-launch-commit` — a lane `start` skips as
  already-running keeps its existing marker untouched. New `--data-dir DIR`
  option (default: the `$CLAUDE_PLUGIN_DATA` env var if set, else
  `~/.claude/plugins/data/claude-ops`, matching `check-all.sh`'s convention).
  `SKILL.md`'s invocation now passes `--data-dir "${CLAUDE_PLUGIN_DATA}"`
  explicitly — per current
  [plugins-reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
  `CLAUDE_PLUGIN_DATA` is exported as a real env var only to hook/MCP/LSP
  subprocesses, not to a script a skill shells out to via the Bash tool, so a
  script-internal fallback alone would silently miss the marketplace-qualified
  data directory in a real session. The write is best-effort: a failure (or an
  unresolvable HEAD) warns on stderr but never fails an already-launched lane.
  `context/refresh.md` and `SKILL.md` now point the probe at the real marker
  file instead of the unfillable placeholder, with an explicit hex-only-input
  note for anyone who later sources the value from something other than `git
  rev-parse`, and a `tr -d '\r'` strip on the marker read (the repo's standing
  CRLF-hazard convention for any captured Windows value). New regression cases
  in `lane-launcher.test.sh` cover the capture/write, the
  skip-if-already-running case, `--dry-run` (preview only, no write),
  unresolvable-HEAD (best-effort, no failure), and the `$CLAUDE_PLUGIN_DATA`
  fallback.
  - The probe's `data_dir` is sourced from `SKILL.md`, which is the only surface
    where it resolves. Per
    [plugins-reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
    `${CLAUDE_PLUGIN_DATA}` substitutes inline in *skill and agent content* but is
    exported as a real environment variable only to hook and MCP/LSP subprocesses
    — and `context/refresh.md` is read raw rather than rendered as skill content.
    An env-var-with-fallback expression there would have silently resolved to the
    unqualified `~/.claude/plugins/data/claude-ops` guess, read no marker, and
    skipped the staleness check without saying so. `SKILL.md` now carries the
    substituted `data_dir=` assignment and `context/refresh.md` points at it.
  - A lane name is now validated as a single path component at config preflight
    (exit `3` on `/`, `\`, `.`, or `..`). The name is the marker's filename, so
    without that check two distinct configured lanes — `work` and
    `group/../work` — would share one marker file and a targeted restart of
    either would make the other's probe read a launch commit it never launched
    at. Rejecting rather than encoding keeps the documented
    `<data-dir>/lanes/<lane>-launch-commit` path literally true.
  - The marker path is namespaced by repo
    (`<data-dir>/lanes/<repo-key>/<lane>-launch-commit`). The data directory is
    plugin-wide but a lane name is only unique within one repo, so a
    conventional `work` lane in two checkouts would otherwise share a marker and
    each repo's probe would diff against the other's unrelated history — usually
    an invalid-revision error, at best a silently wrong answer. `<repo-key>` is
    `git hash-object` over `git rev-parse --show-toplevel`: a digest rather than
    a character fold, because folding collapses two real checkout paths like
    `/repos/foo-bar` and `/repos/foo/bar` onto one key, and git's canonical
    (symlink-resolved) toplevel rather than the `--repo` argument, because the
    documented probe asks git directly and both sides must land on the same key.
    Print the key for a checkout with
    `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`.
  - A (re)start that cannot record its own commit (unresolvable HEAD, or a failed
    write) now removes any marker the previous launch left. Leaving it made the
    probe treat that older commit as the new session's launch point and report
    already-consumed merges indefinitely; removing it degrades the probe to its
    honest "no marker → skip" branch. `--dry-run` still touches nothing.

## [0.20.0]

### Added

- **`lanes`: per-lane `settings` passthrough, wiring the autonomy lane-stop gate into the shipped
  launch flow (#535 review follow-up).** The autonomy plugin's `Stop`-hook lane-stop gate is
  default-OFF and documents a per-session opt-in via `claude --settings`, but the lane launcher —
  the repository's shipped standing-lane flow — built only `claude --bg -n … [--model] [--effort]`
  and never supplied that override, so no launched lane ever received the gate or its operator
  notification. The lane config now takes an optional per-lane `settings` JSON object that the
  launcher passes verbatim as `--settings` (session-only, never persisted) on `start`/`restart`,
  validated as an object at preflight so a malformed value skips the lane instead of failing the
  launch with an opaque CLI error. Generic by design: any session-only settings override rides the
  same field; the gate opt-in (`pluginConfigs` → `autonomy@<marketplace>` → `options`) is the
  motivating example documented in `context/config.md`.

## [0.19.3]

### Fixed

- **`plugins` skill: `fleet-state.sh` no longer crashes with `Argument list too long` against a
  large-catalog marketplace (`#1336`).** Every `jq --argjson <name> "$value"` call site carrying a
  catalog/installed/enabled-scale JSON payload embedded that value as a literal command-line
  argument; for a marketplace catalog large enough (confirmed against a real 273-plugin catalog,
  reproduced here with a synthetic 500-plugin fixture), the serialized JSON exceeded the
  platform/shell's argv-length ceiling and `jq` failed before emitting anything — silently dropping
  that marketplace from `sync`/`audit`/`converge`. Confirmed on Windows Git Bash/MSYS `jq`, but the
  underlying argv-length ceiling is a real limit on every platform, just reached sooner there.
  Every affected call site now routes its payload through a temp file via `jq --slurpfile` instead
  of `--argjson`, so catalog size never determines whether a marketplace can be synced. Only the
  fixed-size boolean `--argjson` uses (`au`/`ci`/`autoUpdate`) remain untouched. Covered by a new
  large-catalog case in `fleet-state.test.sh` (asserts no argv-length crash and full,
  non-truncated output) plus a static guard locking the remaining `--argjson` count to booleans
  only.
  - Temp files created for `--slurpfile` routing live in one per-run directory removed by an EXIT
    trap; each call site invokes the writer inside a `$(...)` subshell, so files are not tracked in
    an array (a subshell-local append would vanish on return) — the whole directory is the cleanup
    unit instead.
  - A malformed source file (e.g. `settings.json`) used to make the affected `--argjson` fail loud
    immediately; `--slurpfile` instead tolerates a genuinely empty payload as "zero JSON values"
    and would have silently degraded the report to `null` fields. The writer now emits a
    deliberately-invalid token for an empty payload so jq's own parser still errors at the call
    site, preserving the prior fail-loud behavior. Covered by a new malformed-`user_settings.json`
    case in `fleet-state.test.sh`.

## [0.19.2]

### Documentation

- `hooks/claude-ops-test-helpers.sh` now points at
  `docs/conventions/shell-test-helpers/README.md`, the repo's owner doc recording that per-plugin
  shell assert-helper duplication and per-script exit-code taxonomies are deliberate, not drift. No
  behavior change.

## [0.19.1]

### Fixed

- **`plugins` skill: the default (no-`--marketplace`) path no longer breaks after a mid-session
  version bump of claude-ops itself (`#1176`, audit finding F1).** `fleet-state.sh`'s
  `resolve_default_marketplace` exact-matched the running plugin root against the version-pinned
  `installPath` in `installed_plugins.json`; any time the session's loaded version differed from the
  installed one — a marketplace `autoUpdate` shortly after session start, or `sync`'s own Step-3
  self-update — the join found nothing and the skill's primary invocation form failed with "could not
  resolve the default marketplace". Added a version-agnostic fallback that matches the version-stripped
  `…/cache/<marketplace>/<plugin>` prefix (exact match still tried first; marketplace stays
  distinguishable), plus a clearer error that prints the searched root and names the version-skew cause.
  Covered by a new version-skew case in `fleet-state.test.sh`.

### Changed

- **`context/gotchas.md`: generalized the CRLF gotcha (audit finding F2).** The trailing-`\r` hazard
  is not `jq`-only — any captured Windows value (`python` `print`, PowerShell interop, `git config`,
  a CRLF file read) can corrupt a constructed `claude plugin` id so the CLI reports
  `Plugin "<name>" not found` with the full id passed (marketplace suffix silently corrupted). Rescoped
  the entry to "any captured value", documented the collision with the bare-name symptom, and
  cross-referenced the two.
- **`plugins` SKILL.md: corrected the `install_new` render contract (audit finding F3).** An unset
  `${user_config.install_new}` renders the literal placeholder (the manifest `default` is not
  substituted for an unset key; verified against CC 2.1.218) — the common default-config case. The doc
  now reads that literal placeholder as the expected unset state → use the default `ask` without
  flagging it as an invalid value; only an explicitly-set unsupported value is the invalid case.

## [0.19.0]

### Added

- **`skill_usage_scope` userConfig — the skill-usage store's home is now scope-selectable
  (`repo` | `user` | `data-dir`), and the repo scope keeps `git status` clean via a
  machine-local `.git/info/exclude` entry (`#1151`).** Previously the store was forced into
  every consuming repo's tree (`.claude/observability/skill-usage.jsonl` as untracked
  `git status` noise) and the `skill_usage_dir` containment validation made user/machine
  scope unreachable by config — containment as a ceiling instead of a default. Now: `repo`
  (default, unchanged location) resolves the contained `skill_usage_dir` subpath under the
  repo root and idempotently adds the store dir to `.git/info/exclude` (machine-local; never
  `.gitignore` or tracked files; tracked content is unaffected by ignore semantics; opt out
  with the new `skill_usage_git_exclude=false` for teams that deliberately commit the
  telemetry); `user` resolves the same contained subpath under `$HOME` — one cross-repo
  operator store; `data-dir` writes `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>` —
  plugin-owned, update-safe, keyed by repo. Unknown scope values fall back to `repo` with a
  one-time advisory (prose-validated; the manifest schema has no enum type). Store rows gain
  `project` (project-root basename, display) and `project_id` (basename + 8-char digest of
  the physical path — same-basename checkouts stay distinguishable) so cross-repo scopes
  keep repo identity; the data-dir key uses the same collision-resistant slug, and the
  exclude line is segment-normalized (a configured `./x` or `x//y` still matches) and
  glob-escaped (`*` `?` `[` in a configured dir write a literal exclude pattern, not a
  glob that over-matches sibling dirs). A `skill_usage_dir=.` (repo-root) store excludes
  the store file (`/skill-usage.jsonl`) rather than the whole tree.
  **Default-flip decision (recorded):** the default deliberately stays `repo` — the store
  sits beside `hook-events.jsonl` per the observability skill's project-local posture (that
  skill reads only `hook-events.jsonl` and the OTEL store, so colocation is convention, not
  a read dependency), the exclude entry removes the status noise that motivated the change,
  and flipping would silently relocate existing consumers' data.

## [0.18.3]

### Security

- **`plugins` fleet-state: hook-utils.sh is now resolved only from the script's
  own location, closing an arbitrary-file `source` via `FLEET_STATE_HOOK_UTILS`.**
  The test-only `FLEET_STATE_HOOK_UTILS` env override let any caller able to set
  an environment variable (a project `.claude/settings.json` env block, an
  inherited shell, another hook) redirect the `source` at an attacker-controlled
  file, executed with the script's ambient permissions — the existing guard only
  checked the path existed, not that it was trusted. `hook-utils.sh` is a fixed
  sibling shipped with the plugin, so it is now loaded unconditionally from the
  script-relative plugin root; the override was removed rather than gated because,
  once the path is script-relative, an override can only ever equal that trusted
  default (both test call sites already resolved to it). `CLAUDE_PLUGIN_ROOT` is
  no longer consulted for this sibling file (it equals the script-relative root
  in production); it is still used for marketplace self-resolution. The
  script-relative path is computed with `builtin cd`/`builtin pwd` and
  `command dirname` so an inherited environment that exports shell functions of
  those names (`BASH_FUNC_cd%%` and friends, imported by bash before the script
  runs) cannot hijack the computation and redirect `source` at an attacker tree.
  No behavior change in production.

## [0.18.2]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

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
