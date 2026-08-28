# Unsupported-platform handoff (Windows, macOS)

The manual removal lane for Windows and macOS, where the `disk-hygiene:clean` engine never
deletes. Read this only after [`../SKILL.md`](../SKILL.md) section 6 has sent you here: the
engine lane and this lane never co-execute, and nothing below may be improvised from the engine
steps.

## Contents

- [The gated manual lane](#the-gated-manual-lane)
- [The PowerShell guard lane](#the-powershell-guard-lane)
- [Hook registration outlives the cleanup](#hook-registration-outlives-the-cleanup)

## The gated manual lane

Preview reports `execution-platform-unsupported` as a per-candidate blocker on these platforms, so
the engine never deletes there. The default outcome is the report. The manual lane is gated by
`--execute` exactly as the engine lane is, without it, no deletion lane may be offered on any
platform. If, and only if,`--execute` was requested and the human reviews the report and approves
an exact path list drawn from one tier in this interactive session (the §3 report spans every tier, so
narrow it to a single tier and show that tier's paths before asking, the
[confirmation gate](../SKILL.md#confirmation-gate)'s removal row is the same exact-tier-and-list bar the engine
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
   against live state and emits one verdict each, `clear`, `drifted` (identity or descendant
   set changed since the snapshot), `gone` (no longer present), or `contested` (protection,
   VCS state, a live handle, elevation, or unverifiable state). And never deletes anything.
   Act only on verdict-`clear` paths. Additionally confirm any owner process named in the audit
   evidence is still absent, that evidence is report-level, outside the engine's checks.

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
   is already stale at emission, and staler after each intervening deletion. Pair each
   deletion with its own fresh single-path handoff-verify run (verify one → delete that one →
   next); reserve the multi-path form for reporting. A clear verdict is valid only at emission
   time: delete immediately, and re-run handoff-verify after any delay or interruption.
2. Prefer reversible removal (Windows Recycle Bin / macOS Trash) over permanent deletion, and say
   which was used. That reversibility is conditional, not guaranteed: bin size caps, a
   policy-disabled bin, or a non-NTFS/network volume can silently make the same operation
   permanent, disclose when a target's volume or policy may turn "reversible" removal permanent.

   **Path length is a different failure, not a silent downgrade but a hard stop.** Those three
   caveats all describe a reversible operation quietly turning permanent. A path longer than the
   classic Windows `MAX_PATH` (260 characters) cannot reach the Recycle Bin *at all*: the shell
   APIs behind it reject the path, so the operation fails outright. Deep tool residue, nested
   dependency or build trees, routinely exceeds it. The only remaining way to remove such a path
   is a **permanent** delete through a `\\?\` long-path API, which no bin can undo.

   That fallback is its own irreversible action and does **not** inherit the approval given for a
   reversible removal. Stop, tell the operator this exact path cannot be recycled and why, and
   re-ask through the [confirmation gate](../SKILL.md#confirmation-gate) for permanent deletion of that exact
   path, named as irreversible, an approval that said "recycle these" never authorized it. If the
   operator declines, skip and report the path; shortening or moving the tree to get under the
   limit is a relocation, out of scope (§3) and the operator's own action. Record such removals as
   permanent in the §6 summary, distinct from the reversible ones.
3. Container-wide deletion commands (`Clear-RecycleBin`, emptying the Trash, or any "delete
   everything in this container" spelling) are forbidden in the manual lane, they execute
   against the live container, so items arriving between approval (or even re-enumeration) and
   execution die under an approval that never saw them. Satisfy "empty the container" by
   enumerating the container and deleting per item under steps 1, 2, and 4; items that arrive
   after enumeration are simply not deleted. This is the engine lane's changed-since-scan threat
   in the manual lane, where no snapshot token protects execution.
4. Skip and report any path whose verdict is not `clear`; never substitute a sibling, retry
   around a lock, or delete under a stale verdict.

## The PowerShell guard lane

The PowerShell guard lane turns deletion spellings into a final human permission prompt (the same
bar as the engine apply prompt); confirm that prompt only when the command matches the exact
approved list. Engine invocations from PowerShell stay hard-denied.

## Hook registration outlives the cleanup

Claude Code registers a skill's frontmatter hooks when the
skill is invoked and keeps them registered for the **rest of the session**. There is no
harness-level "while the skill is active" window for hooks (#2618). So once `/disk-hygiene:clean`
has run, the deny-by-default Bash lane and the PowerShell deletion prompts keep applying to
unrelated later work in the same session, not only to this cleanup. Say so when a later,
unrelated command is blocked or prompted, rather than treating it as a surprise; the session's own
end is what clears it. Both registration surfaces, the kill switch, and what the belt does and does not
bound: see [`safety-model.md`](safety-model.md).
