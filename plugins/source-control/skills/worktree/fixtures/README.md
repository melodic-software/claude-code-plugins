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

## `nesting-invariant-probe.sh` — the nesting invariant's disputed arm

**Status: RUN 2026-08-15 on Claude Code 2.1.232 — INCONCLUSIVE (fixture failure).**
All four arms executed the fixture setup. The `InstructionsLoaded` hook produced
**zero trace events on every arm**. `claude -p` stderr was `Not logged in · Please
run /login`. Per this section's own trap rule, that is a fixture failure — **not**
evidence of absence and **not** a null finding about the leak. The dispute remains
unadjudicable until an authenticated re-run produces a real trace (or a documented
null from a firing hook).

**Claim under test.** From a session inside a worktree nested in a checkout, a read matching a
path-scoped rule's glob also loads the enclosing checkout's copy of that rule.

**Why it is not settled.** Measured once on 2.1.224 and not reproduced on 2.1.227 — and **neither
run recorded its fixture**, so the two results cannot be compared. That is the whole problem: the
outcome depends on discriminators neither run disclosed, and a null result from a fixture that
differs anywhere is not a refutation. The 2026-08-15 run pinned the discriminators below but could
not fire the instrument without CLI authentication.

### Pinned discriminators (2026-08-15 run)

| Discriminator | Value pinned by this run |
|---|---|
| How the worktree was **created** | plain `git worktree add` (not `claude --worktree` / `EnterWorktree`) |
| How the session was **launched** | `cd <worktree> && claude -p … --settings <file>` (bare cd into a git-worktree-add directory) |
| The exact `paths:` glob **and its anchoring root** | `src/**`, anchored at each rule file's own repo root |
| Whether the parent's rule file was **committed** | yes — committed in the parent checkout |
| Hook registration | `InstructionsLoaded` exec (`args`-array) form via `claude -p --settings` |
| Claude Code version | **2.1.232** |
| Host | Linux (cloud agent); CLI present but unauthenticated |

### Recorded outcome (2026-08-15)

| Arm | Placement | Result |
|---|---|---|
| dot-nested | `<parent>/.claude/worktrees/wt` | **fixture failure** — no `InstructionsLoaded` trace events (CLI not logged in) |
| plain-nested | `<parent>/plainsub/wt` | **fixture failure** — same |
| external (control) | `<workdir>/external-root/wt` | **fixture failure** — same |
| unrelated-nested | `<unrelated>/nested/wt` | **fixture failure** — same |

No arm may be read as settling the leak claim. Re-run under an authenticated CLI; a real null
(hook fired, parent rule absent from the trace) *is* a finding — zero events is not.

**Why the original dispute was unadjudicable.** The outcome depends on discriminators neither run
disclosed:

| Discriminator | Why it changes the answer |
|---|---|
| How the worktree was **created** (`claude --worktree` / `EnterWorktree` / plain `git worktree add`) | The harness's worktree-aware behavior attaches to a session it *recognizes* as a worktree session. `worktrees.md` (fetched 2026-08-11) frames it as "whether you started it with `--worktree`, Claude entered one with `EnterWorktree`, or you resumed a worktree session" — a bare `cd` into a `git worktree add` directory is not obviously any of those. |
| How the session was **launched** into it | Same reason. |
| The exact `paths:` glob **and its anchoring root** | A glob anchored at the worktree root and one anchored at the parent are different tests. |
| Whether the parent's rule file was **committed** | An untracked rule file in a worktree's parent is a different fixture from a tracked one. |
| **Placement**: dot-prefixed `.claude/worktrees/` vs a plain subdirectory vs an **unrelated** repository | These are three separate claims, and one arm's null refutes none of the others. |

**Arms.** dot-nested, plain-nested, external (control — must show zero), and unrelated-nested. The
unrelated-nested arm is the one claimed *worse* (all three surfaces, not just scoped rules) and is
**untested by anyone**; the dispute above does not reach it, so a result there settles nothing about
arm A and vice versa.

**Instrument.** An `InstructionsLoaded` hook, which names the files loaded rather than inferring
them from token deltas. Registered in **exec (`args`-array) form** per
<https://code.claude.com/docs/en/hooks> (raw markdown, fetched 2026-08-11): "Set `args` whenever the
hook references a path placeholder, since each element is passed as one argument with no quoting."
Delivered with `claude -p --settings <file>`, because a project-scope hook in an unapproved
`settings.json` does not run headlessly.

**A trap the script guards.** Zero trace events means *the hook did not fire* — a fixture failure,
not evidence of absence. The script says so rather than printing a null. Mistaking one for the other
is the most likely way this dispute arose in the first place. The 2026-08-15 run hit exactly this
trap (unauthenticated CLI); the record above refuses to convert it into a null.

