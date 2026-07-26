---
name: clean
description: "Audit an arbitrary directory tree for orphaned, temporary, stale-lock, failed-write, partial-download, and empty leftover artifacts; classify evidence into confidence tiers; and optionally remove exact validated paths after explicit per-tier approval. Read-only by default and manual-only. Use when: 'audit this directory', 'find orphaned files', 'what junk can I clean up', 'reclaim disk space', 'find temp or lock leftovers', 'clean up my home directory'. Skip when: repository cache/build cleanup belongs to repo-hygiene, a product has its own prune/GC command, or the target is an OS-managed root."
argument-hint: "[--execute] [--policy <policy.json>] <target-directory>"
user-invocable: true
disable-model-invocation: true
hooks:
  PreToolUse:
    - matcher: "Bash|PowerShell"
      hooks:
        - type: command
          command: "python3"
          args: ["${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive_guard.py", "--plugin-root", "${CLAUDE_PLUGIN_ROOT}"]
          timeout: 60
---

# Disk hygiene

Audit first; mutate only after a fresh deterministic preview and explicit approval of one tier. A
filename pattern is a discovery hint, never proof that an entry is junk. Read
[the safety model](reference/safety-model.md) before the optional execution lane.

## Arguments and boundaries

Parse `$ARGUMENTS` as optional `--execute`, optional `--policy <file>`, and one target directory.
`--execute` means "deletion may be offered" on every platform — the gated engine lane where the
platform supports it, the manual handoff elsewhere; it is not approval. (Deliberate semantic
unification, not a restatement: the flag previously read as engine-lane-only, which left the
manual lane's gate ambiguous — consumer sessions read it both ways.) With no target, ask once. Reject an
OS-managed root, a non-root mount target, a protected shell-folder root or descendant, a missing
directory, a symlink, or a Windows reparse point. A whole-volume root that is not OS-managed (a
Windows Dev Drive) is no longer rejected outright — it is a valid target, but as a known-large root
it is gated like a home target (see step 1): the scan returns `large-target-confirmation-required`
unless bounded with `--max-depth` or confirmed with `--confirmed-large-scan`.

- Use `/repo-hygiene:clean` for one repository's caches, build output, Git metadata, or tree reset.
- For git worktree checkouts (e.g. under a `.worktrees/` directory), hand off to
  `/source-control:worktree status`/`cleanup` (if installed), run from the checkout's own main
  repository — those actions manage the current repository's worktrees and take no target path. The
  engine already protects tracked content and `.git` metadata, but owns no worktree lifecycle.
- For state owned by a package manager, plugin manager, browser, IDE, cloud-sync client, or similar
  product, research its documented dry-run/prune/GC command and report the handoff. Managed state is
  never eligible for this engine, even when a native dry-run calls it eligible.
- Never elevate, trigger UAC/sudo, install a dependency, close another process's handle, or disable a
  retention mechanism. Report `needs-elevation` or `handle-state-unverified` and stop that tier.
- If the `disk_hygiene_enabled` userConfig option is `false` (its value here is
  `${user_config.disk_hygiene_enabled}`), audit only and explain why execution is disabled. A
  literal unexpanded token is not evidence the toggle is unset — resolve it deterministically by
  running the bundled probe (the guard allows exactly this argument-free shape):
  `"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/kill_switch_probe.py"` and honor
  the `effective` value it reports; on `degraded: true` proceed as enabled but say the configured
  value could not be read. The guard now enforces this independently: it resolves the same
  `disk_hygiene_enabled` toggle by reading it straight from your user `settings.json` (the read is
  shared with this probe, and the settings file is located from the tamper-resistant
  `${CLAUDE_PLUGIN_ROOT}` — not the environment), so in audit-only mode it denies both mutation lanes
  it gates outright — the Bash engine `apply` and the PowerShell deletion belt alike. Running the probe still
  matters so you can state the configured value accurately and stop before proposing work the guard
  would deny; the guard is the backstop, not the sole enforcer. The hook runs in shell-free exec form and reports its absolute Python
  interpreter and the authorized `--data-root` value in denial guidance. Use that exact interpreter
  path as `<hook-python>` for
  every engine call; bare `python`/`python3` is rejected because Bash aliases and functions can
  replace them. If either value is not known yet, submit the otherwise exact scan shape once with
  bare `python`: the guard must deny it and report both, after which retry the scan with the
  absolute interpreter and the reported `--data-root`. If the reported interpreter is older than
  the engine's declared floor (the `MIN_PYTHON` constant in `hygiene.py`, the floor's single
  origin), stop with the declared prerequisite instead of improvising a different scanner or
  deletion path.
