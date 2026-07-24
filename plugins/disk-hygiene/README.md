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
  engine — deferring everything else instantly — and enforces the configured kill switch and
  data-root authority through plugin-hook substitution. **Caveat (verified on Claude Code 2.1.218):**
  that gate only registers once `disk_hygiene_enabled` is **explicitly configured**. Upstream never
  implemented the declared userConfig `default`, so while the option is unset its
  `${user_config.disk_hygiene_enabled}` argument is neither substituted nor exported, and its
  presence **drops the whole hook entry** — the gate does not run at all, on either tool. The
  skill-scoped belt below carries no such token and is unaffected. And the
  skill-scoped **belt** inside the `clean` skill's context, which adds the deny-by-default Bash and
  deletion-spelling PowerShell discipline during active cleanup work. Hook-lifetime caveat: docs
  scope a skill hook to the component's lifetime, but session-long firing of the belt has been
  observed on at least one Claude Code build (producer-reported; see issue #1105) — if unrelated
  commands are denied after a clean run ends, start a new session and see that issue. PreToolUse
  hooks also fire inside subagents, so fanned-out workers run under the same guards. The plugin
  never downloads a runtime.
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
  mode. When the value is **explicitly configured `false`**, the plugin-level engine gate receives it
  by exec-form substitution and denies engine invocations outright. **Caveat (verified on Claude Code
  2.1.218):** this holds only for a configured value — because upstream never implemented the declared
  userConfig `default`, an *unset* `disk_hygiene_enabled` is neither substituted nor exported, and its
  presence in the gate's args drops the whole hook, so on a default (unconfigured) install the engine
  gate does not run at all. The skill self-enforcement (kill-switch probe + skill-content value) is
  therefore the primary kill-switch honoring on a default install, not a redundant layer; the
  skill-scoped belt cannot receive the value either (skill-frontmatter hooks get neither
  `${user_config.*}` substitution nor `CLAUDE_PLUGIN_OPTION_*`) and still forces a human prompt before
  every mutation.
- **Trust-surface record (0.7.0):** the plugin-level `hooks/hooks.json` PreToolUse registration is a
  NEW trust surface (a hook that launches in every consumer session **once `disk_hygiene_enabled` is
  explicitly configured** — see the caveat below), added deliberately for guard-enforced audit-only
  mode and data-root authority (#1106 decision, Option E — split registration). Its blast radius is
  bounded by design: exec form (no shell), bundled standard-library script only, instant no-output
  deferral for any command not referencing the engine, and no new capability beyond what the
  skill-scoped deployment already did during active cleanup. Known costs, accepted: one `python3`
  launch per Bash/PowerShell call **on a configured install**, and on a machine where `python3`
  resolves to the Windows Store alias stub the launch fails on every call (tracked with remediation
  detection in #1110). **Caveat (verified on Claude Code 2.1.218):** while `disk_hygiene_enabled` is
  unset, the bare `${user_config.*}` argument drops the whole hook, so on a default install this hook
  does not register or launch at all — neither the trust surface nor its per-call cost applies until
  the option is configured. This entry is the plugin-acceptance review delta for the
  change. A direct `hygiene.py` invocation outside that skill does not read the toggle and
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
