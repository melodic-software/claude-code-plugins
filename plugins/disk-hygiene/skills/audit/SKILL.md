---
description: "Read-only, audit-only scan of one directory tree for orphaned, temporary, stale-lock, failed-write, partial-download, and empty leftovers, reported as an evidence snapshot. Removes nothing; any removal is a separate /disk-hygiene:clean run that a person invokes. Use when: 'delegate a disk-hygiene audit', 'orchestrator scan of a directory for leftovers', 'subagent scan of this directory for leftovers', 'disk-hygiene audit report'. Skip when: the ask is to clean up or reclaim space (that is /disk-hygiene:clean), one repository's caches or build output (repo-hygiene), or an OS-managed root."
argument-hint: "[--max-depth <N>] [--sizes-only] [--policy <file>] <target-directory>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Scan a directory tree for stale leftovers and report the evidence, read-only
---

**Arguments.** `[--max-depth <N>] [--sizes-only] [--policy <file>] <target-directory>`. Full form: `[--max-depth <N>] [--sizes-only] [--quiet] [--policy <file>] [--root-children [--root-child <name>]...] <target-directory>`

# Disk hygiene audit

Scan one directory tree and report what the snapshot shows. This skill runs the engine's `scan`
subcommand and nothing else, and it changes nothing in the target. A filename pattern is a
discovery hint, never proof that an entry is junk.

This skill carries no hooks of its own. Safety rests on the plugin-level engine-gate in
`hooks/hooks.json`, which checks every Bash or PowerShell call that names `hygiene.py`. Run no
engine subcommand other than `scan`, no shell command that writes, moves, or deletes under the
target, and no compound shell around an engine call. A subagent follows that contract itself, from
the worker brief in step 2.

## 1. Bootstrap

Run the argument-free probe first, before any engine call:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/kill_switch_probe.py"
```

Take `hook_python` and `data_root` from its one-line JSON. Every engine call needs the absolute
`<hook-python>` and `--data-root`; a bare `python3` is rejected. When `hook_python` is not yet
known, submit the probe once with bare `python`. The probe reports `hook_python` as the interpreter
it ran under, so that value is the guard's only if the guard's own interpreter ran it. The scan is
admitted only under the guard's interpreter: if it is denied for that reason, the denial names the
interpreter and ran nothing, so rerun the scan with the interpreter it names.

- `data_root` is `null`: the install layout proved no data root and the guard denies every engine
  call. Report the audit as not run, submit no engine call, and stop.
- The probe call is denied or left waiting for a person: report the audit as not run and stop. Do
  not scan without it.
- `hook_python` is older than `MIN_PYTHON` in
  [`hygiene.py`](../clean/scripts/hygiene.py): stop with that declared prerequisite.
- `effective` is `false` (audit-only): the scan still runs. State the configured value, and leave
  out the removal handoff in step 4. On `degraded: true`, say the configured value could not be read.

## 2. Scan

Pick a unique run directory under `<data_root>/runs/`; the snapshot lives there, never in the
target. With no target, ask the person who invoked you once. Reject an OS-managed root, a missing
directory, a symlink, or a Windows reparse point.

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<target>" --output "<run-dir>/snapshot.json" \
  --data-root "<data_root>" [--project-dir "<project-dir>"] \
  [--policy "<policy.json>"] [--max-depth <N>] [--sizes-only] [--quiet] \
  [--root-children [--root-child <name>]...]
```

`--project-dir` is optional; pass it, as a literal absolute path, when the consumer project has
standing policy files. Never pass `${CLAUDE_PROJECT_DIR}` or any other `${...}` token: the guard
rejects shell expansion. What each flag does, including the large-target and volume-root rules, is in
[scan-flags.md](../clean/reference/scan-flags.md). For a home directory or another large target,
start with `--max-depth 1`, then scan the subtrees the evidence justifies. Never pass
`--confirmed-large-scan` on your own: an unbounded walk needs a person's answer.

For a subtree worker, the brief to paste into the spawn prompt is
[fan-out-worker-brief.md](../clean/reference/fan-out-worker-brief.md). Before spawning, replace every
`${...}` token and `<placeholder>` in it with the literal absolute value you hold from the probe
(`hook_python`, `data_root`) or from step 2: a worker cannot expand `${...}` tokens, and its data
root is the probe's `data_root`, not `${CLAUDE_PLUGIN_DATA}`. A worker returns scan evidence only.

## 3. Read and report the snapshot

Report from the snapshot and the scan's stdout, and nothing the run did not observe.

- Lead with `children_rollup`. `walked: true` rows carry exact totals; `walked: false` rows carry
  `null` aggregates and `unwalked_reasons`, so report them as coverage gaps, never as small or clean.
- Rank on `reclaimable_local_bytes`, not `logical_bytes`. An entry whose `size_qualifiers` is
  non-empty stays out of any reclaimable total; state its bytes and reasons separately.
- Report `truncated_paths` (a count under `--quiet`, the list in the snapshot) and every scan error
  as coverage gaps. A `large-target-confirmation-required` or `root-children-selection-required`
  status names the next step, not a failure.
- Quote hint coverage as a rate: `hinted_entries` of `entries`, never "N findings".
- List protected, locked, needs-elevation, and unverified entries separately, and surface an
  `os_autoclean` recommendation as the engine states it.
- Give each hinted entry the evidence the snapshot holds (path, hint, `protected_reasons`,
  `size_qualifiers`). A hint has no owner check behind it, so label the list hints for a person to
  judge, not verdicts, and rank nothing for deletion. Empty directories stay visible.
- A non-zero exit is a real failure: 2 for an invalid or blocked target, 3 when elevation is needed
  or filesystem state could not be verified. Report it and stop.

## 4. Hand off

Removal is `/disk-hygiene:clean`, which a person invokes. Close the report with the snapshot path
and that one line. Do not start a removal run and do not propose exact paths for one. When
`effective` was `false`, say instead that removal is disabled by the plugin's configuration.

## Next

/disk-hygiene:clean <target-directory>

Run by a person when the findings warrant removal; it takes the same target, not this snapshot.

## Gotchas

- The argument-free probe is not one of the calls the engine-gate adjudicates, so a session in a
  permission mode that asks may hold it for a person. That is the "waiting for a person" stop in
  step 1, not a reason to skip the probe.
- Under an inline `--plugin-dir` load the probe can report `data_root` as `null` even though the
  plugin data directory exists. Stop as step 1 says; do not substitute a guessed path. **Claim:** the
  guard derives `data_root` only from the `<plugins>/cache/<marketplace>/<name>` install layout or a
  registered directory marketplace, so a checkout loaded inline reports `null`. **Basis:** the probe
  run from a checkout with neither reported `hook_python` resolved and `data_root: null` on Claude Code
  2.1.285 (Linux); the derivation rule is in
  [safety-model.md](../clean/reference/safety-model.md), "Local-directory marketplace installs".
  **As of:** 2026-09-30. **Recheck:** the guard's data-root derivation changes, or a Claude Code
  release documents a plugin data path for `--plugin-dir` loads.
- A hint match is discovery evidence only. Reporting "N hinted entries" as "N safe deletions" is the
  failure this skill exists to avoid.