- Automated, scheduled, remote, unattended, or no-human-in-loop sessions always audit and stop.

## 1. Create a read-only snapshot

Create a unique run directory under `${CLAUDE_PLUGIN_DATA}/runs/`; snapshots, plans, and reports must
stay there, never in the target or `${CLAUDE_PLUGIN_ROOT}`. Run:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<target>" --output "<run-dir>/snapshot.json" [--policy "<policy.json>"] \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}" \
  [--max-depth <N>] [--confirmed-large-scan]
```

The guard validates `--data-root` against the plugin data directory it derives from
`${CLAUDE_PLUGIN_ROOT}` (passed to the guard as `--plugin-root`, the only substitution a
skill-frontmatter hook receives), confining generated state to the plugin data directory even when
the guard's own environment lacks `CLAUDE_PLUGIN_DATA`. If the guard cannot recognize the install
layout it derives no authority and denies `--data-root` engine calls rather than trusting a guessed
path, so re-run reporting a denial is a coverage gap, not a clean result.

For a large root (a home directory, anything whose recursive walk could exceed the engine's entry
cap), start with a bounded pass: add `--max-depth 1` to inventory the target's loose files and
immediate children, then fan out deeper scans per subtree that the evidence justifies. The engine
backs this with a deterministic gate: a scan whose target resolves to the user home directory or a
non-OS volume root (a Windows Dev Drive — an OS-managed root is denied outright and never reaches
this gate) and carries neither `--max-depth` nor `--confirmed-large-scan` returns
`large-target-confirmation-required` (after a cheap top-level probe, not a full walk) instead of the
unbounded traversal, so a forgotten bound never becomes an accidental whole-volume scan. `--max-depth`
is the preferred bounded response.
Reserve `--confirmed-large-scan` for a deliberate full walk the human has confirmed — ask with
`AskUserQuestion` first, exactly as the apply lane requires before an expensive step; a general
"clean my home directory" is not that confirmation. Every
directory whose descendants were not walked — cut off by `--max-depth`, a protected root, or a VCS
boundary — is recorded in `truncated_paths`; report them as coverage gaps, never as clean, and
never plan them for removal (the preview blocks them as `truncated-not-inventoried` and skips the
live re-verification checks a candidate with no live-I/O value left to give would otherwise still
pay for). Each fan-out worker receives a bounded subtree and returns evidence only. The parent owns
classification, the single report, every approval, preview, and all execution. Do not let workers
delete or prepare approvals.

The bundled [baseline policy](reference/baseline-policy.json) contains cross-platform candidate hints
and protected names. Without `--policy`, the engine also layers standing policy files when present:
`~/.claude/disk-hygiene.json` (user-global), then `<project>/.claude/disk-hygiene.json` via
`--project-dir`. An explicit `--policy` is the invocation-specific choice and replaces both standing
layers. Every overlay can only disable/add hints and add protected globs; none can weaken hard guards.
The scan output names its `policy_sources`. Treat scan errors and unvisited protected roots as
coverage gaps, not clean results.

The scan output may also carry an `os_autoclean` advisory when the target overlaps a zone an OS
mechanism (Windows Storage Sense, systemd-tmpfiles) should own. Surface its recommendation in the
report; prefer enabling the OS mechanism over hand-cleaning that zone, mirroring the managed-state
rule below.

## 2. Establish evidence and ownership

A hint annotation is not the only trigger for triage: at a user-home target, treat any loose
root-level entry that is not in `protected_exact_names` and does not belong to a recognizable
app/config convention as suspicious too — the snapshot already carries it (every walked entry is
recorded with a possibly-empty `hints` list), so nothing further needs discovering, only judging.
This positional read is how session-state droppings that share no common name (a runner-controller
status snapshot, a one-off data export) surface for ownership triage even without a matching hint.

For each hinted or suspicious entry, inspect enough neighboring content and metadata to answer:

1. What created it? Prefer a manifest, log, documented naming contract, sibling structure, or owning
   tool over an age/name guess.
2. Is the owner active? Check current process/tool state without killing, pausing, or modifying it.
3. Does the owning system provide cleanup or retention? Its dry-run result is authoritative.
4. Could this be real work product, a resumable download, a backup, a dependency pinned by constraints,
   or a shell/cloud-sync folder? If uncertain, keep it.
5. Is the evidence current for this exact path? Re-resolve every sibling independently; never
   interpolate names from one batch member.

## 3. Classify and report

Confidence is report priority, not permission:

| Tier | Minimum evidence | Default outcome |
|---|---|---|
| High | Explicit disposable provenance plus a second independent signal; owner inactive; work-product question resolved | Offer exact-path approval |
| Medium | Likely disposable, but one ownership/provenance fact is indirect | Review, then optionally offer its own approval |
| Low | Name/age-only, conflicting signals, resumable or user-content possibility | Keep unless the human separately reviews and approves exact paths |

Report every finding with path, logical bytes, tier, evidence, owner/native-GC result, why it is not
work product, and disposition. Separately list protected, locked, needs-elevation, unverified, and
coverage-gap entries. Empty directories are not inherently junk.

## 4. Build one exact-tier plan

Only when `--execute` was requested, write `<run-dir>/plan-<tier>.json`; never mix tiers:

```json
{
  "version": 1,
  "tier": "high",
  "candidates": [
    {
      "path": "relative/exact.tmp",
      "tier": "high",
      "reason": "failed atomic-write staging file",
      "evidence": ["documented name shape", "owner process absent"],
      "why_not_work_product": "generated staging bytes with no durable consumer",
      "owner": "unmanaged"
    }
  ]
}
```

For managed state, report the documented native command and its current dry-run result, but do not add
the path to an engine plan. Paths in an engine plan are unmanaged, snapshot-relative, exact,
non-overlapping, and never globs.

## 5. Preview, then ask

Run the deterministic gate:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" preview \
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json" \
  --data-root "${CLAUDE_PLUGIN_DATA}"
```

