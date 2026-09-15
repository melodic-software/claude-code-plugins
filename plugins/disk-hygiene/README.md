# disk-hygiene

`/disk-hygiene:clean` audits an arbitrary directory tree for abandoned temporary files, stale locks,
failed atomic-write remnants, empty leftovers, and similar disk residue. It is a context-aware audit,
not a static delete list: bundled patterns are discovery hints only, and every finding needs evidence
that it is not work product.

The default lane is read-only. Cleanup is available only through a fresh, exact-path preview followed
by explicit approval of one confidence tier. The engine then rechecks every candidate before removing
only the entries captured in the snapshot; it never follows links or recursively deletes an
unvalidated tree.

## Safety contract

- The side-effecting skill is manual-only (`disable-model-invocation: true`). Automated, scheduled,
  remote, or otherwise unattended sessions audit and stop.
- Confidence controls report ordering, never authorization. High, medium, and low each require a
  separate approval naming every path and its logical byte count.
- Filesystem roots, mount targets, OS-managed roots on every Windows volume, user shell-folder roots,
  VCS metadata/tracked content, mount points (including Linux bind mounts), every Windows reparse
  point, symlinks, entries changed since the scan, and paths outside the target are hard stops. These
  predicates cannot be disabled by policy.
- A live-handle preflight runs immediately before deletion. Windows uses an exclusive `CreateFile`
  probe for every entry. Linux/macOS require `lsof`; absence, incomplete authority, or diagnostics
  produce `handle_state_unverified` and block the tier. The plugin never elevates itself.
- Managed state is always a report-only handoff to the owning product's documented cleanup/GC command.
  A dry-run result is evidence for the report, never authorization for this engine to remove it.
- The skill-scoped guard is a fail-closed allowlist. It permits only canonical bundled scan/preview
  calls made from literal shell words, returns `ask` for the one canonical apply shape, and denies
  every other Bash command. Brace, tilde, parameter, command, arithmetic, process, word-splitting,
  filename, redirection, and operator syntax is rejected before argument parsing.
- Deletion walks the validated snapshot bottom-up. New entries are not traversed; they make the
  directory non-empty and therefore skipped. After captured children are removed, a directory is
  reopened with `O_NOFOLLOW`, checked empty through its descriptor, and matched by device, inode, and
  type immediately before descriptor-relative `rmdir`. The report separates removed, locked, changed,
  protected, needs-elevation, and unverified outcomes and records logical bytes plus observed
  free-space delta.

The execution lane is Linux-only. It reads the current mount namespace from `/proc/self/mountinfo`,
re-discovers protections and Git state, opens every parent through `O_NOFOLLOW` directory descriptors,
checks the descriptor identities against the snapshot, and calls descriptor-relative `unlink`/`rmdir`.
Windows and macOS retain the complete audit/report lane but return `execution-platform-unsupported`
at preview. Backups remain the recovery boundary for user data.

## Requirements and platform support

