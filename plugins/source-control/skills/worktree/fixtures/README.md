# Worktree fixtures — recorded probes of harness behavior

Every measured claim this plugin makes about how Claude Code treats worktrees is recorded here with
the script that produced it, so a recheck is one command rather than a re-derivation. Stamps follow
[the upstream-drift convention](../../../../../docs/conventions/upstream-drift/README.md): claim,
basis, as-of date, recheck trigger.

A record whose script cannot be re-run is not a fixture — it is a memory. If you change a probe,
re-run it and update the outcome in the same commit.

## `worktree-create-hook-probe.sh` — the `WorktreeCreate` hook contract

**Claim.** A `WorktreeCreate` command hook has no "not applicable" channel: both failure shapes fail
creation. It must create the directory it names. Its stderr reaches the user on a non-zero exit —
all of it — and is dropped on exit 0.

**Basis.** Four arms of `claude -p "…" --worktree <name> [--settings <file>]` in throwaway git
repositories, plus <https://code.claude.com/docs/en/hooks> read as raw markdown (`hooks.md`) per the
convention's [rung 1 fetch route](../../../../../docs/conventions/upstream-drift/README.md#the-rungs).

**As-of.** 2026-08-11, Claude Code **2.1.228**, Windows (Git Bash).

**Recheck trigger.** A Claude Code release note naming `WorktreeCreate`, worktree isolation, or hook
stderr surfacing; or the hooks page's "WorktreeCreate output" section changing what a hook must
return.

### Recorded outcome

| Arm | Hook | Result |
|---|---|---|
| 1 | *(none — control)* | Worktree created at `<repo>/.claude/worktrees/probe0`, on branch `worktree-probe0`, and **locked** with reason `claude session probe0 (pid 29884)` |
| 2 | `exit 0`, no stdout | **Creation FAILS**, CLI exit 1, nothing created |
| 3 | `exit 3`, two stderr lines | Creation fails; **both** stderr lines surfaced, prefixed with the hook command |
| 4 | prints a path it did not create | Creation fails — the harness requires the directory to exist |

Verbatim harness output, arm 2:

```text
Error creating worktree: WorktreeCreate hook failed: hook succeeded but returned no worktree path
(command: echo the path to stdout; http/callback: return hookSpecificOutput.worktreePath)
```

Arm 3 — note that the *second* line is present, so a failing hook is not limited to one surfaced
line:

```text
Error creating worktree: WorktreeCreate hook failed: bash "…/fail-hook.sh": FIRST-STDERR-LINE
SECOND-STDERR-LINE
```

Arm 4:

```text
Error: worktree directory …/extroot/probe4 does not exist or is not a directory. The path came from
a WorktreeCreate hook — the hook must print the directory it created as the last line of its stdout.
```

Arm 2's hook also wrote `PROBE-STDERR-MARKER` to stderr. That string is **absent** from the harness
output, while arm 3's two lines are present — which is how the exit-0-stderr-is-dropped half is
established empirically rather than inferred.

### Corroborating doc quotes

All from `https://code.claude.com/docs/en/hooks.md`, fetched 2026-08-11:

- "Command hook prints path on stdout; HTTP hook returns `hookSpecificOutput.worktreePath`. **Hook
  failure or missing path fails creation**"
- "If the hook fails or produces no path, worktree creation fails with an error."
- "**Command hooks** (`type: "command"`): print the path as the **last non-empty line** of stdout.
  Claude Code strips ANSI escape codes before reading that line… Redirect any other hook output to
  stderr."
- "Any non-zero exit code causes worktree creation to fail."
- "A `WorktreeCreate` command hook can't return JSON, because Claude Code reads its stdout as the
  worktree path."

An earlier audit recorded that no "missing path" sentence was reachable on this page. At the current
revision it is reachable, quoted above, and it agrees with the measurement — recorded here so the
absence claim is not carried forward.

### What this settles in the plugin

- `hooks/worktree-create-gate.sh`'s disabled path exits **non-zero**. The exit-0 shape it used to
  take produced the identical outcome (creation fails) while suppressing every explanation.
- `worktree_create_gate_enabled=false` cannot hand placement back to Claude Code. The harness-side
  stand-downs are `worktree.bgIsolation: "none"` and disabling the plugin.
- Every refusal message leads with a remedy, because a failing hook's stderr is what the user reads.
