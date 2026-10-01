# disk-hygiene

`/disk-hygiene:clean` audits an arbitrary directory tree for abandoned temporary files, stale locks,
failed atomic-write remnants, empty leftovers, and similar disk residue. It is a context-aware audit,
not a static delete list: bundled patterns are discovery hints only, and every finding needs evidence
that it is not work product. Safe tidiness is the primary objective; reclaimable bytes are a
secondary signal, so zero-byte and empty-directory residue stay visible in reports.

The default lane is read-only. Cleanup is available only through a fresh, exact-path preview followed
by explicit approval of one confidence tier, or, on Linux, through `handoff-apply` for one approved
standalone Git checkout. The engine then rechecks every candidate before removing only the entries
captured in the snapshot, except the Git metadata contents `handoff-apply` empties (see the safety
contract); it never follows links or recursively deletes an unvalidated tree.

## Safety contract

- The side-effecting skill is manual-only (`disable-model-invocation: true`). Automated, scheduled,
  remote, or otherwise unattended sessions audit and stop.
- The investigated-entry catalog under the plugin data root records what a run or the operator
  concluded about an entry. `prior_disposition` is a hint on the next scan. It never authorizes
  deletion or skips approval, preview, or revalidation.
- Confidence controls report ordering, never authorization. High, medium, and low each require a
  separate approval naming every path with provenance, what the entry is, why it is removable, and
  risk; logical / reclaimable byte counts come last and never drop empty directories from the
  ranking.
- Filesystem roots, mount targets, OS-managed roots on every Windows volume (unless addressed only
  via `--root-children` with an explicit child selection), user shell-folder roots,
  VCS metadata/tracked content, mount points (including Linux bind mounts), every Windows reparse
  point, symlinks, entries changed since the scan, and paths outside the target are hard stops. These
  predicates cannot be disabled by policy. The sole VCS exception is the evidence mode for an
  entire standalone Git checkout: `handoff-verify` reads it without changing anything, and on Linux
  `handoff-apply` runs the same checks and then deletes that one approved path. It requires empty
  porcelain status, every local head SHA confirmed through the checkout's GitHub remote, every stash
  SHA present in an independent checkout (or no stashes), and the existing exact-path operator
  approval. Without all four, categorical protection remains, except that an `accept_unpublished`
  acknowledgement on the evidence entry (one exact approved path, with a reason) waives the first
  two, the empty status and the heads confirmed on the remote, and the verdict reports them as
  accepted-unpublished. The stash gate and the exact-path operator approval still apply.
- A live-handle preflight runs immediately before deletion. Windows uses an exclusive `CreateFile`
  probe for every entry. Linux/macOS require `lsof`; absence, incomplete authority, or diagnostics
  produce `handle_state_unverified` and block the tier. The plugin never elevates itself.
- Managed state with no registry match is always a report-only handoff to the owning product's
  documented cleanup/GC command. A dry-run result is evidence for the report, never authorization for
  this engine to remove it. A registry match follows `skills/clean/reference/managed-state-report.md`.
