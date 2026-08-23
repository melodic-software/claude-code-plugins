---
description: "Audit an arbitrary directory tree for orphaned, temporary, stale-lock, failed-write, partial-download, and empty leftover artifacts; classify evidence into confidence tiers; and optionally remove exact validated paths after explicit per-tier approval. Read-only by default and manual-only. Use when: 'audit this directory', 'find orphaned files', 'what junk can I clean up', 'reclaim disk space', 'find temp or lock leftovers', 'clean up my home directory'. Skip when: repository cache/build cleanup belongs to repo-hygiene, a product has its own prune/GC command, or the target is an OS-managed root."
argument-hint: "[--execute] [--policy <policy.json>] [--max-depth <N>] [--confirmed-large-scan] [--root-children [--root-child <name>]...] <target-directory>"
user-invocable: true
disable-model-invocation: true
hooks:
  PreToolUse:
    - matcher: "Bash|PowerShell"
      hooks:
        # Shell form, matching hooks/hooks.json (#2568). Exec form resolves
        # `command` on PATH with no shell, and the bare `python3` this used to
        # name is the zero-length WindowsApps App Execution Alias stub on stock
        # Windows — the hook cannot launch, and a failed launch is non-blocking,
        # so the belt silently enforces nothing. `hooks/run-python-hook.sh`
        # rejects that stub and falls through to `python`, then `py -3`.
        # `${CLAUDE_PLUGIN_ROOT}` is the ONLY substitution a skill-frontmatter
        # hook receives (#1014) — never ${CLAUDE_PLUGIN_DATA} or
        # ${user_config.*}, either of which makes Claude Code refuse the launch.
        # The single-quoted YAML scalar is the same value hooks.json spells with
        # \" escapes; every path placeholder must stay double-quoted, because the
        # shell re-tokenizes the string and plugin roots contain spaces.
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}"/hooks/run-python-hook.sh "${CLAUDE_PLUGIN_ROOT}"/skills/clean/scripts/destructive_guard.py --plugin-root "${CLAUDE_PLUGIN_ROOT}"'
          shell: bash
          timeout: 60
metadata:
  workflow-stage: anytime
  summary: Audit a directory tree for stale leftovers and remove validated paths
---

# Disk hygiene

Audit first; mutate only after a fresh deterministic preview and explicit approval of one tier. A
filename pattern is a discovery hint, never proof that an entry is junk. **Safe tidiness is the
primary objective; reclaimed bytes are secondary.** Read
[the safety model](reference/safety-model.md) before the optional execution lane.

## Arguments and boundaries