**Doc status of the claim.** `worktrees.md` (fetched 2026-08-11) documents the default
`.claude/worktrees/<name>/` placement, the isolation checks, the non-suppressible `EnterWorktree`
approval outside `.claude/worktrees/`, and what a worktree shares with the main checkout — and says
**nothing** about whether a nested worktree's session discovers the parent checkout's
`.claude/rules/`. The claim is doc-*unaddressed*, not doc-contradicted, which is exactly why
measurement is the only adjudicator and why an undisclosed fixture was fatal.

**When you re-run it:** record the outcome here — *including a null, which is a finding* — and
refresh the as-of stamp in `SKILL.md` with the verdict, per the upstream-drift convention's
"when a trigger fires" procedure. Do not treat a zero-event fixture failure as a null.

## `project-scope-reap-probe.sh` — what `plugin uninstall -s project` acts on

**Claim.** `claude plugin uninstall <id> -s project` has no path flag and resolves strictly against
the **resolved absolute current directory**. From any other directory it exits 1 and touches
nothing. From the recorded directory — whether that is the live original or an empty one recreated
at the same path — it exits 0 and removes the record from `installed_plugins.json`. Enumeration is
the other half: `claude plugin list --json` reports **every** project-scope record on the machine
regardless of cwd, so a reap can enumerate through the documented CLI and never needs to read
`installed_plugins.json` at all.

**Basis.** Six arms of `claude plugin install|list|uninstall` against throwaway directories under
the platform temp, with the record store read (never written) between arms. No network beyond
installing from an already-configured marketplace; no `claude -p` turns.

**As-of.** 2026-08-22, Claude Code **2.1.240**, re-run unchanged on **2.1.241**, Windows (Git Bash).
The CLI self-updated between the first and last run of this probe; both versions produced the same
outcome on every arm, which is recorded here rather than collapsed into one version.

**Recheck trigger.** A Claude Code release note naming plugin scopes, `plugin uninstall`,
`installed_plugins.json`, or project-scope resolution; or a `--project`/`--path` flag appearing on
`plugin uninstall --help`, which would retire the cwd constraint this design is built on.

### Recorded outcome

| Arm | Question | Result |
|---|---|---|
| 1 | does `install -s project` write a record, keyed by what? | Yes — one record per plugin, `scope: "project"`, `projectPath` set to the **resolved native absolute cwd**, backslash-separated. A plain non-git directory is enough; it also writes `<cwd>/.claude/settings.json`. Count 108 → 111 |
| 2 | is `plugin list --json` enumeration cwd-independent? | Yes — run from two unrelated directories, the project-scope record set was identical (111 records, same `cksum`) |
| 3 | does `uninstall -s project` reach another path's record? | **No** — exit 1, count unchanged at 111 |
| 4 | from the recorded directory? | Exit 0, record removed (111 → 109 over two ids) |
| 5 | after the directory is deleted? | The record **survives** the directory. Recreating an **empty** directory at the same path and running the uninstall from inside it exits 0 and removes it (109 → 108). The recreated directory is left holding `<path>/.claude/settings.json` |
| 6 | where no record exists here? | Exit 1, no-op |

Verbatim failure text, arms 3 and 6 — the same message for "belongs to another path" and "no record
here":

```text
✘ Failed to uninstall plugin "caveman@caveman": Plugin "caveman@caveman" is installed in user
scope, not project. Use --scope user to uninstall.
```

**A trap this fixture exists to stop.** That message names a remedy — `--scope user` — that would
uninstall the plugin **fleet-wide**, for every project and the user scope both. A non-zero exit from
a reap call is a no-op to report, never an escalation, and the suggestion in this line is never to
be followed.

**A trap that already cost one measurement.** An early run read as a **null** — "the install wrote
no record" — purely because the reader compared the 8.3 short form inherited from `%TEMP%`
of the user directory (`ALICE~1`) against the long form the CLI writes (`AliceExample`). The record
was there the whole time. Any consumer comparing these paths must resolve first (`pwd -W` on Git
Bash yields the native long form), unify separators, and fold case on Windows. Two related shapes
bite the same way: `jq` on Git Bash terminates lines with CRLF, and `@tsv` escapes each backslash to
`\\` — both leave a `projectPath` that silently matches nothing.

### What this settles in the plugin

- `scripts/reap-project-plugin-records.sh` requires `--worktree-path` to name the directory it is
  already standing in, and refuses otherwise. That is arm 3 rendered in code: the CLI cannot reach
  another path's record, so a helper that could only ever be a no-op or a mistake there declines to
  run at all.
- The reap runs **before** `git worktree remove`, from inside the worktree — arm 4, the shortest
  route, needing no directory to be recreated.
- Arm 5 is what makes pre-existing orphans reachable at all, and it is also the arm most capable of
  harm, because it works on any path a user can recreate. `audit` therefore **reports** such records
  and never removes them on its own; see [../context/audit.md](../context/audit.md).
- Nothing anywhere edits `installed_plugins.json`. Arm 2 is why that is affordable: enumeration and
  removal both have documented CLI surfaces.
