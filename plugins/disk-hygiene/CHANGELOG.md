# Changelog

All notable changes to the `disk-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.3]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.9.2]

### Fixed

- **The anchored target root is validated by object identity, so benign directory churn no longer
  aborts an approved run (#384).** Preview and apply held the target root to full stat identity
  (`st_mtime_ns` and `st_size` included), but a directory's mtime and size flip whenever any direct
  child is added or removed. Human approval sits between scan and apply, so any unrelated write into
  a live target — a home or an active project root, the common case — flipped the root's mtime and
  aborted the run with "anchored target changed since the snapshot," forcing a full rescan. Both
  sites now use the stable device/inode/type identity that directory candidates and `handoff-verify`
  already use; a replaced root still refuses. The check was never wrong-deleting, only over-refusing.

### Changed

- **`resolve_snapshot_target` no longer takes `strict_root_stat`.** With one root-identity standard
  across preview, apply, and `handoff-verify`, the parameter that selected between them is gone and
  the single refusal reads "target root was replaced since the snapshot."

## [0.9.1]

### Changed

- **The PowerShell lane's documented coverage now names what it does not flag (#386).**
  `reference/safety-model.md` and the clean skill's PowerShell gotcha described the lane as gating
  "known deletion spellings" without stating that destructive non-deletion spellings — `Move-Item`,
  `Rename-Item`, overwriting writers (`Set-Content`/`Out-File`/`>`/`New-Item -Force`), and
  `Format-Volume`/`Clear-Disk` — reach the tool with no guard verdict, audit-only mode included. The
  gap is now disclosed where the security model is stated, naming the consumer's permission policy as
  its only backstop — the manual handoff's per-path approval covers the paths selected for removal, so
  it does not reach what these spellings collaterally destroy. Docs only; the guard's behavior is
  unchanged and closing the gap is tracked in #387.

## [0.9.0]

### Fixed

- **The `disk_hygiene_enabled` kill switch now enforces on both guard surfaces — closing the
  inert-by-default engine gate (#1019).** Through 0.8.3 the plugin-level engine gate (`hooks/hooks.json`)
  carried a bare `${user_config.disk_hygiene_enabled}` argument. Because the declared userConfig `default`
  is unimplemented upstream (#46477 / #39455 / #39827), an unset-but-defaulted token dropped the whole hook
  entry, so on a default install the gate never ran; the skill-frontmatter belt could not receive the value
  either (skill hooks get neither the `${user_config.*}` substitution nor `CLAUDE_PLUGIN_OPTION_*`). Audit-only
  mode therefore degraded from deny-outright to prompt-gated. Both surfaces now resolve the toggle by
  **reading it directly** from user-scope `pluginConfigs` in `settings.json`, so a configured `false` is
  denied outright on the Bash engine lane and the PowerShell deletion lane, whether or not the clean skill
  is active.

### Changed

- **Kill-switch delivery is a settings read, not a hook argument or environment variable.** The engine gate
  drops its `${user_config.*}` argument (fixing the hook-drop) and both surfaces call the new shared
  `lib/killswitch_config.py` reader. The user `settings.json` is located **solely** from the
  tamper-resistant `${CLAUDE_PLUGIN_ROOT}` both surfaces receive — the guard never falls back to
  `CLAUDE_CONFIG_DIR`/`HOME` for it, because those are environment values a repo `.claude/settings.json`
  `env` block can inject into hook subprocesses (carrying no provenance). A marker-less `--plugin-dir`
  checkout root leaves no trusted user path, so the user scope is skipped and the switch relies on managed
  settings, failing closed to enabled otherwise. Since Claude Code 2.1.207 `pluginConfigs` is honored only
  from user, managed, and `--settings` scope (project/local ignored), so a hostile repo cannot forge the
  value. Every absent, unreadable, or ambiguous read fails **closed to enabled**.
- **Managed (enterprise) settings are honored as the highest-precedence scope.** The reader also reads the
  platform managed-settings.json (`/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/`
  on Linux/WSL, `C:\Program Files\ClaudeCode\` on Windows — a fixed path, not `%ProgramFiles%`-derived, so a
  repo `env` block cannot redirect it); a value configured there overrides the user file, so an organization
  can enforce audit-only mode; the sibling `managed-settings.d/` drop-in directory is merged over it
  (later files win). The reader also matches only this install's exact `<name>@<marketplace>` key
  (derived from `${CLAUDE_PLUGIN_ROOT}`), so another marketplace's `disk-hygiene` entry cannot mask it. The
  one residual: a value supplied only through a session `--settings` file (a runtime CLI flag no hook can
  observe) is not enforced by the guard.
- **`kill_switch_probe.py` now delegates to the shared reader** (its behavior and single-line JSON output
  contract unchanged) so the report-only probe and the guard resolve the switch one way, not two.
- Docs corrected across `clean`/`setup` `SKILL.md`, `reference/safety-model.md`, and `README.md`: the
  "engine gate is inert until configured" and "audit-only reaches only the model, not the guard" caveats
  are removed; the guard is again the audit-only backstop.

### Design note

- This supersedes the planned SessionStart-hook + state-file delivery ("C′"). Both guard surfaces are the
  same script funnelling through one resolve point, so there is nothing to distribute between sessions or
  surfaces: a direct read is a smaller trust surface (a settings *read*, no state-file *write*), honors a
  mid-session settings change, and needs no session-start timing dependency. Semantics are unchanged from
  the locked resolver decision — read user-scope `pluginConfigs`, ignore env, fail closed to enabled.

## [0.8.3]

### Fixed

- **RETRACTS 0.8.2's PowerShell claim, which was wrong (#1195).** 0.8.2 documented that "PreToolUse guards
  do not intercept PowerShell-tool commands" and scoped the PowerShell lane behind a preview caveat. A
  fresh-session controlled test falsified that: a `Bash|PowerShell` PreToolUse matcher **does** fire for the
  PowerShell tool on 2.1.218, the payload `tool_name` is literally `PowerShell`, and a live `Set-Content`
  through that tool was blocked. There is no harness firing divergence and no preview limitation involved —
  0.8.2's caveat overstated an un-isolated inference and is removed.
- **The real defect, now documented accurately: the plugin-level engine gate is inert whenever
  `disk_hygiene_enabled` is unconfigured.** `hooks/hooks.json` passes a bare
  `${user_config.disk_hygiene_enabled}`; upstream never implemented the declared userConfig `default`, so an
  unset-but-defaulted token is neither substituted nor exported as `CLAUDE_PLUGIN_OPTION_*` and its presence
  **drops the entire hook entry** (proven: token-carrying hooks vanish while token-free controls fire, and
  return once the key is configured). So the gate has never run for any consumer who never set the key — on
  Bash and PowerShell alike, which is the real shape of the reported "PowerShell bypass". The skill-scoped
  belt carries no such token and is unaffected. Every doc that claimed the gate "fires in every session"
  or that audit-only mode is "guard-enforced" corrected: the `clean` and `setup` `SKILL.md` files,
  `reference/safety-model.md`, and the consumer `README.md`. The code fix (a delivery channel that does
  not depend on the unimplemented `default`) is tracked separately.
  Recheck when the upstream gap closes (#46477 / #39455 / #39827).

## [0.8.2]

### Fixed

- **Docs no longer promise PowerShell-tool deletion protection that does not fire on current builds
  (inbox `173656`).** `skills/clean/SKILL.md` and `reference/safety-model.md` asserted the PowerShell
  guard belt "turns deletion spellings into a final human permission prompt" and that a configured
  `disk_hygiene_enabled=false` blocks the PowerShell lane. On Claude Code 2.1.218 (Windows, reproduced)
  a `Bash|PowerShell` PreToolUse hook fires for the Bash tool but does **not** intercept
  PowerShell-*tool* commands — the PowerShell tool is a documented *preview* feature
  ([tools-reference](https://code.claude.com/docs/en/tools-reference)) and PreToolUse interception of it
  is not a listed preview limitation, so the belt and the kill switch's reach into the manual PowerShell
  lane are inert there. The claims are now scoped as the guard's *intended* design with an explicit
  version-pinned preview caveat + recheck trigger; on Windows the protections that actually hold are the
  manual lane's per-path `handoff-verify` approval and the consumer's baseline permission policy.
  Observed effect only — the mechanism (matcher firing vs Windows payload delivery vs `tool_name`) is not
  yet isolated (recheck by adding a logging `PreToolUse` `matcher: "PowerShell"` hook in a fresh session
  and confirming it fires for a PowerShell-tool command); the upstream docs-vs-behavior divergence is
  held for a report once isolated.

## [0.8.1]

### Changed

- **`--execute` now gates every deletion lane, including the manual handoff (#1113, F7).** A
  deliberate semantic unification, not a restatement: the flag previously read as "offer the gated
  ENGINE lane", which can never apply on Windows/macOS — leaving the manual lane's gate ambiguous,
  and consumer sessions read it both ways (one proceeded to manual deletion without `--execute`).
  The clean skill now states the unified contract in one sentence at the argument definition and
  requires `--execute` in the manual-handoff precondition, for lane symmetry.

### Fixed

- **Doc corrections from the 0.6.4 consumer audit (#1113, F9/F10).** Safety-model trust boundaries
  now name standing-policy `additional_hints[].reason` prose as untrusted claims requiring
  independent evidence (additive-only design means hints cannot authorize, but the prose reached
  triage reasoning unlabeled). Setup SKILL.md and the README now say `preview` *reports
  `execution-platform-unsupported` as a per-candidate blocker* rather than "returns" it (it was
  never a top-level status), and the README states once that the Recycle-Bin / Trash naming is a
  model-layer distinction only — the engine treats Windows and macOS identically. F10(c)'s
  restructure-the-hub suggestion is DECLINED with evidence: the repo's `.markdownlint-cli2.jsonc`
  sets `"MD013": false` (no line-length rule — the complaint came from an out-of-repo lint run) and
  the skill-quality gate passes the hub at its current length.

## [0.8.0]

### Added

- **`hygiene.py handoff-verify` — deterministic revalidation for the manual lane (#1109).** New
  read-only subcommand: takes the snapshot plus the human-approved exact path list
  (`{"version": 1, "paths": [...]}`, same containment rules as plan candidates) and reruns the
  engine's identity/reparse/protection/descendant/VCS/handle checks per path against live state,
  emitting one machine-readable verdict each — `clear` / `drifted` / `gone` / `contested` — and
  never deleting anything. Platform execution blockers deliberately do not apply (the subcommand
  exists exactly where apply is unsupported); every unverifiable condition fails closed into
  `contested`. Exit 0 all-clear, exit 3 otherwise. The target-root gate reuses preview's checks but
  tolerates the root directory's own metadata churn (stable device/inode/type identity instead of
  full stat identity — deleting an approved root-level item changes the root's mtime, and the
  manual lane deletes one item at a time with a re-verify between items); a replaced root still
  refuses. The clean skill's manual-handoff lane now writes `handoff-paths.json`, runs
  handoff-verify immediately before deletion, and acts only on verdict-`clear` paths — bringing
  snapshot binding to Windows/macOS without adding an engine deletion lane (captures most of the
  declined F12 value; #1116's affirmation records this as the intended alternative). The Bash
  guard admits the exact `handoff-verify --snapshot <s> --paths <p> [--data-root <d>]` shape as a
  read-only invocation, including in audit-only mode (kill switch keeps blocking every deletion
  lane; verification is reporting). Safety model documents the verdict vocabulary and the
  emission-time-only validity of `clear`.

## [0.7.3]

### Added

- **Test coverage for the least-observable engine paths (#1114).** Test-only release — no engine
  behavior change. The paths a consumer can least verify live now have direct tests with mocked OS
  surfaces, exercised identically on both CI lanes regardless of host platform:
  `windows_handle_state` CreateFileW error-code mapping (32/33 → open, 5/1314 → needs_elevation,
  unknown codes fail closed as unverified; handle closed on success; directory probes use
  backup semantics), `posix_handle_state` lsof parsing (missing lsof, diagnostics on stderr,
  unexpected exit codes, and timeouts all fail closed; directory vs file command shapes),
  `windows_storage_sense_state` registry reads (set/zero/missing values, missing key),
  `_decode_mountinfo_path` octal decoding (escapes, non-octal and truncated sequences left
  verbatim), and the non-Git VCS marker branch (nested, enclosing, and casefolded markers all
  flag `vcs-state-unverified`). No latent engine bugs surfaced while writing them.

## [0.7.2]

### Fixed

- **PowerShell lane narrows the engine deny from substring to invocation classification (#1112).**
  The lane denied ANY command containing the substring `hygiene.py` — blocking commands that
  merely NAME the script (live-observed, F6) while a renamed copy evaded it anyway. The engine
  check now uses the same invocation classifier as the plugin-level gate (bundled-file identity +
  launcher rules): bare-name and consumer-file mentions defer. Deliberately NOT deferred: a
  command whose argument IS the bundled engine, even under a read-verb spelling
  (`Get-Content <engine>`) — PowerShell aliases and profile functions shadow cmdlet names, so a
  verb name proves nothing about what executes (review finding); the deny message points at
  non-shell file tools for reading the engine source.

## [0.7.1]

### Fixed

- **PowerShell mutation guard covers instance-method `.Delete()`, and robocopy mirror/purge/move
  (#1111).** The .NET-delete pattern required `::` before `delete`, so `$item.Delete()` executed
  with no guard flag (live-observed in the 0.6.4 consumer audit, F4); it now also matches
  `.Delete(`. `robocopy` with `/MIR`, `/PURGE`, `/MOV`, or `/MOVE` (mass deletion via mirroring)
  now raises the final ask prompt and is denied in audit-only mode; plain `robocopy /E` copies
  stay untouched. The truncation family (`Set-Content`, `Out-File`, `New-Item -Force`) is
  DECLINED with reason: those spellings are ordinary file-writing work, and an ask-tier belt that
  fires on every write during a cleanup session trades too much friction for a raised bar the
  engine's own containment already backs — design stays raised-bar-not-fail-closed.

## [0.7.0]

### Added

- **Split guard registration — plugin-level engine gate delivers the kill switch and data-root
  authority (#1105, #1106, #1107).** The destructive guard now registers on two surfaces. A NEW
  plugin-level `hooks/hooks.json` PreToolUse hook runs `destructive_guard.py --mode engine-gate`
  with `${user_config.disk_hygiene_enabled}` and `${CLAUDE_PLUGIN_DATA}` substituted in exec form
  (both channels docs-verified) — so a configured `false` (audit-only mode) is guard-enforced
  against engine invocations in every session, and `--data-root` authority no longer depends on
  reconstruction from the plugin root. In engine-gate mode the guard defers instantly with no
  output for any command that does not reference the engine, so unrelated work is never taxed. The
  skill-scoped belt (deny-by-default Bash + deletion-spelling PowerShell discipline) is unchanged
  and remains scoped to active cleanup. The gate acts on parsed engine INVOCATIONS, not mentions —
  `git diff -- hygiene.py`, `rg hygiene.py`, or `echo hygiene.py` defer, a word resolving to a
  DIFFERENT existing file named `hygiene.py` (a consumer's own tool) defers, and interpreter
  options before the script (`python3 -B`) cannot slip the gate; unparsable
  marker-carrying commands fail closed into the gate (review finding on the implementation PR). GuardTests now exercise the exact channel set the shipped
  plugin-level registration receives (`run_guard_engine_gate` grid), closing the
  tests-prove-undelivered-channels gap. Trust-surface delta recorded in the README's
  plugin-acceptance security review section. Docs record the observed-vs-documented hook-lifetime
  discrepancy (session-long belt firing, producer-reported — #1105 tracks the interactive repro)
  and that PreToolUse hooks fire inside subagents. The maintainer's re-affirmation of the
  Windows-engine-execution decline (#1116) is recorded in the safety model with its reversal
  trigger.

## [0.6.5]

### Fixed

- **Manual-handoff lane: container-wide deletions now require immediate pre-execution
  re-enumeration (#1108).** An approval for a container-wide operation (`Clear-RecycleBin`,
  emptying the Trash) was bound to a prose item list that could go stale between approval and
  execution — items landing in the container after approval would be destroyed under an approval
  that predated their existence (a live near-miss in the 0.6.4 consumer audit, F2). The clean
  skill's unsupported-platform handoff now forbids container-wide deletion commands outright —
  review showed even immediate re-enumeration leaves an approval-to-execution window against a
  live container — and satisfies "empty the container" by per-item deletion under the lane's
  per-path revalidation, so unenumerated arrivals survive. Also documents that Recycle Bin / Trash reversibility is conditional: bin size caps,
  policy-disabled bins, or non-NTFS/network volumes can silently make removal permanent.
  `Clear-RecycleBin` added to the PowerShell guard's mutation words, and module-qualified
  deletion cmdlets (`Module\Remove-Item`, `Module\Clear-Content`, `Module\Clear-RecycleBin`) now
  match a companion pattern the word boundary's lookbehind previously rejected (review findings
  on the same PR; the guard word is defense-in-depth for attempted container ops, which the
  manual lane now forbids) — the broader F4 spelling additions
  (`.Delete(`, robocopy purge flags) remain tracked in #1111. Engine-side changed-since-scan
  gotcha now cross-references the manual lane's re-enumeration rule (closes #1108's third
  acceptance criterion in both directions).

## [0.6.4]

### Fixed

- **A non-OS volume root (e.g. a Windows Dev Drive) is no longer blanket-rejected (#984).** A
  whole-volume root was refused purely structurally — on Windows by the mount-point gate (every drive
  letter is `os.path.ismount` True), backed by a `parent == root` filesystem-root check — with no
  reasoning about the volume's purpose, blocking a legitimate non-OS volume. Root classification is
  now reasoned: an OS-managed root (the OS drive holding an existing Windows install / `Program Files`
  / `ProgramData`, or `/` holding `/bin`, `/etc`, …) is still denied, while a non-OS volume root — a
  drive root carrying only the per-volume metadata every volume has (`System Volume Information`,
  `$Recycle.Bin`) and no OS-install marker — is now a valid target. The target-level mount rejection
  is scoped to non-root mount points, so nested and bind mounts stay hard-blocked; per-entry
  mount/OS-managed/VCS/identity protections and the preview + per-tier approval gate are unchanged.
  Scan and preview share one unverified → OS-managed → non-root-mount target-check ordering. A
  now-valid non-OS volume root composes with the large-target scan gate (0.5.0): it is a known-large
  root (`large_scan_reasons` reason `non-os-volume-root`), so an unbounded whole-volume walk returns
  `large-target-confirmation-required` unless bounded with `--max-depth` or confirmed with
  `--confirmed-large-scan`.

## [0.6.3]

### Fixed

- **The destructive-action guard was failing open on the bundled `clean` skill.** The
  skill-frontmatter PreToolUse hook passed `--authorized-data-root ${CLAUDE_PLUGIN_DATA}` in its
  args, but Claude Code refuses to launch a skill-scoped hook that references `${CLAUDE_PLUGIN_DATA}`
  (it is plugin-only; only `${CLAUDE_PLUGIN_ROOT}` is available to skill hooks) and treats the failed
  launch as a non-blocking error — so the guard silently never ran and `rm -rf`, engine `apply`, and
  the PowerShell deletion belt were all ungated. This recurs the fail-open shape earlier fixes
  addressed through a new vector (hook launch failure via an unsupported substitution token); the
  0.4.4 premise that "inline placeholder substitution resolves in exec-form hook args" does not hold
  for `${CLAUDE_PLUGIN_DATA}` in a skill-scoped hook.
  - The hook now passes only `--plugin-root ${CLAUDE_PLUGIN_ROOT}` — the sole substitution a skill
    hook receives — so it always launches. `destructive_guard.py` derives the authorized data root
    from the plugin root using Claude Code's documented persistent-data-directory layout
    (`<plugins>/data/<id>`, `<id>` = the sanitized `<name>@<marketplace>`). Every failure mode is
    fail-closed: an unrecognized layout yields no authority, so `--data-root` engine calls are denied
    while the destructive-action guard stays fully active. A direct `--authorized-data-root` and the
    `CLAUDE_PLUGIN_DATA` environment variable remain accepted as additional/fallback channels for
    hosts that can supply them.
  - **Known limitation (platform gap):** the `disk_hygiene_enabled` kill switch can no longer reach
    the guard on a skill-frontmatter hook. Its only channels are the `--disk-hygiene-enabled` argv
    flag (which needs the `${user_config.*}` substitution skill hooks do not receive) and the
    `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` environment variable (which the runtime does not
    inject into skill hooks). The guard therefore defaults to enabled and cannot honor a configured
    `false` by denying outright; it still forces a human prompt before every mutation, and the skill
    body's substituted value lets the model self-enforce audit-only. This never functioned on 0.4.6
    either (the hook did not launch at all), so it is a documented gap rather than a regression.
    Delivering the kill switch to a skill-scoped guard needs a channel skill hooks do not yet have.
    (#983)

## [0.6.2]

### Fixed

- **Windows platform posture no longer reads as if the engine deletes there.** `setup check`'s
  platform-posture step said "Windows (full, `lstat` reparse + Win32, never UAC)", but "full"
  described only the audit lane — `clean`'s preview returns `execution-platform-unsupported` on
  Windows and removal is a manual Recycle-Bin handoff. The posture line (and the README's Windows
  bullet) now keeps the lanes visibly separate: full **audit**; engine **execution unsupported**;
  manual, per-path Recycle-Bin handoff after explicit approval. macOS gains the matching manual
  Trash note.
- **"Skill-scoped guard" wording now says what the scope means.** The `destructive_guard.py`
  PreToolUse hook is registered in the `clean` skill's frontmatter and fires only within that
  skill's context; setup's own probes and any direct `hygiene.py` invocation rely on the engine's
  built-in containment, not the hook. One clause in `setup check` step 1 and the README
  requirements bullet now states this instead of implying always-on protection.
- **The security review's Configuration bullet no longer claims "no `userConfig`".** That claim
  has been stale since 0.3.0 introduced the `disk_hygiene_enabled` toggle; the bullet now
  describes the actual surface (one non-sensitive boolean that can only narrow the destructive
  surface) with the review conclusion unchanged.

## [0.6.1]

### Changed

- **The Python version floor now has one origin.** The "3.11+" floor was hand-maintained in at
  least five places — `hygiene.py`'s runtime check (the real enforcement), both `.test.sh`
  wrappers, both SKILL.md files, and the README — while the setup skill told itself to "probe
  what they actually require, don't recite this file"; a future bump would drift the copies
  silently. The floor is now the module-level `MIN_PYTHON` constant in `hygiene.py`: the runtime
  check and its error message derive from it, a regression test locks the constant's greppable
  line shape and proves enforcement uses it, both test wrappers parse it instead of restating
  the number (failing loudly if the parse breaks), `setup check` step 1 derives the probed floor
  from the constant, and the remaining prose mentions are annotated as pointers or convenience
  copies of that origin.

## [0.6.0]

### Added

- **Deterministic kill-switch probe** (`skills/setup/scripts/kill_switch_probe.py`): a report-only,
  stdlib-only read of the configured `disk_hygiene_enabled` value from
  `pluginConfigs[<plugin-id>].options` in the user `settings.json` (`CLAUDE_CONFIG_DIR`-aware). It
  emits one JSON line with the `effective` boolean, its `source`
  (`configured` / `default` / `indeterminate`), a `degraded` flag, and the matched entries. The
  guard's Bash allowlist now permits exactly the argument-free bundled probe invocation (any
  argument, bare `python`, or a different path stays denied).

### Fixed

- **`setup check` no longer reports the kill switch from an unexpanded body token.** Step 4
  previously emitted `${user_config.disk_hygiene_enabled}` in the skill body with the rule
  "unexpanded or empty means default `true`", so a configured `false` (audit-only mode) whose
  token failed to expand was misreported as enabled — a false-negative on the safety-critical
  setting the check exists to verify. Current plugin docs state non-sensitive `${user_config.*}`
  values substitute in skill content, but a live run observed the token unexpanded, so body-token
  expansion cannot be load-bearing for a safety report. `check` now reports the probe's
  deterministic result with provenance, degrades honestly ("could not read the configured toggle;
  assuming default `true`") when no definitive read is possible, and treats the body token as at
  most a cross-check whose contradiction is reported rather than silently resolved. The `clean`
  skill's audit-only instruction likewise stops treating an unexpanded token as "unset = enabled"
  and resolves the toggle through the same probe; enforcement remains with the guard's
  runtime-substituted `--disk-hygiene-enabled` hook argument (0.4.4).

## [0.5.0]

### Added

- **Engine-level large-target scan gate.** A `scan` whose target resolves to the user home directory
  now returns `large-target-confirmation-required` (after a cheap top-level probe, no full walk)
  unless it carries `--max-depth` or the new `--confirmed-large-scan` flag, backing the former
  prompt-only `--max-depth 1` convention with a deterministic backstop so a forgotten bound cannot
  become an accidental unbounded whole-home walk. The Bash guard accepts the valueless
  `--confirmed-large-scan` in the exact scan shape.

## [0.4.7]

### Fixed

- **The `clean` skill now hands off git worktree checkouts to `/source-control:worktree`.** An audit
  of a repos root containing worktree checkouts (e.g. under `.worktrees/`) inventories each checkout
  and protects its tracked content and `.git` metadata, but the skill named no next step for the
  worktree lifecycle it does not own. The boundary list (and the README relationship list) now point
  at `/source-control:worktree status`/`cleanup` (if installed) — run from the checkout's own main
  repository, since those actions manage the current repository's worktrees and take no target —
  extending the existing managed-state → named-handoff pattern. Discoverability only; no engine or
  safety behavior change. (#986)

## [0.4.6]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard_powershell` helper in
  `test_hygiene.py` — the enabled-PowerShell sibling of the three helpers sealed in 0.4.5 — carried
  the identical unsealed seam: it mocked `os.environ` to drive the kill switch but left `sys.argv`
  unpatched, so an ambient `--disk-hygiene-enabled` flag in the real test-runner invocation could
  override the env-var mock the test intends to exercise. It now patches `guard.sys.argv` to a
  clean, flag-free argv alongside its existing environment mock — matching the pattern the other
  four `run_guard*` helpers use — so the environment variable stays the sole channel under test.
  This completes the seam-sealing left out of 0.4.5 for scope; standard `unittest`/`pytest`
  invocations never produced such argv, so it seals latent fragility rather than a live failure.

## [0.4.5]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard`, `run_guard_disabled`, and
  `run_guard_powershell_disabled` helpers in `test_hygiene.py` mocked `os.environ` to exercise the
  kill switch but left `sys.argv` unpatched. Since the guard reads `--disk-hygiene-enabled` from
  `sys.argv[1:]` before the environment fallback, a test runner whose real invocation argv happened
  to carry that flag could override the env-var mock and flip an expected `deny` to `ask`. Each
  helper now patches `guard.sys.argv` to a clean, flag-free argv alongside its existing environment
  mock — matching the pattern the `run_guard_enabled_argv` helper already established — so the
  environment variable stays the sole channel under test. Standard `unittest`/`pytest` invocations
  never produced such argv, so this seals latent fragility rather than a live failure.

## [0.4.4]

### Fixed

- **The `disk_hygiene_enabled` kill switch now actually blocks deletions in audit-only mode.**
  Setting `disk_hygiene_enabled=false` (audit-only mode) failed to prevent deletions in two
  independent ways, both fixed here.
  - The PowerShell lane never consulted the kill switch: `destructive_guard.py` routed `PowerShell`
    calls to `powershell_decision` and returned before the enabled gate was computed, so flagged
    deletion spellings (`Remove-Item`, `rm`, `del`, `::Delete`, recycle-bin calls) still returned
    `ask` — and could be approved — even with execution disabled. The enabled gate is now resolved
    before the tool-name branch and threaded into `powershell_decision`, which denies flagged
    deletions in audit-only mode and only prompts (`ask`) when execution is enabled.
  - The kill switch was inert under the env-injection failure: the guard read
    `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` from the hook process environment and defaulted to
    enabled when absent, but the runtime does not inject plugin env vars into a skill-frontmatter
    hook's environment, so a configured `false` was silently overridden to enabled. The `clean`
    skill's hook now passes the configured value as a runtime-substituted
    `--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}` argument — inline placeholder
    substitution resolves in exec-form hook `args` where environment injection does not — and the
    guard reads the kill switch from that argument, honoring the environment variable only as a
    fallback. When no channel supplies a value the guard still fails safe to enabled (guard active,
    every mutation gated behind the final human prompt). This mirrors the `--authorized-data-root`
    argv mechanism.

## [0.4.3]

### Fixed

- **The `clean` skill's destructive-safety guard now launches via a resolvable `python3`.** The
  PreToolUse hook ran in exec form via the unqualified interpreter `python`, which stock macOS and
  many Linux distros do not ship (only `python3`). Because Claude Code treats a failed hook launch
  as a non-blocking error, an unresolvable `python` fails the guard open — `rm -rf`, engine `apply`,
  and other destructive shapes stop being intercepted on the very POSIX hosts the safety model
  relies on — and a legacy `python` 2.x resolving first would crash the guard on modern syntax. The
  hook now names `python3`. A new regression test (`test_skill_hook_interpreter_is_python3_and_resolves`)
  locks the config at `python3` and probes that a runnable `python3` reports a 3.11+ interpreter.
  Enforcement remains bounded by resolution: on a host without a resolvable `python3` the launch
  still fails open on the manual PowerShell deletion lane (engine `apply` is already unsupported on
  Windows/macOS), so the per-path human approval that lane already requires and the consumer's
  baseline permission policy stay the backstop, and `/disk-hygiene:setup check` reports interpreter
  resolution. (#380)

## [0.4.2]

### Fixed

- **The `clean` skill's step 2 now defines "suspicious" for home-directory targets.** A prior
  fix covered the `tmp_*` hint-glob gap but left two findings open: an unhinted agent-session
  status file has no shared name shape to glob, and SKILL.md never said what "suspicious"
  meant for an unhinted entry. Both are the same gap: the scan snapshot already records every
  walked entry with a possibly-empty `hints` list, so the data was always there, just never
  triaged. Step 2 now instructs the model to treat any loose root-level entry at a user-home
  target that is not in `protected_exact_names` and does not match a recognizable app/config
  convention as suspicious, closing the triage gap without inventing a fabricated
  baseline-policy.json glob for a naming pattern the evidence doesn't support. (#287)

## [0.4.1]

### Fixed

- **The skill-frontmatter guard now receives its authorized data root.**
  `destructive_guard.py` read the authoritative data root only from the
  `CLAUDE_PLUGIN_DATA` environment variable, which the runtime does not inject
  into a skill-frontmatter hook's process environment. As a result `--data-root`
  never validated and the `scan`/`preview`/`apply` engine lane failed closed on
  every guarded invocation, on all platforms. The `clean` skill's hook now
  passes the root as a runtime-substituted `--authorized-data-root
  ${CLAUDE_PLUGIN_DATA}` argument — inline placeholder substitution resolves in
  hook arguments where environment injection does not — and the guard reads its
  authority from that argument, honoring `CLAUDE_PLUGIN_DATA` only as a fallback.
  The security property is unchanged: the authority is a runtime-substituted
  value the model cannot forge, validated against the model-supplied
  `--data-root`. The unsubstituted-placeholder fallback matches only the exact
  `${CLAUDE_PLUGIN_DATA}` token, so a real data-root path that merely contains
  the `${` sequence is preserved as the authority instead of being discarded.

## [0.4.0]

### Added

- **`/disk-hygiene:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the clean skill's bundled scripts as the source
  of truth and probes Python 3.11+, conditional Git, the current OS family's
  documented lane (Linux `lsof` and macOS audit-only reported as INFO), and
  the effective `disk_hygiene_enabled` toggle. `apply` is guidance-only with
  no write path; toggle guidance states `--config`'s fresh-install-only
  semantics. A disabled toggle downgrades prerequisite FAILs to INFO.

## [0.3.0]

Fixes driven by a live Windows user-profile audit where the engine was unusable through its
sanctioned lane and the guard's protections did not cover the platform's primary shell.

### Added

- `--data-root` on scan, preview, and apply. The Bash guard validates the value against the
  `CLAUDE_PLUGIN_DATA` its own hook process received (the runtime exports it to hook processes but
  not to shell tool subprocesses, so the engine could previously never find its generated-state
  root through the guarded lane) and discloses the authorized value in denial guidance alongside
  the interpreter path. Absent hook authority the flag fails closed; the environment variable
  remains honored as a fallback.
- `--max-depth` bounded scans. Directories at the cutoff are recorded in `truncated_paths`,
  reported as coverage gaps, and blocked from plans by a new `truncated-not-inventoried` preview
  blocker. This makes a profile-root audit possible: the previous all-or-nothing walk exceeded the
  250k entry cap on any real home directory before reaching a single loose file.
- PowerShell guard lane (matcher now `Bash|PowerShell`): engine invocations from PowerShell are
  hard-denied (Bash stays the only engine lane), and known deletion spellings / .NET Delete calls
  surface a final human permission prompt instead of executing silently. Read-only support work
  passes through untouched.
- Documented unsupported-platform manual handoff: on Windows/macOS, after the same exact-list
  human approval as the engine lane, removal proceeds manually with per-path revalidation and
  reversible (Recycle Bin / Trash) deletion preferred.
- Scan progress heartbeat to stderr every 25k entries; the entry-cap error now suggests
  `--max-depth`.
- `os_autoclean` advisory is computed before the walk and included in scan failure payloads, so a
  capped profile scan still surfaces the Storage Sense / systemd-tmpfiles recommendation.
- Baseline hints for `tmp_*` (medium ceiling) and `scratch*` (low ceiling) artifacts.

### Changed

- Generated-state error messages name the `--data-root`/`CLAUDE_PLUGIN_DATA` pair instead of the
  environment variable alone.
- **Execution kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling): the `disk_hygiene_enabled` boolean (default `true`) now gates the clean
  skill's execution tiers, read by the skill-scoped guard through the native
  `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` hook-process mirror. Configure with
  `/plugin configure disk-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_DISK_HYGIENE_ENABLED` environment variable is retired and no
  longer read. Zero-config behavior is unchanged (execution allowed).