Parse `$ARGUMENTS` as the complete user-facing surface: optional `--execute`, optional
`--policy <file>`, optional `--max-depth <N>`, optional `--confirmed-large-scan`, optional
`--root-children` with zero or more `--root-child <name>`, and one target directory. Remaining
engine flags (`--output`, `--project-dir`, `--data-root` on scan; `--snapshot`, `--plan`,
`--report`, `--confirm-tier`, `--approval-token`, `--paths`, and `--vcs-evidence` on the other
subcommands) are supplied by this skill's command templates, not typed by the user.
`--execute` means "deletion may be offered" on every platform — the gated engine lane where the
platform supports it, the manual handoff elsewhere; it is not approval. (Deliberate semantic
unification, not a restatement: the flag previously read as engine-lane-only, which left the
manual lane's gate ambiguous — consumer sessions read it both ways.) `--max-depth <N>` bounds a
scan to depth N (preferred for large targets); `--confirmed-large-scan` opts into an unbounded
full walk after the human clears the [confirmation gate](#confirmation-gate)'s scan-scope row.
`--root-children` is the only way to address an OS-managed volume root (for example `C:\` or `/`):
it never walks that root recursively. Without `--root-child` names the engine returns
`root-children-selection-required` listing admitted immediate directories (OS-owned, hidden,
system, reparse, mount, protected-shell-folder, and non-directory entries are withheld). With one
or more explicit `--root-child <name>` flags — after the human clears the confirmation gate's
root-children row — it audits only those admitted children into one snapshot. A general "clean
everything" is not selection. With no target, ask once. Reject an
OS-managed root (unless `--root-children`), a non-root mount target, a protected shell-folder root
or descendant, a missing directory, a symlink, or a Windows reparse point. A whole-volume root that
is not OS-managed (a Windows Dev Drive) is no longer rejected outright — it is a valid target, but
as a known-large root it is gated like a home target (see step 1): the scan returns
`large-target-confirmation-required` unless bounded with `--max-depth` or confirmed with
`--confirmed-large-scan`. `--root-children` is invalid on a non-OS volume root or a non-volume
target; scan those without the flag.

- Invoke `/repo-hygiene:clean` via the Skill tool for one repository's caches, build output, Git metadata, or tree reset.
- For git worktree checkouts (e.g. under a `.worktrees/` directory), hand off by invoking
  `/source-control:worktree status`/`cleanup` via the Skill tool (if installed), run from the checkout's own main
  repository — those actions manage the current repository's worktrees and take no target path. The
  engine already protects tracked content and `.git` metadata, but owns no worktree lifecycle.
  A standalone checkout is likewise protected by default; the narrow evidence mode in §6 is the
  only exception, and it never applies to linked worktrees whose common Git directory is outside the
  approved checkout.
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
  value could not be read. The guard enforces the same toggle independently and denies both mutation
  lanes in audit-only mode (`reference/safety-model.md`), so run the probe anyway — to state the
  configured value accurately and stop before proposing work the guard would deny. The guard is the
  backstop, not the sole enforcer. It reports its absolute Python interpreter and the authorized
  `--data-root` value in denial guidance; use that exact interpreter path as `<hook-python>` for
  every engine call; bare `python`/`python3` is rejected because Bash aliases and functions can
  replace them. If either value is not known yet, submit the otherwise exact scan shape once with
  bare `python`: the guard must deny it and report both, after which retry the scan with the
  absolute interpreter and the reported `--data-root`. If the reported interpreter is older than
  the engine's declared floor (the `MIN_PYTHON` constant in `hygiene.py`, the floor's single
  origin), stop with the declared prerequisite instead of improvising a different scanner or
  deletion path.
- Automated, scheduled, remote, unattended, or no-human-in-loop sessions always audit and stop.

## Confirmation gate

Every question this skill asks passes this gate — the no-target prompt above, the large-scan
confirmation in §1, the root-children selection for an OS-managed volume root, the removal approval
in §5, and the unsupported-platform handoff in §6. One surface rule and one floor cover all five.
What a valid answer must *name* is per question, because a target prompt has no tier or path list to
name and cannot be held to a bar built for one.

**Question surface.** Prefer `AskUserQuestion`: its answer is the user's own and cannot be
fabricated. It is not always usable, in two distinct ways — a bare-name `permissions.deny` rule or a
`disallowed-tools` entry removes it from context entirely, while permission mode `dontAsk` denies it
even when an allow rule names it, leaving it visible and every call failing. Fall back to the same
question asked inline as a numbered choice whenever the tool is absent, denied, **or otherwise
unusable** — including a denial discovered only by calling it; a denied call is an unanswered
question, never an answer. Then wait for the reply.

**The floor — every question.** Take the user's own answer, given in this interactive session. Never
supply, infer, or fabricate it: a prior general request, `--execute`, "clean everything", approval of
another tier, or silence is not an answer. On rejection, stop.

**What the answer must name — per question.** Where a row requires the answer to name something the
skill itself produced — the resolved target, the tier, the path list — show it in the question; a bar
naming what the question never presented cannot be met.

| Question | Accept only an answer naming |
|---|---|
| Target selection (no target given) | one directory, which must then clear every rejection in "Arguments and boundaries" |
| Scan scope (`--confirmed-large-scan`, §1) | that target and a deliberate unbounded full walk of it |
| Root-children selection (`--root-children`, §1) | one or more admitted immediate child directory names just listed — never "everything" or the volume root itself |
| Removal approval (§5) and manual handoff (§6) | exactly the one tier and the exact path list just shown |

## 1. Create a read-only snapshot

Create a unique run directory under `${CLAUDE_PLUGIN_DATA}/runs/`; snapshots, plans, and reports must
stay there, never in the target or `${CLAUDE_PLUGIN_ROOT}`. Run:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<target>" --output "<run-dir>/snapshot.json" [--policy "<policy.json>"] \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}" \
  [--max-depth <N>] [--confirmed-large-scan] \
  [--root-children [--root-child <name>]...]
```

The guard validates `--data-root` against the plugin data directory it derives itself, and denies
the call outright when it cannot recognize the install layout — so a run reporting that denial is a
coverage gap, not a clean result. (Derivation and its fail-closed rationale: `reference/safety-model.md`.)

For a large root (a home directory, anything whose recursive walk could exceed the engine's entry cap),
start with a bounded pass: add `--max-depth 1` to inventory the target's loose files and immediate children,
then fan out deeper scans per subtree that the evidence justifies. The engine backs this with a
deterministic gate: a scan whose target resolves to the user home directory or a non-OS volume root (a
Windows Dev Drive — an OS-managed root still cannot be walked as a whole, and reaches the engine only via
`--root-children`) and carries neither `--max-depth` nor `--confirmed-large-scan` returns
`large-target-confirmation-required` (after a cheap top-level probe, not a full walk) instead of the
unbounded traversal, so a forgotten bound never becomes an accidental whole-volume scan. `--max-depth` is
the preferred bounded response. When the target is an OS-managed volume root, first run with
`--root-children` alone, present the `admitted_children` list through the [confirmation
gate](#confirmation-gate)'s root-children row, then re-run with the same flag plus each chosen `--root-child
<name>` — one run directory, one snapshot, one report covers every selected subtree. Never invent the
selection. Reserve `--confirmed-large-scan` for a deliberate full walk the human has confirmed — pass the
[confirmation gate](#confirmation-gate)'s scan-scope row first, the same standing before an expensive step
that the apply lane demands before a destructive one; a general "clean my home directory" is not that
confirmation. Every directory whose descendants were not walked — cut off by `--max-depth`, a protected
root, or a VCS boundary — is recorded in `truncated_paths`; report them as coverage gaps, never as clean,
and never plan them for removal (the preview blocks them as `truncated-not-inventoried` and skips the live
re-verification checks a candidate with no live-I/O value left to give would otherwise still pay for). Each
fan-out worker receives a bounded subtree and returns evidence only. The parent owns classification, the
single report, every approval, preview, and all execution. Do not let workers delete or prepare approvals.

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
root-level entry whose `protected_reasons` is empty and that does not belong to a recognizable
app/config convention as suspicious too — the snapshot already carries it (every walked entry is
recorded with a possibly-empty `hints` list), so nothing further needs discovering, only judging.
Read the entry's own `protected_reasons`, never one policy field: protection also comes from name
patterns and from live filesystem state, and an entry that names a single field as its filter will
step straight past a cloud-sync root whose name embeds a tenant.
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

Safe tidiness leads; reclaimed space follows. Confidence is report priority, not permission — and
byte size is never a ranking key:

| Tier | Minimum evidence | Default outcome |
|---|---|---|
| High | Explicit disposable provenance plus a second independent signal; owner inactive; work-product question resolved | Offer exact-path approval |
| Medium | Likely disposable, but one ownership/provenance fact is indirect | Review, then optionally offer its own approval |
| Low | Name/age-only, conflicting signals, resumable or user-content possibility | Keep unless the human separately reviews and approves exact paths |

Report every finding with these fields, in this order — size last:

1. **Provenance** — where it came from, resolved from evidence (a manifest, a config's own
   contents, an owning repository's source, a documented naming contract), never guessed from the
   name alone.
2. **What it is** — intent / role of the entry (`reason` in engine plans).
3. **Why removable** — why it is not work product, plus owner / native-GC result.
4. **Risk** — what could go wrong if it is removed (and why that risk is acceptable at this tier).
5. Path, tier, evidence, disposition.
6. Logical / reclaimable bytes as a **secondary** signal only.

Separately list protected, locked, needs-elevation, unverified, and coverage-gap entries.

**Empty directories are first-class findings.** They are not inherently junk, but zero-byte residue must
stay visible and rankable: never drop an empty directory from investigation or from the report because it
reclaims nothing. Prefer ranking by tier, location sensitivity (for example volume-root or home-root
orphans), and provenance strength over byte totals. The snapshot already distinguishes them for you: a
walked directory whose `logical_size` is `0` with an empty `size_qualifiers` is a genuinely empty directory,
while a `logical_size` of `null` carrying the `not-walked` qualifier is an uninventoried coverage gap. Never
fold the first into a byte-centric roll-up that drops it, and never read it as the second.

**Lead the frontier with `children_rollup`.** The snapshot carries one row per immediate child the run covered, whatever
that child's coverage, and `walked` is the single discriminator: `true` means every aggregate is exact; `false` means
they are all `null` with `unwalked_reasons` naming the cause — never `0`, never a partial subtree sum. Rank on
`reclaimable_local_bytes`, never on `logical_bytes`, a logical total that `size_qualifiers` flags as inflated by cloud
placeholders, hard links, or sparse extents. The block opens no directory the walk did not, so a `--max-depth 1` pass
returns `depth-cut`/`null` for every NON-EMPTY child: the frontier is complete, but a recursive total is bought only by
fanning a deeper scan out over that subtree — report those rows as coverage gaps, never as small or clean.
`scan-complete` also carries `unhinted_entries` — `entries` minus `hinted_entries`, every inventoried entry no hint
judged — so quote hint coverage as a rate: 7 hinted of 40,247 is 0.017 %, nothing like "7 findings". Fields, reasons
and the measurement: [the safety model](reference/safety-model.md).

**Relocation is out of scope.** This skill offers exactly two outcomes per finding — keep it, or approve its
exact path for deletion. There is no relocation lane and no move primitive in the engine, by design: a move
is not a containment-checkable, revalidatable, token-bound operation the way a delete is. So when the right
answer for a misplaced entry is "this belongs somewhere else", say so and report it as **keep**; the
operator performs and verifies the move themselves, outside this workflow. Never imply the report's
keep-or-delete choice is the complete set of dispositions, and never stage a move through the manual
handoff.

An entry's `logical_size` is reclaimable local bytes only when its `size_qualifiers` is empty. Exclude every qualified
entry from any reclaimable-bytes total and state the qualified bytes separately with their reasons — a
`cloud-placeholder` carries its REMOTE size while occupying roughly nothing locally; a `hardlinked` name shares one
object with other names; a `sparse` file's logical size overstates local allocation; and `not-walked` means the subtree
was never inventoried, so `logical_size` is `null` rather than `0` — except on the target's own record, which keeps its
partial walked sum alongside a `not-walked` qualifier, so read that number as a floor. Prefer the snapshot's
`target_reclaimable_local_bytes` (and preview/apply `reclaimable_local_bytes*`) over summing `logical_size` yourself —
folding qualified or unknown sizes into a total claims space that deleting the path would never return. Never treat a
low or zero reclaimable-byte figure as a reason to skip a finding that otherwise clears the evidence bar.

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
      "provenance": "documented atomic-write staging name; owner process absent",
      "reason": "failed atomic-write staging file",
      "evidence": ["documented name shape", "owner process absent"],
      "why_not_work_product": "generated staging bytes with no durable consumer",
      "risk": "low — regenerable staging residue; no live consumer",
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

When status is `ready-for-explicit-approval`, show a table naming every path with provenance, what
it is, why removable, risk, whether it is an empty directory, the single tier, and only then logical
/ reclaimable bytes, plus the preview's approval token — then pass the
[confirmation gate](#confirmation-gate) — the approval must name **exactly that tier and list**.
Process another tier only with a new plan, preview, and question.

## 6. Apply only the confirmed preview

After an affirmative answer in this interactive session, run only:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" apply --execute \
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json" \
  --confirm-tier "<tier>" --approval-token "<token>" --report "<run-dir>/report-<tier>.json" \
  --data-root "${CLAUDE_PLUGIN_DATA}"
```

Never use `rm`, `rmdir`, `Remove-Item`, `del`, `find -delete`, or an ad-hoc Python deletion call. The
skill-frontmatter belt blocks those bypasses and forces one final permission prompt for the exact engine
apply command; confirm it only when it matches the tier and paths just approved. If the plan, snapshot,
path identity, descendant set, VCS state, or handle state changed, re-scan and re-ask; never reuse a
token.

### Unsupported-platform handoff (Windows, macOS)

Preview reports `execution-platform-unsupported` as a per-candidate blocker on these platforms, so
the engine never deletes there. The default outcome is the report. The manual lane is gated by
`--execute` exactly as the engine lane is — without it, no deletion lane may be offered on any
platform. If — and only if — `--execute` was requested and the human reviews the report and approves
an exact path list drawn from one tier in this interactive session (the §3 report spans every tier, so
narrow it to a single tier and show that tier's paths before asking — the
[confirmation gate](#confirmation-gate)'s removal row is the same exact-tier-and-list bar the engine
lane clears; a general "clean it up" is still not approval), removal is a manual handoff, not an
engine plan:

1. Write the approved exact paths to `<run-dir>/handoff-paths.json` as
   `{"version": 1, "paths": ["relative/exact.tmp"]}` (snapshot-relative, exact, non-overlapping,
   never globs). For an ordinary path, run the engine's deterministic revalidation immediately
   before deletion:

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

   A standalone Git checkout can reach `clear` only through an additional, explicit evidence file.
   Never use this for a linked worktree, a tracked subdirectory, or non-Git VCS. After the operator
   has approved that exact checkout in `handoff-paths.json`, write
   `<run-dir>/vcs-evidence.json`:

   ```json
   {
     "version": 1,
     "repositories": [
       {
         "path": "relative/checkout",
         "remote": "origin",
         "stash_copies": ["/absolute/path/to/independent/checkout"]
       }
     ]
   }
   ```

   Include one entry for every live `.git` marker at or below the approved checkout. `path` is
   snapshot-relative; `remote` is the configured GitHub remote whose repository must contain every
   local branch-head SHA (plus detached `HEAD`, when applicable), or `null` only for a genuinely
   unborn repository with no local heads. `stash_copies` contains independent absolute checkout
   roots outside every approved deletion path; use `[]` when there are no stashes. Then run:

   ```text
   "<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" handoff-verify \
     --snapshot "<run-dir>/snapshot.json" --paths "<run-dir>/handoff-paths.json" \
     --vcs-evidence "<run-dir>/vcs-evidence.json" --data-root "${CLAUDE_PLUGIN_DATA}"
   ```

   This mode remains read-only. It re-runs
   `git status --porcelain=v1 --untracked-files=all --ignored=matching` (with submodule dirtiness
   enabled), resolves every local head, confirms each SHA through
   `gh api repos/<owner>/<repo>/commits/<sha>`, enumerates every live stash, and requires each stash
   SHA in at least one declared independent checkout's own stash list whose `--git-common-dir` is
   not the candidate's Git store. Only `github.com` remotes are supported; another provider,
   missing/failed `git` or `gh`, a repository-set mismatch, external common Git metadata,
   dirty/untracked/ignored content, an unconfirmed head, a linked-worktree "stash copy", or a
   non-duplicated stash leaves the categorical VCS protections in place and returns `contested`.

   The exception is deliberately limited to the Git-specific reasons: `vcs-tracked-content`,
   `vcs-metadata`, `.git`'s own `baseline-protected-name`, and the scan's opaque `.git` truncation.
   Every other protected name, mount/link/reparse check, identity/descendant check, handle check, and
   consumer protection remains categorical. The emitted `vcs_evidence.gates` object records all four
   required gates: empty porcelain status; all local heads present on the configured remote; all
   stashes duplicated elsewhere (or none); and the exact approved path supplied by the existing
   operator-confirmation lane.

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

   **Path length is a different failure — not a silent downgrade but a hard stop.** Those three
   caveats all describe a reversible operation quietly turning permanent. A path longer than the
   classic Windows `MAX_PATH` (260 characters) cannot reach the Recycle Bin *at all*: the shell
   APIs behind it reject the path, so the operation fails outright. Deep tool residue — nested
   dependency or build trees — routinely exceeds it. The only remaining way to remove such a path
   is a **permanent** delete through a `\\?\` long-path API, which no bin can undo.

   That fallback is its own irreversible action and does **not** inherit the approval given for a
   reversible removal. Stop, tell the operator this exact path cannot be recycled and why, and
   re-ask through the [confirmation gate](#confirmation-gate) for permanent deletion of that exact
   path, named as irreversible — an approval that said "recycle these" never authorized it. If the
   operator declines, skip and report the path; shortening or moving the tree to get under the
   limit is a relocation, out of scope (§3) and the operator's own action. Record such removals as
   permanent in the §6 summary, distinct from the reversible ones.
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
approved list. Engine invocations from PowerShell stay hard-denied.

**That belt outlives this cleanup.** Claude Code registers a skill's frontmatter hooks when the
skill is invoked and keeps them registered for the **rest of the session** — there is no
harness-level "while the skill is active" window for hooks (#2618). So once `/disk-hygiene:clean`
has run, the deny-by-default Bash lane and the PowerShell deletion prompts keep applying to
unrelated later work in the same session, not only to this cleanup. Say so when a later,
unrelated command is blocked or prompted, rather than treating it as a surprise; the session's own
end is what clears it. See `reference/safety-model.md` for both registration surfaces, the kill
switch, and what the belt does and does not bound.

Summarize tidiness outcomes first: the paths removed (the report's `removed` list), how many of them
were empty directories, the coverage gaps that remain, and every skip grouped by `locked`,
`changed-or-link`, `protected`, `needs-elevation`, `handle-state-unverified`, or `delete-failed`.
Report `reclaimable_local_bytes_removed` and the observed free-space delta **after** those tidiness
figures, never as the headline. Do not claim the observed free-space delta is exact: concurrent disk
activity, sparse files, hard links, compression, and delayed allocation affect it.

## Gotchas

Harness mechanics are not restated here — one copy only, because two is how a stale claim survived
a fix to the reference (#2618). Load [the safety model](reference/safety-model.md) when you need
them: how the guard registers on two surfaces, how the kill switch is delivered and scoped, and
what the PowerShell lane flags → "Kill-switch enforcement"; how the hooks launch, what that bounds,
and the residual fail-open → "Hook launch form".

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
- The Bash lane is deny-by-default: only the literal-word bundled scan, preview, handoff-verify, and
  apply shapes (plus the argument-free kill-switch probe) pass, using the hook runtime's own absolute
  interpreter. Do supporting inspection with non-Bash read-only tools. Shell expansions, globs,
  splitting/escape forms, operators, redirections, aliases, and exported functions fail closed.
- The PowerShell lane is the inverse tradeoff: open for read-only support work, hard-denying engine
  invocations, and turning known deletion spellings into a final human permission prompt. It is a
  raised bar, not a fail-closed lane — its flagged set is enumerated, so an unflagged mutation
  spelling passes it. The engine's own containment and the Bash lane remain the deletion authority.
- The guard rejects `~` anywhere in a Bash command as a shell-expansion character, which includes
  Windows 8.3 short names (`SOMEUS~1`). Always pass long-form paths; the guard's own disclosures
  are already long-form.
