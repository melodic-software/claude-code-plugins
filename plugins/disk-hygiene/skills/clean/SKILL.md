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
          args: ["${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive_guard.py", "--authorized-data-root", "${CLAUDE_PLUGIN_DATA}", "--disk-hygiene-enabled", "${user_config.disk_hygiene_enabled}"]
---

# Disk hygiene

Audit first; mutate only after a fresh deterministic preview and explicit approval of one tier. A
filename pattern is a discovery hint, never proof that an entry is junk. Read
[the safety model](reference/safety-model.md) before the optional execution lane.

## Arguments and boundaries

Parse `$ARGUMENTS` as optional `--execute`, optional `--policy <file>`, and one target directory.
`--execute` means “offer the gated lane”; it is not approval. With no target, ask once. Reject a
filesystem root, mount target, OS-managed root, protected shell-folder root or descendant, missing
directory, symlink, or Windows reparse point.

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
  `${user_config.disk_hygiene_enabled}`; a literal unexpanded token means unset = enabled), audit
  only and explain why execution is disabled. In this audit-only mode the guard denies every
  deletion lane, including the flagged PowerShell mutation spellings, not only the Bash engine
  apply. The kill-switch value reaches the guard as a runtime-substituted hook argument
  (`--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}`), so a configured `false` is
  honored even where the runtime does not inject the `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED`
  environment variable; the environment variable is only a fallback. The hook
  runs in shell-free exec form and reports its absolute Python interpreter and the authorized
  `--data-root` value in denial guidance. Use that exact interpreter path as `<hook-python>` for
  every engine call; bare `python`/`python3` is rejected because Bash aliases and functions can
  replace them. If either value is not known yet, submit the otherwise exact scan shape once with
  bare `python`: the guard must deny it and report both, after which retry the scan with the
  absolute interpreter and the reported `--data-root`. If the reported interpreter is older than
  Python 3.11, stop with the declared prerequisite instead of improvising a different scanner or
  deletion path.
- Automated, scheduled, remote, unattended, or no-human-in-loop sessions always audit and stop.

## 1. Create a read-only snapshot

Create a unique run directory under `${CLAUDE_PLUGIN_DATA}/runs/`; snapshots, plans, and reports must
stay there, never in the target or `${CLAUDE_PLUGIN_ROOT}`. Run:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<target>" --output "<run-dir>/snapshot.json" [--policy "<policy.json>"] \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}"
```

The guard validates `--data-root` against the authorized data root it receives as a
runtime-substituted hook argument (`${CLAUDE_PLUGIN_DATA}`), so generated state provably lands in the
plugin data directory even when the shell environment lacks `CLAUDE_PLUGIN_DATA`.

For a large root (a home directory, anything whose recursive walk could exceed the engine's entry
cap), start with a bounded pass: add `--max-depth 1` to inventory the target's loose files and
immediate children, then fan out deeper scans per subtree that the evidence justifies. Every
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

Preview returns `execution-platform-unsupported` on these platforms, so the engine never deletes
there. The default outcome is the report. If — and only if — the human reviews the report and
approves an exact path list in this interactive session (the same `AskUserQuestion` exact-tier-and-
list bar as the engine lane; a general "clean it up" is still not approval), removal is a manual
handoff, not an engine plan:

1. Revalidate each path immediately before removal: size, mtime, and kind unchanged since the
   audit evidence; no reparse point/symlink; any owner process named in the evidence still absent;
   an exclusive-open probe succeeds (no live handle).
2. Prefer reversible removal (Windows Recycle Bin / macOS Trash) over permanent deletion, and say
   which was used.
3. Skip and report any path that fails revalidation; never substitute a sibling or retry around a
   lock.

The PowerShell guard lane turns deletion spellings into a final human permission prompt (the same
bar as the engine apply prompt); confirm that prompt only when the command matches the exact
approved list. Engine invocations from PowerShell stay hard-denied.

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
  bottom-up; it never follows a new link or recursively discovers new entries.
- `allowed-tools` would pre-approve rather than restrict tools, so this destructive skill intentionally
  grants none. Consumer permission policy remains authoritative.
- The Bash hook denies unknown commands rather than trying to enumerate deletion spellings. Supporting
  research uses non-Bash read-only tools; only literal-word bundled scan, preview, and apply shapes
  using the hook runtime's same absolute executable pass. Shell expansions, globs, splitting/escape
  forms, operators, redirections, aliases, and exported functions fail closed.
- The guard hook launches in exec form via `python3`, resolved on `PATH` with no shell (`python3`,
  not bare `python`, because stock macOS and many Linux distros ship only `python3` and a legacy
  `python` 2.x would crash the guard on modern syntax). Enforcement is therefore only as strong as
  that resolution: on a host where `python3` does not resolve to a 3.11+ interpreter the PreToolUse
  launch fails, and Claude Code treats a failed hook launch as a non-blocking error, so the guard
  does not intercept there. Concretely, the exposure is the manual PowerShell deletion lane: engine
  `apply` is unsupported on Windows and macOS and elsewhere runs only behind the guard's own `ask`,
  so no silent auto-delete path opens, but the guard's PowerShell belt that turns a deletion spelling
  into a final human prompt is lost. The backstops that remain are the per-path human approval the
  manual-handoff lane already requires and the consumer's baseline permission policy — defense-in-depth
  lost, not preserved. `/disk-hygiene:setup check` reports whether the interpreter resolves on this
  machine.
- The PowerShell lane is the inverse tradeoff: it stays open for read-only support work (git, gh,
  metadata probes) and instead hard-denies engine invocations and turns known deletion spellings
  into a final human permission prompt. It is a raised bar, not a fail-closed lane; the engine's
  own containment and the Bash lane remain the deletion authority.
- The guard rejects `~` anywhere in a Bash command as a shell-expansion character, which includes
  Windows 8.3 short names (`SOMEUS~1`). Always pass long-form paths; the guard's own disclosures
  are already long-form.