- Python 3.11+ available on `PATH` is required for scanning, validation, the skill-scoped guard, and
  cleanup (the floor's single origin is the `MIN_PYTHON` constant in
  `skills/clean/scripts/hygiene.py`; `/disk-hygiene:setup check` derives the enforced value from
  there, so treat the number printed here as a convenience copy). Claude Code launches the guard in
  shell-free exec form; guarded engine calls must use the same absolute interpreter reported by that
  guard, so Bash aliases and functions cannot replace it. The guard registers on two surfaces: a
  plugin-level **engine gate** (`hooks/hooks.json`) that acts only on commands referencing the
  engine — deferring everything else instantly — and enforces the kill switch and data-root
  authority; and the skill-scoped **belt** inside the `clean` skill's context, which adds the
  deny-by-default Bash and deletion-spelling PowerShell discipline during active cleanup work. Both
  surfaces resolve the kill switch by reading `disk_hygiene_enabled` from user-scope `pluginConfigs`
  in `settings.json` (located from `${CLAUDE_PLUGIN_ROOT}`, honored only from user/managed/`--settings`
  scope since Claude Code 2.1.207, so a repo cannot forge it), register unconditionally, and fail
  closed to enabled — the earlier bare-`${user_config.*}` argument that dropped the engine gate on a
  default install is gone (since 0.9.0). Hook-lifetime caveat: docs
  scope a skill hook to the component's lifetime, but session-long firing of the belt has been
  observed on at least one Claude Code build (producer-reported; see issue #1105) — if unrelated
  commands are denied after a clean run ends, start a new session and see that issue. PreToolUse
  hooks also fire inside subagents, so fanned-out workers run under the same guards. The plugin
  never downloads a runtime.
- **A silent engine-gate launch/runtime failure is now surfaced (since 0.9.5, #1416).** A `Stop`-event
  detector (`skills/clean/scripts/guard_launch_monitor.py`, a second hook entry in `hooks/hooks.json`,
  independent of the engine-gate guard itself) scans the session transcript for
  `hook_non_blocking_error` records naming the engine gate's own command string and warns once per
  session with the failure count and the most recent failure's exit code, duration, and stderr — so a
  guard that never ran or died mid-run no longer looks identical to a guard that ran and approved.
  This covers only the `destructive_guard.py` command string in the current session's transcript: it
  does not cover repo-hygiene's own guard (a separate plugin, verified working independently), and it
  never retroactively scans a prior session's transcript. It is also wired with the same literal
  `python3` command as the guard it watches, so the interpreter-resolution failure below — the
  WindowsApps alias stub, or a missing/broken `python3` — takes the detector down with the guard and
  goes unreported (#1504).
- Git is optional for ordinary trees. If a target contains or sits inside a Git worktree, Git becomes
  required so tracked content can be proven safe; otherwise cleanup for that subtree is blocked.
- Windows has the full **audit** lane (Python 3.11's `lstat` reparse metadata plus Win32 APIs
  exposed by the OS; never invokes UAC) but engine **execution is unsupported**: `preview` reports
  `execution-platform-unsupported` as a per-candidate blocker, and removal is a manual, per-path
  Recycle-Bin handoff offered only when `--execute` was requested and after explicit approval
  (the flag gates every deletion lane, manual included). The Recycle-Bin / Trash naming is a model-layer
  distinction only — the engine treats Windows and macOS identically (execution unsupported); which
  reversible-removal container the manual lane prefers is the model's instruction, not engine
  behavior.
- **Windows `python3` gotcha — the Store alias stub fails the guard open.** The `clean` guard hook
  launches the literal command `python3`. On stock Windows that name resolves to a zero-length
  `WindowsApps\python3.exe` App Execution Alias — a reparse stub that opens the Microsoft Store (or
  exits) instead of running an interpreter, so the guard process never starts. A PreToolUse hook
  blocks a tool call only by emitting exit code 2 or a `deny` decision ([Hooks](https://code.claude.com/docs/en/hooks));
  a guard that never runs emits neither, and Claude Code treats the non-blocking result as approval —
  the destructive Bash/PowerShell command proceeds ungated (the same fail-open shape as the 0.6.3
  launch-failure fix, via a different vector). `/disk-hygiene:setup check` detects this explicitly and
  FAILs: disable the `python3` App execution alias (Settings > Apps > Advanced app settings > App
  execution aliases) or install real Python and ensure it precedes WindowsApps on `PATH`. A bare
  `command -v python3` / `where python3` success is not proof the interpreter is real — the stub
  answers to the name too.
- Linux requires readable `/proc/self/mountinfo`, descriptor-relative filesystem APIs, and `lsof` for
  the optional execution lane. Absence, diagnostics, or authority gaps block cleanup.
- macOS supports audit/report only because this implementation has no authoritative bind-mount and
  descriptor-anchoring proof for its execution lane.

Verify this machine's prerequisites and platform posture with `/disk-hygiene:setup check`;
`/disk-hygiene:setup apply` resolves anything the check reports with guidance.

## Usage

```text
/disk-hygiene:clean <target-directory>
/disk-hygiene:clean --policy <policy.json> <target-directory>
```

The skill stores snapshots, plans, and reports under `${CLAUDE_PLUGIN_DATA}`. It never writes generated
state into the installed plugin directory or the audited target.

Policy files all share one shape:

```json
{
  "version": 1,
  "disabled_hint_ids": ["common-lock-file"],
  "additional_hints": [
    {
      "id": "my-tool-staging",
      "os": ["all"],
      "kind": "name_glob",
      "pattern": "my-tool-stage-*",
      "confidence_ceiling": "medium",
      "reason": "My tool's documented staging-directory convention"
    }
  ],
  "additional_protected_path_globs": ["client-deliverables/**"]
}
```

Without `--policy`, standing policy files layer over the baseline when present:
`~/.claude/disk-hygiene.json` (user-global) first, then the consumer project's
`.claude/disk-hygiene.json`. An explicit `--policy` file is the invocation-specific choice and
replaces both standing layers. The scan output records which sources applied.

Candidate hints can be disabled or extended. Consumer protection globs are additive. Hard safety
predicates and the baseline protected-name/root rules are non-overridable by any layer: a policy
file can only add protections, add hints, or disable discovery hints (which can only cause junk to
be missed, never removed).

When the audited zone overlaps the user temp directory, the scan also reports an `os_autoclean`
advisory naming the OS mechanism that should own it (Windows Storage Sense, systemd-tmpfiles) and,
when that mechanism is off or set to fire only on low disk space, recommends enabling it rather than
hand-cleaning the zone.

## Relationship to other tools

- Use `/repo-hygiene:clean` for deterministic caches, build outputs, Git metadata, or a fresh-pull reset
  inside one repository. `disk-hygiene` does not duplicate those mechanisms.
- Use `/source-control:worktree status`/`cleanup` (if installed) for git worktree checkouts such as a
  `.worktrees/` tree — run those actions from the checkout's own main repository, as they manage the
  current repository's worktrees and take no target. `disk-hygiene` protects tracked content and `.git`
  metadata but does not manage worktree lifecycle.
- Use a product's own prune/GC/uninstall command for state it owns. This skill reports the handoff and
  records the native result but never makes managed state eligible for engine execution.
- `git clean` remains the authority for ignored/untracked repository files. This plugin protects every
  tracked path and does not emulate Git's path rules.

## Plugin-acceptance security review

- **Code execution:** the plugin runs bundled, standard-library Python. The skill-scoped PreToolUse
  guard denies every unknown Bash command, permits only canonical bundled scan/preview calls, and
  forces a final permission prompt for the canonical engine apply call. The guard rejects shell
  expansion and operator syntax instead of validating only the post-split argument vector; script
  identity follows the host path rules and remains case-sensitive on POSIX. No `eval`, dynamic shell
  construction, or downloads are used. Paths cross the process boundary as JSON or individually
  quoted CLI arguments.
- **MCP / external trust:** no MCP server, agent, dependency, or third-party service is shipped.
- **Configuration:** one non-sensitive `userConfig` boolean (`disk_hygiene_enabled`, default
  `true`) gating the execution tiers — setting it `false` puts `/disk-hygiene:clean` in audit-only
  mode. Both guard surfaces resolve the toggle by reading `disk_hygiene_enabled` from user-scope
  `pluginConfigs` in `settings.json` (not the process environment). A configured `false` denies Bash
  engine invocations outright on the always-on engine gate (whether or not the clean skill is active);
  PowerShell deletion spellings are denied outright by the skill-scoped belt while `/disk-hygiene:clean`
  is active (the always-on gate defers on non-engine commands). The read is honored only from user, managed, and
  `--settings` scope (Claude Code 2.1.207+), so a project or local repo `settings.json` cannot flip
  it; the user file is located from `${CLAUDE_PLUGIN_ROOT}`, not from repo-redirectable environment, and
  the managed (enterprise) file at its fixed system path wins as the highest-precedence scope so an org
  can enforce audit-only (the sibling `managed-settings.d/` drop-in directory is merged over it). An absent
  or unreadable value fails closed to enabled. The one residual a hook cannot read is a value supplied only
  via a session `--settings` file. The skill's own kill-switch probe + skill-content value remain a
  defense-in-depth honoring layer over the guard.
- **Trust-surface record (0.7.0; updated 0.9.0):** the plugin-level `hooks/hooks.json` PreToolUse
  registration is a NEW trust surface (a hook that launches in every consumer session), added
  deliberately for guard-enforced audit-only mode and data-root authority (#1106 decision, Option E —
  split registration). Its blast radius is bounded by design: exec form (no shell), bundled
  standard-library script only, instant no-output deferral for any command not referencing the engine,
  and no new capability beyond what the skill-scoped deployment already did during active cleanup.
  Known costs, accepted: one `python3` launch per Bash/PowerShell call, and on a machine where
  `python3` resolves to the Windows Store alias stub the launch fails on every call (tracked with
  remediation detection in #1110). **0.9.0 delta:** the gate no longer carries a `${user_config.*}`
  argument (which, unset, dropped the whole hook and left the gate inert on a default install); it now
  registers unconditionally and resolves the kill switch by **reading** the user `settings.json` and the
  platform managed-settings.json. The added trust surface is that settings-file *read* — bounded to a
  single `pluginConfigs` value, from the user file (located from `${CLAUDE_PLUGIN_ROOT}`) and the
  root-owned managed file at its fixed system path, no write. Both are the plugin's own documented CC
  config, sanctioned by the acceptance review's operator-home carve-out (criterion 4). This entry is the
  plugin-acceptance review delta for the change. A direct `hygiene.py` invocation outside that skill does not read the toggle and
  answers only to the engine's own preview/approval-token gate. The toggle can only narrow the
  destructive surface, never widen it (see [the safety model](skills/clean/reference/safety-model.md)
  for the degraded-mode detail). No credentials. Policy comes from an explicit invocation
  argument or standing `disk-hygiene.json` files under `~/.claude/` and the consumer project's
  `.claude/`. All policy input is pattern-only and additive: it can add protections and discovery
  hints or disable hints, and cannot weaken hard guards or authorize removal, so ambient config
  cannot widen the destructive surface.
- **Isolation:** bundled assets resolve from `${CLAUDE_PLUGIN_ROOT}`; generated state belongs under
  `${CLAUDE_PLUGIN_DATA}`. The audited target is read, then mutated only through the gated lane.
- **Egress:** none. `git` and `lsof` are local read-only subprocesses.
- **Provenance:** Melodic Software, MIT. No vendored code.

Security review result: **accept** for the declared local code-execution surface. Any later network,
credential, dependency, or MCP surface reopens this review.

## Sources

Verified 2026-07-16 against current primary documentation:

- [Create plugins](https://code.claude.com/docs/en/plugins) and
  [plugins reference](https://code.claude.com/docs/en/plugins-reference) — plugin structure, cache
  isolation, manifests, versions, and local `--plugin-dir` testing.
- [Skills](https://code.claude.com/docs/en/skills) — side-effecting skills should be manual-only;
  supporting files, arguments, and skill-scoped hooks.
- [Hooks](https://code.claude.com/docs/en/hooks) — current `PreToolUse` decision output.
- [Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — relative plugin sources.
- [GNU Bash shell expansions](https://www.gnu.org/software/bash/manual/html_node/Shell-Expansions.html)
  — expansion order and the brace, tilde, parameter, command, arithmetic, process, splitting, and
  filename-expansion families rejected by the literal-command guard.
- [Python 3.11 filesystem APIs](https://docs.python.org/3.11/library/os.html) and
  [path APIs](https://docs.python.org/3.11/library/os.path.html) — non-following metadata, junction, and
  mount detection.
- [Windows reparse-point operations](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-operations)
  and [`GetLogicalDrives`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getlogicaldrives)
  — the reparse attribute and available-volume enumeration.
- [Linux `mountinfo`](https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html) — current mount
  namespace and bind-mount targets, which `os.path.ismount` cannot reliably identify.
- [Git `ls-files`](https://git-scm.com/docs/git-ls-files) — the index/tracked-file authority.
- [Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
  — sharing conflicts and directory handles via `FILE_FLAG_BACKUP_SEMANTICS`.
- [`lsof` maintained documentation](https://lsof.readthedocs.io/en/stable/) — open-file lookup; the
  recursive `+D` authority limitation is why diagnostics fail closed.
- [POSIX `unlink`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/unlink.html) and
  [Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html) — open-file unlink semantics
  motivate an explicit preflight rather than relying on deletion failure.

## License

MIT (SPDX-License-Identifier: MIT). See the repository root `LICENSE`.