It rechecks containment, identity and full descendant set, hard protections, Git's index, and live
handles from current state rather than trusting snapshot annotations. It also proves Linux mount and
directory-descriptor prerequisites. Windows and macOS return `execution-platform-unsupported`. Any
blocker means no approval prompt and no deletion. Fix nothing behind the gate; rescan.

When status is `ready-for-explicit-approval`, show a table naming every path, the single tier, logical
bytes, and the preview's approval token. Use `AskUserQuestion` to ask whether to remove **exactly that
tier and list**. A prior general request, `--execute`, “clean everything,” approval of another tier, or
silence is not confirmation. On rejection, stop. Process another tier only with a new plan, preview,
and question.

## 6. Apply only the confirmed preview

After an affirmative answer in this interactive session, run only:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" apply --execute \
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json" \
  --confirm-tier "<tier>" --approval-token "<token>" --report "<run-dir>/report-<tier>.json" \
  --data-root "${CLAUDE_PLUGIN_DATA}"
```

Never use `rm`, `rmdir`, `Remove-Item`, `del`, `find -delete`, or an ad-hoc Python deletion call. The
skill-scoped hook blocks those bypasses and forces one final permission prompt for the exact engine
apply command; confirm it only when it matches the tier and paths just approved. If the plan, snapshot,
path identity, descendant set, VCS state, or handle state changed, re-scan and re-ask; never reuse a
token.

### Unsupported-platform handoff (Windows, macOS)

Preview reports `execution-platform-unsupported` as a per-candidate blocker on these platforms, so
the engine never deletes there. The default outcome is the report. The manual lane is gated by
`--execute` exactly as the engine lane is — without it, no deletion lane may be offered on any
platform. If — and only if — `--execute` was requested and the human reviews the report and
approves an exact path list in this interactive session (the same `AskUserQuestion` exact-tier-and-
list bar as the engine lane; a general "clean it up" is still not approval), removal is a manual
handoff, not an engine plan:

1. Write the approved exact paths to `<run-dir>/handoff-paths.json` as
   `{"version": 1, "paths": ["relative/exact.tmp"]}` (snapshot-relative, exact, non-overlapping,
   never globs), then run the engine's deterministic revalidation immediately before deletion:

   ```text
   "<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" handoff-verify \
     --snapshot "<run-dir>/snapshot.json" --paths "<run-dir>/handoff-paths.json" \
     --data-root "${CLAUDE_PLUGIN_DATA}"
   ```

   It reruns the engine's identity/reparse/protection/descendant/VCS/handle checks per path
   against live state and emits one verdict each — `clear`, `drifted` (identity or descendant
   set changed since the snapshot), `gone` (no longer present), or `contested` (protection,
   VCS state, a live handle, elevation, or unverifiable state) — and never deletes anything.
   Act only on verdict-`clear` paths. Additionally confirm any owner process named in the audit
   evidence is still absent — that evidence is report-level, outside the engine's checks.

   **Verify one path per deletion, not one batch for all.** In a multi-path run, the first
   path's check ages while every later path is still being walked and probed, so its `clear`
   is already stale at emission — and staler after each intervening deletion. Pair each
   deletion with its own fresh single-path handoff-verify run (verify one → delete that one →
   next); reserve the multi-path form for reporting. A clear verdict is valid only at emission
   time: delete immediately, and re-run handoff-verify after any delay or interruption.
2. Prefer reversible removal (Windows Recycle Bin / macOS Trash) over permanent deletion, and say
   which was used. That reversibility is conditional, not guaranteed: bin size caps, a
   policy-disabled bin, or a non-NTFS/network volume can silently make the same operation
   permanent — disclose when a target's volume or policy may turn "reversible" removal permanent.
3. Container-wide deletion commands (`Clear-RecycleBin`, emptying the Trash, or any "delete
   everything in this container" spelling) are forbidden in the manual lane — they execute
   against the live container, so items arriving between approval (or even re-enumeration) and
   execution die under an approval that never saw them. Satisfy "empty the container" by
   enumerating the container and deleting per item under steps 1, 2, and 4; items that arrive
   after enumeration are simply not deleted. This is the engine lane's changed-since-scan threat
   in the manual lane, where no snapshot token protects execution.
4. Skip and report any path whose verdict is not `clear`; never substitute a sibling, retry
   around a lock, or delete under a stale verdict.

The PowerShell guard lane turns deletion spellings into a final human permission prompt (the same
bar as the engine apply prompt); confirm that prompt only when the command matches the exact
approved list. Engine invocations from PowerShell stay hard-denied. The plugin-level engine gate
(`hooks/hooks.json`) now registers unconditionally and resolves the kill switch itself by reading
`disk_hygiene_enabled` from your user `settings.json`; it no longer carries a `${user_config.*}`
argument, so the unset-default hook-drop that once made it inert on a default install is gone.
`Bash|PowerShell` PreToolUse hooks fire for the PowerShell tool. See `reference/safety-model.md`.

Summarize removed paths, logical bytes removed, observed free-space delta, and every skip grouped by
`locked`, `changed-or-link`, `protected`, `needs-elevation`, `handle-state-unverified`, or
`delete-failed`. Do not claim the observed free-space delta is exact: concurrent disk activity,
sparse files, hard links, compression, and delayed allocation affect it.

## Gotchas

- POSIX permits unlinking an open file, so successful deletion is not a live-handle check. Linux
  execution requires an authoritative `lsof` result and fails closed on diagnostics or missing access.
- Python 3.11 has no `os.path.isjunction`; the engine reads the Windows reparse attribute from `lstat`
  and treats every reparse point as protected. Windows execution remains disabled.
- `os.path.ismount` cannot reliably identify same-filesystem bind mounts. Linux execution therefore
  parses `/proc/self/mountinfo` and fails closed if that namespace view is unavailable.
- Apply opens every Linux parent with `O_NOFOLLOW` relative to the already-open target descriptor,
  verifies the descriptor identity, and removes only by descriptor-relative `unlink`/`rmdir`. A
  directory is reopened without following links, matched by device/inode/type, and proven empty after
  its captured children are removed.
- A directory's contents can change after preview. Apply revalidates each captured entry and removes
  bottom-up; it never follows a new link or recursively discovers new entries. The manual-handoff
  lane's container re-enumeration rule applies this same changed-since-scan discipline where no
  snapshot token exists.
- `allowed-tools` would pre-approve rather than restrict tools, so this destructive skill intentionally
  grants none. Consumer permission policy remains authoritative.
- The Bash hook denies unknown commands rather than trying to enumerate deletion spellings. Supporting
  research uses non-Bash read-only tools; only literal-word bundled scan, preview, handoff-verify, and
  apply shapes using the hook runtime's same absolute executable pass. Shell expansions, globs,
  splitting/escape forms, operators, redirections, aliases, and exported functions fail closed.
- The guard registers twice: a plugin-level engine gate (`hooks/hooks.json`, `--mode engine-gate`)
  that receives the data root by plugin-hook substitution and defers instantly on any command not
  referencing the engine; and this skill's frontmatter belt, which adds the deny-by-default Bash and
  deletion-spelling PowerShell discipline while cleanup is the active work. Both resolve the kill switch
  the same single way — reading `disk_hygiene_enabled` from user-scope `pluginConfigs` in
  `settings.json`, located from the `${CLAUDE_PLUGIN_ROOT}` both receive — so both honor a configured
  `false`, register unconditionally, and fail closed to enabled when the value is absent or unreadable.
  Verdicts are idempotent where both fire.
- The guard hook launches in exec form via `python3`, resolved on `PATH` with no shell (`python3`,
  not bare `python`, because stock macOS and many Linux distros ship only `python3` and a legacy
  `python` 2.x would crash the guard on modern syntax). Enforcement is therefore only as strong as
  that resolution: on a host where `python3` does not resolve to an interpreter meeting the
  engine's `MIN_PYTHON` floor the PreToolUse
  launch fails, and Claude Code treats a failed hook launch as a non-blocking error, so the guard
  does not intercept there. Concretely, the exposure is the manual PowerShell deletion lane: engine
  `apply` is unsupported on Windows and macOS and elsewhere runs only behind the guard's own `ask`,
  so no silent auto-delete path opens, but the guard's PowerShell belt that turns a deletion spelling
  into a final human prompt is lost. The backstops that remain are the per-path human approval the
  manual-handoff lane already requires and the consumer's baseline permission policy — defense-in-depth
  lost, not preserved. `/disk-hygiene:setup check` reports whether the interpreter resolves on this
  machine.
- **The kill switch is delivered by reading user settings, not by a hook argument (since 0.9.0).** Earlier
  versions passed a bare `${user_config.disk_hygiene_enabled}` in `hooks/hooks.json`; a declared userConfig
  `default` is not implemented upstream (#46477 / #39455 / #39827), so an unset-but-defaulted token was
  neither substituted nor exported to `CLAUDE_PLUGIN_OPTION_*`, and its presence **dropped the whole hook
  entry** — making the engine gate inert for any consumer who never set the key. The gate no longer carries
  a `${user_config.*}` token; both the gate and the belt resolve `disk_hygiene_enabled` by reading it from
  `pluginConfigs` in `settings.json`. Claude Code honors that key only from user, managed, and `--settings`
  scope since 2.1.207 (a project/local `settings.json` is ignored), so a hostile repo cannot forge it. The
  reader reads the **user** file (located from `${CLAUDE_PLUGIN_ROOT}` rather than repo-redirectable
  environment) and the **managed** enterprise file (highest precedence — a value there wins, so an org can
  enforce audit-only, with its `managed-settings.d/` drop-in dir merged over it); a session `--settings`
  file is the one honored source a hook cannot read. Absent or unreadable settings fail closed to enabled.
- **PreToolUse hooks DO fire for the PowerShell tool** (2.1.218; payload `tool_name` is literally
  `PowerShell`, confirmed by a live block through that tool). A `Bash|PowerShell` matcher is correct and
  there is no harness firing divergence — read `tool_name` from the stdin payload, not from an env var
  (`CLAUDE_TOOL_NAME` does not exist).
- The PowerShell lane is the inverse tradeoff: it stays open for read-only support work (git, gh,
  metadata probes) and instead hard-denies engine invocations and turns known deletion spellings
  into a final human permission prompt. It is a raised bar, not a fail-closed lane — move, rename,
  overwrite, and volume-format spellings are not flagged at all (`reference/safety-model.md`); the
  engine's own containment and the Bash lane remain the deletion authority.
- The guard rejects `~` anywhere in a Bash command as a shell-expansion character, which includes
  Windows 8.3 short names (`SOMEUS~1`). Always pass long-form paths; the guard's own disclosures
  are already long-form.
