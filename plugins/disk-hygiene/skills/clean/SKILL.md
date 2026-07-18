---
name: clean
description: "Audit an arbitrary directory tree for orphaned, temporary, stale-lock, failed-write, partial-download, and empty leftover artifacts; classify evidence into confidence tiers; and optionally remove exact validated paths after explicit per-tier approval. Read-only by default and manual-only. Use when: 'audit this directory', 'find orphaned files', 'what junk can I clean up', 'reclaim disk space', 'find temp or lock leftovers', 'clean up my home directory'. Skip when: repository cache/build cleanup belongs to repo-hygiene, a product has its own prune/GC command, or the target is an OS-managed root."
argument-hint: "[--execute] [--policy <policy.json>] <target-directory>"
user-invocable: true
disable-model-invocation: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python"
          args: ["${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive_guard.py"]
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
- For state owned by a package manager, plugin manager, browser, IDE, cloud-sync client, or similar
  product, research its documented dry-run/prune/GC command and report the handoff. Managed state is
  never eligible for this engine, even when a native dry-run calls it eligible.
- Never elevate, trigger UAC/sudo, install a dependency, close another process's handle, or disable a
  retention mechanism. Report `needs-elevation` or `handle-state-unverified` and stop that tier.
- If the `disk_hygiene_enabled` userConfig option is `false` (its value here is
  `${user_config.disk_hygiene_enabled}`; a literal unexpanded token means unset = enabled), audit
  only and explain why execution is disabled. The hook
  runs in shell-free exec form and reports its absolute Python interpreter in denial guidance. Use
  that exact path as `<hook-python>` for every engine call; bare `python`/`python3` is rejected because
  Bash aliases and functions can replace them. If the path is not known yet, submit the otherwise
  exact scan shape once with bare `python`: the guard must deny it and report `<hook-python>`, after
  which retry the scan with that absolute path. If the reported interpreter is older than Python
  3.11, stop with the declared prerequisite instead of improvising a different scanner or deletion
  path.
- Automated, scheduled, remote, unattended, or no-human-in-loop sessions always audit and stop.

## 1. Create a read-only snapshot

Create a unique run directory under `${CLAUDE_PLUGIN_DATA}/runs/`; snapshots, plans, and reports must
stay there, never in the target or `${CLAUDE_PLUGIN_ROOT}`. Run:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<target>" --output "<run-dir>/snapshot.json" [--policy "<policy.json>"] \
  --project-dir "${CLAUDE_PROJECT_DIR}"
```

For a large root, first map its immediate children and fan out read-only analysis by subtree. Each
worker receives a bounded subtree and returns evidence only. The parent owns classification, the single
report, every approval, preview, and all execution. Do not let workers delete or prepare approvals.

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
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json"
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
  --confirm-tier "<tier>" --approval-token "<token>" --report "<run-dir>/report-<tier>.json"
```

Never use `rm`, `rmdir`, `Remove-Item`, `del`, `find -delete`, or an ad-hoc Python deletion call. The
skill-scoped hook blocks those bypasses and forces one final permission prompt for the exact engine
apply command; confirm it only when it matches the tier and paths just approved. If the plan, snapshot,
path identity, descendant set, VCS state, or handle state changed, re-scan and re-ask; never reuse a
token.

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