- The skill-scoped belt governs deletion shapes, not every command. On Bash it reaches `rm`,
  `rmdir`, `unlink`, `shred`, `truncate`, `mv` and `find` (bare or by absolute path) and any command
  naming a bundled script. It permits only canonical bundled scan/preview calls made from literal
  shell words and a read-only allowlist, returns `ask` for the two exact mutating shapes, `apply` and
  `handoff-apply`, and denies the rest of what reaches it. Brace, tilde, parameter, command,
  arithmetic, process, word-splitting, filename, redirection, and operator syntax is rejected before
  argument parsing. See [Session belt](#session-belt).
- Deletion walks the validated snapshot bottom-up. New entries are not traversed; they make the
  directory non-empty and therefore skipped. The one exception is Linux `handoff-apply`, which
  empties a verified checkout's `.git` contents, entries the snapshot never inventoried, under the
  mount, consumer-glob, readability, device, and link checks in the
  [safety model](skills/clean/reference/safety-model.md#standalone-git-checkout-evidence). After
  captured children are removed, a directory is
  reopened with `O_NOFOLLOW`, checked empty through its descriptor, and matched by device, inode, and
  type immediately before descriptor-relative `rmdir`. The report leads with tidiness outcomes
  (paths removed, empty directories cleared, and the locked, changed, protected, needs-elevation,
  and unverified skips) and records logical / reclaimable bytes plus observed free-space delta as
  secondary figures.

The execution lane is Linux-only. It reads the current mount namespace from `/proc/self/mountinfo`,
re-discovers protections and Git state, opens every parent through `O_NOFOLLOW` directory descriptors,
checks the descriptor identities against the snapshot, and calls descriptor-relative `unlink`/`rmdir`.
Windows and macOS retain the complete audit/report lane but return `execution-platform-unsupported`
at preview. Backups remain the recovery boundary for user data.

## Requirements and platform support

- Node.js on `PATH`. Every guard and detector registration runs `node hooks/exec-bash.mjs`, and Claude Code's
  native binary neither ships nor uses Node ([Setup](https://code.claude.com/docs/en/setup)), so
  without `node` no hook launches and no guard is enforced. A `SessionStart` row in shell form
  (`"shell": "bash"`, no `args`) runs `command -v node` and needs no node itself. When node is
  absent it exits 0 with JSON: `systemMessage` shows the user a warning and `additionalContext`
  tells the model that the destructive-delete guard cannot launch and enforces nothing. It prints
  nothing when node is present. Basis: https://code.claude.com/docs/en/hooks, "SessionStart"
  (plain stdout reaches Claude only, and exit-2 stderr reaches the user only) and "JSON output"
  (`systemMessage` is a warning shown to the user).
- Bash that `hooks/exec-bash.mjs` can find. The file's header comment lists the candidates in
  order for each platform: on Windows, `CLAUDE_CODE_GIT_BASH_PATH`, the Git for Windows install
  roots, then `PATH`; elsewhere, `PATH` first. The WSL relay (`System32\bash.exe`) is never used.
- Python 3.11+ available on `PATH` is required for scanning, validation, the skill-scoped guard, and
  cleanup. The floor's single origin is the `MIN_PYTHON` constant in
  `skills/clean/scripts/hygiene.py`; `/disk-hygiene:setup check` derives the enforced value from
  there, so treat the number printed here as a convenience copy. Guarded engine calls must use the
  same absolute interpreter reported by the skill-scoped guard, so Bash aliases and functions cannot
  replace it. The plugin never downloads a runtime.
- Git is optional for ordinary trees. If a target contains or sits inside a Git worktree, Git becomes
  required so tracked content can be proven safe; otherwise cleanup for that subtree is blocked.
- `gh` with authenticated access to the configured `github.com` remote is additionally required only
  when the operator invokes standalone-checkout VCS evidence mode. Other hosting providers remain
  protected; no generic network or `git ls-remote` fallback is treated as provider proof.
- Windows has the full **audit** lane (Python 3.11's `lstat` reparse metadata plus Win32 APIs
  exposed by the OS; never invokes UAC) but engine **execution is unsupported**: `preview` reports
  `execution-platform-unsupported` as a per-candidate blocker, and removal is a manual, per-path
  Recycle-Bin handoff offered only after an execution request and explicit approval. The
  request is `--execute` or the user's own in-session request after the audit report, and it
  gates every deletion lane, manual included. The Recycle-Bin / Trash naming is a model-layer
  distinction only, the engine treats Windows and macOS identically (execution unsupported); which
  reversible-removal container the manual lane prefers is the model's instruction, not engine
  behavior.
- Linux requires readable `/proc/self/mountinfo`, descriptor-relative filesystem APIs, and `lsof` for
  the optional execution lane. Absence, diagnostics, or authority gaps block cleanup.
- macOS supports audit/report only because this implementation has no authoritative bind-mount and
  descriptor-anchoring proof for its execution lane.

Check this machine's prerequisites read-only with `/disk-hygiene:check`; Claude can run that on its own,
for example when a hook notice says Python is missing. `/disk-hygiene:setup check` runs the same check,
and `/disk-hygiene:setup apply` resolves anything it reports with guidance.

## How the guard is registered

**All three** hook registrations, both wired hooks and the skill-scoped belt, use **exec form**
with `"command": "node"`. `args` is `hooks/exec-bash.mjs`, then
`hooks/run-python-hook.sh` and that script's arguments. `node` is a real executable. The
launcher finds bash (Git Bash or `PATH` on Windows, `PATH` first elsewhere) and never
`System32\bash.exe`. Bare `bash` or `python3` as `command`
is the launch that fails open on Windows: the WSL relay and the WindowsApps alias stub, and a
failed hook launch is non-blocking, so the guard would silently enforce nothing. The launcher
resolves Python itself instead (#1504, #3686).

The guard registers on two surfaces: a plugin-level **engine gate** (`hooks/hooks.json`) that acts
only on commands referencing the engine, deferring everything else instantly, and enforces the kill
switch and data-root authority; and the skill-scoped **belt** inside the `clean` skill's context,
which governs deletion shapes in the Bash and PowerShell lanes for the rest of the session
(see [Session belt](#session-belt)). Both surfaces resolve the kill switch by reading `disk_hygiene_enabled` from
user-scope `pluginConfigs` in `settings.json` (located from `${CLAUDE_PLUGIN_ROOT}`, honored only
from user/managed/`--settings` scope since Claude Code 2.1.207, so a repo cannot forge it), register
unconditionally, and fail closed to enabled.

Hook lifetime: the hooks page says Claude Code registers a skill's frontmatter hooks when the skill is
invoked and keeps running them for the rest of the session, on turns after the skill's own turn as
well. The belt therefore keeps denying after a clean run ends. Start a new session to clear it. The
plugin-level engine gate fires inside subagents. The skill-frontmatter belt does not: the subagents
page lists settings, managed-policy and plugin hooks as the ones that apply inside subagents, and a
Bash call from a subagent ran unguarded on Claude Code 2.1.285. A fanned-out worker's Bash lane is
not belt-guarded, so "evidence only" is an instruction to the worker, not an enforced denial.
`skills/clean/SKILL.md` holds the detail.

**A silent engine-gate launch or runtime failure is surfaced.** A `Stop`-event detector
(`skills/clean/scripts/guard_launch_monitor.py`, a separate hook entry in `hooks/hooks.json`,
independent of the engine-gate guard itself) scans the session transcript for
`hook_non_blocking_error` records naming the engine gate's own command string and warns once per
session with the failure count and the most recent failure's exit code, duration, and stderr, so a
guard that never ran or died mid-run does not look identical to a guard that ran and approved. This
covers only the `destructive_guard.py` command string in the current session's transcript: it does
not cover repo-hygiene's own guard (a separate plugin, verified working independently), and it never
retroactively scans a prior session's transcript. Every hook registration routes through
`hooks/run-python-hook.sh`, a bash launcher that resolves Python independently of bare `python3` on
PATH, so when `python3` is the WindowsApps alias stub or otherwise unresolvable, the detector still
emits a `systemMessage` even though the guard cannot run (#1504). The detector runs through the same
`node` and bash launch as the guard, so when `node` is missing or no bash resolves it cannot report
either; the failure table below states what happens then.

**The guard's interpreter and data root arrive with the command.** A `UserPromptExpansion` hook
(`skills/clean/scripts/engine_context.py`) runs when `/disk-hygiene:clean` expands and hands the
skill the guard's absolute Python and authorized `--data-root`, resolved by the guard's own code, so
a run does not open with a deliberately denied call to learn them (#4215). It grants nothing; the
guard still judges every call.

**Windows `python3` gotcha, and what the guard does when no Python resolves.** Every hook resolves
Python through `hooks/run-python-hook.sh` (rejecting the zero-length `WindowsApps\python3.exe` App
Execution Alias stub and falling through to `python`, then `py -3`) before exec'ing the guard, the
skill-scoped belt included. A PreToolUse hook blocks a tool call only with exit code 2 or a `deny`
decision, and one that exits 0 with nothing to say reads as approval
([Hooks](https://code.claude.com/docs/en/hooks)), so a guard that could not run would read as one
that ran and allowed. The launcher therefore answers for the guard when the ladder is exhausted, on
the call itself, the same way the guard's watchdog answers "could not decide":

| Surface | When the guard cannot run |
|---|---|
| No Python resolves: `/disk-hygiene:clean` expanding | The expansion is blocked with the reason, so the skill and its belt never load |
| No Python resolves: skill-scoped belt, any Bash or PowerShell call | Denied (exit 2), reason on stderr |
| No Python resolves: plugin-level gate, command naming `hygiene.py` (or an empty payload) | Denied (exit 2), reason on stderr |
| No Python resolves: plugin-level gate, any other command its `if` rows let through | **Proceeds unchecked**, with a `systemMessage` and `additionalContext` notice once per session |
| `node` missing or no bash found: every hook | **Proceeds unchecked.** The hook fails to launch, which is non-blocking: the user sees a hook error notice, the guard is not enforced, and the model is not told. With no bash, the notice's first line is the launcher's `exec-bash: <script> did not run, so this hook enforces nothing`. With no `node`, the launcher never starts, so it cannot detect or report the failure there; the shell-form `SessionStart` row warns the user and the model at each session start, and the guard stays unenforced. The Stop detector launches the same way and reports neither |

Of the no-Python rows, the plugin-level gate row is the only fail-open. Those are the commands the guard would
have deferred on had it run; the watchdog asks on them because a missed deadline is transient, but a
missing interpreter is not, and an `ask` on every `PowerShell(*& $*)` call of every session would
stop work (and deny outright under `-p`) on a host whose only fault is having no Python. The
residual is an engine reached without its file name appearing in the payload, the identity class the
guard itself documents. For the no-Python rows the Stop detector stays as the end-of-turn backstop
and repeats a summary of the same report. The last row has no backstop inside the plugin;
`/disk-hygiene:setup check` probes `node` and bash before a run.

`/disk-hygiene:setup check` resolves the launcher's whole ladder and FAILs only when it is exhausted
or the interpreter it selects is below the floor. A stubbed `python3` alongside a working `python`
or `py -3` is a **WARN**, not a FAIL: every guard launches there, and the residual is only that a
bare `python3` typed by hand still opens the Store. To clear it: disable the `python3` App execution
alias (Settings > Apps > Advanced app settings > App execution aliases) or install real Python ahead
of WindowsApps on `PATH`. A bare `command -v python3` / `where python3` success is not proof the
interpreter is real, the stub answers to the name too.

## Session belt

**Threat model.** After `/disk-hygiene:clean` is invoked, the belt guards against ad hoc deletion and
move commands Claude issues in the main session's Bash and PowerShell lanes. It is not a sandbox.

**What is governed.** Both lanes govern deletion shapes.

- Bash: `rm`, `rmdir`, `unlink`, `shred`, `truncate`, `mv` and `find`, bare or by absolute path, plus
  any command naming `hygiene.py`, `kill_switch_probe.py` or `release_belt.py`. Other commands (`git`,
  `gh`, the repo-hygiene scripts) are not denied. What reaches the belt is denied unless it is an
  exact bundled engine call, the argument-free kill-switch probe, a read-only supporting command, or
  the release lever.
- PowerShell: known deletion spellings get `ask`; engine invocations are denied.

**Accepted cost.** The Bash lane is a deny-list, so a wrapped deletion passes it: a script, an
interpreter call, `bash -c`, `env`, `timeout`, `eval`, `git rm` or `git clean`. That is the cost of
leaving `git`, `gh` and the repo-hygiene scripts unblocked. The engine's own containment stays the
authority for engine work.

**Release lever.** When the belt blocks a command the user wants run, ask the user. The Bash denial
prints one command, `release_belt.py --data-root <root> --session-id <id>`. Claude Code asks for
approval every time, and the guard logs each released command with its text. A release is per
session, writes a marker under `<data root>/belt-release/`, and does not touch the engine gate: engine
calls keep their rules. Without the lever, start a new session to clear the belt.

**Subagents.** The belt does not reach subagents, deliberately: a subagent's Bash call ran unguarded
in 2 of 2 probes on Claude Code 2.1.285. The plugin-level engine gate does fire there. Widening the
plugin gate to subagents is a separate decision. Detail:
[the safety model](skills/clean/reference/safety-model.md#session-belt).

## Reading guard decisions after the fact

Every verdict the guard reaches is appended to a local record under the plugin's own persistent
data directory, with no configuration:

```text
<CLAUDE_PLUGIN_DATA>/guard-decisions/decisions.jsonl
```

One JSON object per line, so `tail`, `grep`, and any JSON-aware reader all work with no
purpose-built tool:

```json
{"schema_version":"1.0","timestamp":"2026-09-07T18:22:41.907Z","hook":"destructive-guard","decision":"ask","rule":"exact-engine-apply","tool":"Bash","mode":"engine-gate","command":"python3 <engine> apply --execute ...","reason":"disk-hygiene is ready to apply one exact, previewed tier..."}
```

`decision` is one of `allow`, `ask`, `deny`, `none` (the guard ran and issued no
`permissionDecision`), `released`, or `not-run`. `rule` names the branch that fired, so a denial
because execution is switched off (`kill-switch-disabled-apply`) is distinguishable from a denial
because the command was not an exact engine invocation (`not-exact-engine-command`). A `released`
record, rule `belt-released`, is a deletion-shaped command the [release lever](#session-belt) let
through to the normal permission system; it keeps the command text. The `not-run` records come from
the `Stop` detector, which is the only process that can observe a guard that never launched.

- **Bounded.** The live file rotates to `decisions.previous.jsonl` at 1 MiB, so the record holds at
  most about 2 MiB and never needs pruning. `command` and `reason` are secret-scrubbed, then clipped
  to 400 characters.
- **Command text is omitted on the catch-all arms.** A PowerShell call recorded as `none` (belt mode,
  no flagged spelling) and a Bash deny-by-default (`not-exact-engine-command`) persist
  `command_chars` (length only) instead of the command text. Those branches fire on arbitrary
  session commands.
- **Owner-only.** The directory is created `0700` and the live file `0600`. Mode is reapplied on
  every write so a leftover world-readable file is tightened.
- **Never a factor in a verdict.** An unwritable data root, a full disk, or any other write failure
  records nothing and changes no decision: the verdict is computed and emitted before the record is
  attempted, and the write path raises nothing.
- **Not a replacement for telemetry.** A configured `HOOK_TELEMETRY_SINK` keeps receiving exactly
  what it received before. The local record is the floor beneath it, for the ordinary case where no
  sink exists.
- **What is not recorded.** The plugin-level defer, the branch this hook takes for every Bash
  command that does not name the engine, writes nothing, which is what keeps the always-on path
  free. The watchdog's expiry path also writes nothing: that callback runs while the main thread is
  presumed wedged inside a filesystem call, and it stays syscall-free for exactly that reason.
- **Turning it off.** Set `DISK_HYGIENE_GUARD_DECISION_LOG` to `0`, `off`, `false`, or `no`. Any
  other value, including an absent one, records.

## Usage

```text
/disk-hygiene:clean <target-directory>
/disk-hygiene:clean --policy <policy.json> <target-directory>
/disk-hygiene:audit [--max-depth <N>] [--sizes-only] [--policy <policy.json>] <target-directory>
```

`/disk-hygiene:audit` is the model-invocable, read-only counterpart for delegated or orchestrated
scans. It runs the engine's `scan` subcommand only, reports the snapshot with coverage gaps, and
removes nothing. Any removal is a separate `/disk-hygiene:clean` run that a person invokes.

`--root-children` with `--root-child <name>` inventories only the named immediate children of the
target. That is required for an OS-managed volume root (the root itself is never walked) and is
also how a depth-1 home audit re-inventories the directories the operator approved, without
walking the rest of the home. Every volume root, OS-managed or a Windows Dev Drive, gets the
strict child ladder described under Volume-root coverage; only a target that is not a volume root
gets the relaxed directory listing.

`--sizes-only` writes per-child byte totals and no entries. It goes through the same large-scan
confirmation as an unbounded walk, sums through VCS and protected directories read-only, and has no
entry cap.

`--deep`, and a home-directory target without it, runs the read-only deep inventory before any
scan: every entry with its producer, a disposition and a reason, where each `KEEP` names who
produced the entry and what still uses it. It reports only and prepares no deletion; removing
anything it lists still goes through scan, preview and the removal approval. Columns and
categories: `skills/clean/reference/scan-flags.md`.

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
  "additional_protected_path_globs": [
    "client-deliverables/**",
    "/srv/shared/keep/**",
    {"glob": "legal/**", "reason": "counsel hold"}
  ]
}
```

Version 2 adds preselect `rules`, an age threshold, and an elevation opt-in
([schema](skills/clean/reference/policy-overlay.schema.json)). A version 1 file keeps working.

```json
{
  "version": 2,
  "rules": [
    {"match": {"hint_ids": ["common-lock-file"]}, "preselect": true, "min_age_days": 7}
  ],
  "elevation": "never"
}
```

A rule ticks matching candidates in the approval list; it never approves. The approval question still
names one tier and its path list, and a tick never raises a candidate above its hint's
`confidence_ceiling` or past a blocker. A rule matches by `hint_id`, `hint_ids`, or `class`
(`superseded-version`, `backup`, `empty`, `temp`, `crash-dump`). Only the baseline temp hints carry
a class; the other classes match only hints an operator adds through `additional_hints` with that
`class`. With `min_age_days`, an entry touched inside the window (or a directory whose newest descendant is, or
whose coverage is incomplete) stays unticked; `min_age_basis` picks the timestamp: `mtime` by
default, `atime`, or `ctime`. The entry is labeled in-flight. Paths that open issues, PRs, or handoffs
reference can be passed to the scan as `--in-flight-refs`; they stay unticked the same way. `elevation: uac-prompt` (Windows only, user-global file or `--policy` only, never a
project file) lets the skill offer an operator-approved elevated re-check for approved-tier paths
that are contested only for `needs-elevation`; the default `never` keeps every elevation off. The
elevation lane has not been proven in a Windows UAC pilot; see the
[safety model](skills/clean/reference/safety-model.md#opt-in-elevation).

Without `--policy`, standing policy files layer over the baseline when present:
`~/.claude/disk-hygiene.json` (user-global) first, then the consumer project's
`.claude/disk-hygiene.json`. An explicit `--policy` file is the invocation-specific choice and
replaces both standing layers. The scan output records which sources applied.

Candidate hints can be disabled or extended. Consumer protection globs are additive. A relative glob matches a path relative to the scan target. A glob that starts with `/`, a drive letter, or `\\` (a UNC path such as `\\server\share\keep\**`) matches the absolute path, so a standing overlay can protect a tree no matter which parent is scanned. An object `{glob, reason}` is accepted. For every entry that matches a path, the scan entry, the preview candidate, the handoff-verify verdict, and a skipped apply path list it under `protection_matches`, sorted and deduplicated, as `{glob}` or `{glob, reason}`. That field sits beside the `consumer-protected-path` reason and is absent when no entry matched. Hard safety
predicates and the baseline protected-name/root rules are non-overridable by any layer: a policy
file can only add protections, add hints, or disable discovery hints (which can only cause junk to
be missed, never removed).

When the scan covers the user home directory, `stdlib_shadowing` lists each home-root `*.py` file
whose stem is a Python standard-library module name, such as `~/gettext.py`. That file shadows the
module for Python started from the home directory with `-c`, `-m`, or the REPL, and it keeps the
home-root `__pycache__` rebuilding. The file's entry carries a `stdlib-module-shadow` advisory, and
the `__pycache__` entry gains `bytecode_sources` naming the modules its `.pyc` files were compiled
from. So a report can say to rename the source, not only to delete the cache. The advisory is not a
hint: it assigns no tier and changes no eligibility. The stdlib name set is the engine
interpreter's `sys.stdlib_module_names`.

When the audited zone overlaps the user temp directory, the scan also reports an `os_autoclean`
advisory naming the OS mechanism that should own it (Windows Storage Sense, systemd-tmpfiles) and,
when that mechanism is off or set to fire only on low disk space, recommends enabling it rather than
hand-cleaning the zone.

On Windows the advisory also sums the user temp directory's regular-file sizes in a read-only walk
that follows no links and stops after 100,000 entries. The result is reported as `temp_zone`, and
the size is a floor when `complete` is false. The recommendation then depends on size against
`os_temp_recommendation_threshold_bytes` in `skills/clean/reference/baseline-policy.json` (1 GiB by
default):

| Temp directory size | Storage Sense | `recommendation` |
|---|---|---|
| At or above the threshold | On, temporary-files cleanup on | Run Storage Sense now (Settings > System > Storage > Storage Sense) |
| At or above the threshold | On, temporary-files cleanup off | Turn on temporary-files cleanup and run it now |
| At or above the threshold | Off or not detected | Enable it on a schedule; a manual run is available either way |
| Below the threshold | Any | `null` |

The text quotes the detected on/off state, schedule, and temporary-files scope. The advisory never
runs Storage Sense, and it changes nothing about what the engine may delete in that directory.

## Volume-root coverage

`--root-children` on a volume root, OS-managed or not (a Windows Dev Drive), never walks the root
itself. Immediate children are admitted or withheld one `scandir` deep. Regular files at the root
use the same admission ladder as directories.

| Never covered | Why |
|---|---|
| The volume root itself | Whole-root recursive walk is refused |
| OS-owned directory names (`Windows`, `/usr`, `Users`/`home`, …) | Per-platform directory set |
| OS-owned file names (`pagefile.sys`, `/swapfile`, `/swap.img`, `vmlinuz*`, `.file`, …) | Per-platform file set |
| Hidden, System, `$`-prefixed, or dot-prefixed names | Fail closed on concealment |
| Symlinks, reparse points, cloud placeholders | Ambiguous identity |
| Virtual-disk image files (`*.vhd`, `*.vhdx`, `*.avhd`, `*.avhdx`, `*.vmdk`, `*.vdi`, `*.qcow2`, `*.img`) | A whole guest disk; the name proves nothing about it being disposable |
| Nested mounts and baseline-protected shell-folder names | Existing hard stops |
| Fifos, sockets, devices, and other non-regular types | `not-regular-file-or-directory` |

User residue that clears that ladder can be selected with `--root-child NAME` and inventoried as
a file. A Windows root file such as `C:\vc_redist.x64.exe` clears it; `/opt` and other OS-owned names
do not. On a target that is not a volume root, such as a home directory, files stay withheld as
`not-a-directory`, only directories are selectable, and hidden and OS-named directories stay
selectable.

## Relationship to other tools

- Use `/repo-hygiene:clean` for deterministic caches, build outputs, Git metadata, or a fresh-pull reset
  inside one repository. `disk-hygiene` does not duplicate those mechanisms.
- Use `/source-control:worktree status`/`cleanup` (if installed) for git worktree checkouts such as a
  `.worktrees/` tree, run those actions from the checkout's own main repository, as they manage the
  current repository's worktrees and take no target. `disk-hygiene` protects tracked content and `.git`
  metadata but does not manage worktree lifecycle. For a redundant standalone checkout, the optional
  VCS evidence mode can return `clear` only after the proof gates in the
  [safety model](skills/clean/reference/safety-model.md) pass, or an `accept_unpublished`
  acknowledgement waives the first two for that one approved path. On Linux, `handoff-apply` then
  deletes that one path in the same call; on Windows and macOS the deletion is the manual handoff.
- Use a product's own prune/GC/uninstall command for state it owns. This skill reports the handoff and
  records the native result but never makes managed state eligible for engine execution.
- `git clean` remains the authority for ignored/untracked repository files. This plugin protects every
  tracked path and does not emulate Git's path rules.

## Security posture

What this plugin can reach, what it refuses, and what it costs you to have it installed. The
measurements below carry the conditions they were taken under.

- **Code execution:** the plugin runs bundled, standard-library Python. The skill-scoped PreToolUse
  guard denies every unknown Bash command, permits only canonical bundled scan/preview calls, and
  returns a hook-issued `ask` for the canonical engine `apply` and `handoff-apply` calls (same
  `permissionDecision: "ask"` as the PowerShell deletion lane; `dontAsk` auto-denies instead of
  prompting). The guard rejects shell expansion and operator syntax instead of validating only the
  post-split argument vector; script identity follows the host path rules and remains
  case-sensitive on POSIX. No `eval`, dynamic shell construction, or downloads are used. Paths cross
  the process boundary as JSON or individually quoted CLI arguments.
- **MCP / external trust:** no MCP server, agent, dependency, or third-party service is shipped.
- **Configuration:** one non-sensitive `userConfig` boolean (`disk_hygiene_enabled`, default
  `true`) gating the execution tiers. Setting it `false` puts `/disk-hygiene:clean` in audit-only
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
- **Trust-surface record:** the plugin-level `hooks/hooks.json` PreToolUse
  registration is a NEW trust surface (a hook that launches in every consumer session), added
  deliberately for guard-enforced audit-only mode and data-root authority (#1106 decision, Option E,
  split registration). Its blast radius is bounded by design: fixed launch arguments authored in the
  plugin's own `hooks.json` (the launch-form record below states what that bounds), bundled
  standard-library scripts only, instant no-output deferral for any command
  not referencing the engine, and no new capability beyond what the skill-scoped deployment already
  did during active cleanup. Known costs, accepted, with the always-on share measured per the
  [hook-budget convention](../../docs/conventions/hook-budget/README.md)'s method (`EPOCHREALTIME`
  wall-clock around direct hook invocation with a benign representative payload; Windows 11 +
  Git Bash dev host, 2026-08-16): the engine-gate hook costs **≈ 190–300 ms per Bash/PowerShell
  tool call** across batches (92 single runs). ≈ 19–30% of the convention's ≤ 1 s typical
  per-tool-call ceiling. While the `clean` skill is loaded, its frontmatter registration is a
  second matching hook that the harness launches in parallel; the pair measured concurrently
  (`&` + `wait`, 60 pairs) walls at **≈ 320–410 ms**, ≈ 1.3–1.5× the same-batch single-hook wall
  rather than double it. **Superseded in 0.21.0 for the launcher portion:** the `sed` read of the
  engine (≈ 24 ms, ≈ 13% of the hook's cost, and ≈ 38 ms in the two-full-pass form before 0.20.13)
  no longer exists, and neither does the separate Python process that was spawned only to evaluate
  the version predicate. The floor is now recovered inside the candidate interpreter on the cold
  path, and the resolved interpreter is cached, so a **warm invocation spends one process spawn
  (the guard itself) where it previously spent four**: `dirname`, `sed`, and two `python3`.
  That spawn census, not a duration, is the durable figure: it is deterministic, whereas the
  wall-clock share above was measured on a host whose process-creation cost was later observed
  varying more than tenfold within a single hour under contention (`bash -c true` at 283 ms and
  1825 ms in the same session at ~10% CPU). Interleaved before/after on such a host, 24 alternating
  pairs, measured p50 5446 → 1418 ms and p95 16991 → 7874 ms; those absolute values are specific to
  that contention and are not comparable to the ≈ 190–300 ms figures above, which were taken on a
  quiet host. Re-measure per the convention's method on a quiet host before citing a new share.
  **Superseded in 0.23.1 for every shell call that does not name the engine and does not
  invoke it through a variable.** The gate is registered once per tool. Bash carries
  `Bash(*hygiene.py*)`. PowerShell carries `PowerShell(*hygiene.py*)` plus
  `PowerShell(*python*$*)` and `PowerShell(*& $*)`, because the PowerShell matcher evaluates
  collected command nodes and a literal path in `$script = '.../hygiene.py'` is not part of the
  later `python $script` (or `& $script`) command. An `if` filter is scoped to the tool it
  names, and one `Bash(...)` filter under a `Bash|PowerShell` matcher left every PowerShell
  call unguarded. The harness evaluates the filter through the tool's own permission matcher
  before it spawns anything, so a Bash or PowerShell call that does not name the engine and
  does not invoke an interpreter or call-operator through a variable now costs this plugin
  zero processes and zero `execve` calls. Before, on a warm interpreter cache, every
  PowerShell call paid four `execve` calls (`bash -c`, the launcher through its `env`
  shebang, bash, the interpreter), no fork, and a 106 KB module import, to be told it was
  irrelevant; measured with `strace -f` on Linux, where the hook process walled at p50 44 ms
  against a `bash -c :` floor of 2 ms (n = 20 per tool), about 22 spawn-equivalents, the cost
  class the issue measured as a 2.4 s median on Windows. A call that names the engine, or
  invokes python/`&` through a variable, pays that chain unchanged and is judged unchanged.
  What the filters still cannot see: for Bash, a command containing `$()`, a backtick or
  `$VAR` spawns the guard anyway, because the filter cannot see what the substitution expands
  to; for PowerShell, the matcher parses the command and runs the hook when any statement,
  pipeline element or nested command matches, so a mixed line such as
  `Get-Date; python hygiene.py` still reaches the guard (the every-subcommand rule applies to
  allow decisions, not to `if`). Neither filter sees an engine reached without its own file
  name in a command node and without an interpreter or call-operator variable, any spelling
  such as a symlink or hard link under another name or a Win32 8.3 short name; the gate's
  relevance check could catch that case by file identity, and the residual is accepted on
  both lanes, as it has been on the Bash lane since 0.21.4, because the engine's own preview
  and approval-token containment still answers for it.
  **0.23.0 delta (local decision record):** the guard now appends one line to
  `<CLAUDE_PLUGIN_DATA>/guard-decisions/decisions.jsonl` on every branch that reaches a verdict.
  The added trust surface is that one append, to a path under the plugin's own data root and
  nowhere else, no read of anything new and no process. The always-on defer branch, which is what a
  Bash command that does not name the engine takes, writes nothing and is byte-for-byte the path it
  was. Measured with `strace -f -e trace=clone,clone3,fork,vfork,execve,openat,write` on a Linux
  container against `origin/main` at `6db96637d`, five invocations per arm: the **process and exec
  census is unchanged on both paths**, one `execve` (the guard) and one `clone3` (the watchdog
  thread, `CLONE_THREAD`, not a process), before and after. The record itself costs one `openat`
  plus one `write` plus one `chmod` (the live file, `0600`) on a warm data root, and one extra
  failed `openat` plus one `mkdir` plus one `chmod` (the directory, `0700`) on the first write of
  an install. Wall-clock over 40 invocations per arm, alternated twice, moved inside
  run-to-run noise on that host (52–58 ms both before and after, the sign of the difference
  changing between repetitions), which is why the syscall census rather than a duration is the
  figure cited here.
  On a machine where no Python 3 interpreter resolves at all, the gate denies every command naming
  the engine and lets the rest through with a once-per-session notice, and the `Stop` detector
  repeats that as a `systemMessage` (#1110, #1504, #3861; the table under the Windows `python3`
  gotcha states each surface). **0.9.0 delta:** the gate no longer carries a `${user_config.*}`
  argument (which, unset, dropped the whole hook and left the gate inert on a default install); it now
  registers unconditionally and resolves the kill switch by **reading** the user `settings.json` and the
  platform managed-settings.json. The added trust surface is that settings-file *read*, bounded to a
  single `pluginConfigs` value, from the user file (located from `${CLAUDE_PLUGIN_ROOT}`) and the
  root-owned managed file at its fixed system path, no write. Both are the plugin's own documented CC
  config, sanctioned by the acceptance review's operator-home carve-out (criterion 4). This entry is the
  plugin-acceptance review delta for the change. **Launch form:** every registration, the wired
  hooks and the skill-scoped belt alike, is exec form: `"command": "node"` and an `args` list naming
  `hooks/exec-bash.mjs`, then `hooks/run-python-hook.sh`, then the Python script and its arguments.
  No shell parses a registration. Claude Code spawns `node` with `args` as the argument vector
  ([Hooks](https://code.claude.com/docs/en/hooks), "Exec form and shell form"), the launcher spawns
  bash with the script path and arguments as argv, and `run-python-hook.sh` execs Python with `"$@"`.
  What bounds the surface is that every argument is a **fixed literal** in the plugin's own
  `hooks.json` or `SKILL.md` frontmatter with no model-, repo-, or session-supplied text in it. The
  only substituted values are Claude Code's own `${CLAUDE_PLUGIN_ROOT}` and, in `hooks.json` only,
  `${CLAUDE_PLUGIN_DATA}`, each inside one argument, so a space, backslash, `$` or backtick in a
  substituted path reaches the script unchanged. A skill-frontmatter hook receives only
  `${CLAUDE_PLUGIN_ROOT}` (#1014), never `${CLAUDE_PLUGIN_DATA}` or `${user_config.*}`, so the belt's
  `--authorized-data-root` channel stays out of its arguments by construction. The shape is
  **maintained by test**: `hooks/run-python-hook.test.sh` asserts that every `hooks.json` row is
  `node` with `exec-bash.mjs` first and `run-python-hook.sh` in `args`, and runs the registered
  engine-gate rows and the belt's frontmatter `args` verbatim; `test_hygiene.py`'s hook helpers stay
  form-agnostic so a form change cannot make an assertion vacuously green. The belt denies every
  call when nothing on the Python ladder resolves. A direct `hygiene.py` invocation outside that skill does
  not read the toggle and answers only to the engine's own preview/approval-token gate. The toggle
  can only narrow the destructive surface, never widen it (see [the safety model](skills/clean/reference/safety-model.md)
  for the degraded-mode detail). The engine never reads or stores credentials; standalone-checkout
  evidence delegates one exact commit lookup per local head to the already-authenticated `gh` CLI.
  Policy comes from an explicit invocation
  argument or standing `disk-hygiene.json` files under `~/.claude/` and the consumer project's
  `.claude/`. All policy input is pattern-only and additive: it can add protections and discovery
  hints or disable hints, and cannot weaken hard guards or authorize removal, so ambient config
  cannot widen the destructive surface.
- **Isolation:** bundled assets resolve from `${CLAUDE_PLUGIN_ROOT}`; generated state belongs under
  `${CLAUDE_PLUGIN_DATA}`. The audited target is read, then mutated only through the gated lane.
- **Egress:** none in the ordinary audit/preview/apply paths. Opt-in standalone-checkout evidence
  invokes `gh api` against `github.com` only, using owner/repository coordinates parsed from the
  checkout's configured remote and an exact locally observed SHA. Unsupported hosts fail closed.
  `git` and `lsof` remain local read-only subprocesses.
- **Provenance:** Melodic Software, MIT. No vendored code.

Security review result: **accept** for the declared local code-execution surface. Any later network,
credential, dependency, or MCP surface reopens this review.

## Sources

Verified 2026-07-16 against current primary documentation:

- [Create plugins](https://code.claude.com/docs/en/plugins) and
  [plugins reference](https://code.claude.com/docs/en/plugins-reference). Plugin structure, cache
  isolation, manifests, versions, and local `--plugin-dir` testing.
- [Skills](https://code.claude.com/docs/en/skills). Side-effecting skills should be manual-only;
  supporting files, arguments, and skill-scoped hooks.
- [Hooks](https://code.claude.com/docs/en/hooks). Current `PreToolUse` decision output.
- [Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces). Relative plugin sources.
- [GNU Bash shell expansions](https://www.gnu.org/software/bash/manual/html_node/Shell-Expansions.html)
. Expansion order and the brace, tilde, parameter, command, arithmetic, process, splitting, and
  filename-expansion families rejected by the literal-command guard.
- [Python 3.11 filesystem APIs](https://docs.python.org/3.11/library/os.html) and
  [path APIs](https://docs.python.org/3.11/library/os.path.html). Non-following metadata, junction, and
  mount detection.
- [Windows reparse-point operations](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-operations)
  and [`GetLogicalDrives`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getlogicaldrives):
  the reparse attribute and available-volume enumeration.
- [Linux `mountinfo`](https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html). Current mount
  namespace and bind-mount targets, which `os.path.ismount` cannot reliably identify.
- [Git `ls-files`](https://git-scm.com/docs/git-ls-files). The index/tracked-file authority.
- [Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew):
  sharing conflicts and directory handles via `FILE_FLAG_BACKUP_SEMANTICS`.
- [`lsof` maintained documentation](https://lsof.readthedocs.io/en/stable/). Open-file lookup; the
  recursive `+D` authority limitation is why diagnostics fail closed.
- [POSIX `unlink`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/unlink.html) and
  [Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html). Open-file unlink semantics
  motivate an explicit preflight rather than relying on deletion failure.

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `disk_hygiene_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` | Allow the clean skill's execution tiers; false = audit-only mode |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure disk-hygiene@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install disk-hygiene@<marketplace> -s <scope> --config disk_hygiene_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "disk-hygiene@<marketplace>": {
         "options": {
           "disk_hygiene_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT). See the repository root `LICENSE`.
