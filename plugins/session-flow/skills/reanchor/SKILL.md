---
name: reanchor
description: "Verify a session's working assumptions are still true before building on them — referenced PRs/issues/branches still in the state a handoff or plan claims, base-branch drift, cited skills/plugins that were renamed or version-drifted, and memory-tier files whose subjects have since landed. Reports what drifted and re-anchors; does not resume the work. Use when: 'reanchor', 're-anchor', 'is this still current', 'verify my assumptions', 'has main moved since', 'are these premises still valid', 'is the handoff stale', 'resuming an old plan', 'check freshness'. Not for resuming work (use /session-flow:keep-going), per-worktree staleness (use /source-control:worktree status), PR feedback triage (use /source-control:babysit-prs), or re-anchoring a standing behavioral rule/discipline (that is the re-anchor plugin — this re-anchors factual premises, not rules)."
user-invocable: true
disable-model-invocation: false
---

# Reanchor

## Purpose

Long-lived and resumed sessions act on stale premises: main has moved, a
referenced PR merged or changed shape, a cited skill was renamed, an installed
plugin shipped a new version, a locked plan references work that has since
landed. Nothing re-verifies those assumptions against live reality before the
session builds on them. This skill re-anchors a session's working assumptions —
checks each premise its inputs depend on against the current state, reports what
drifted, and hands back a corrected picture to plan from.

It verifies premises; it does not resume the work. Run it before continuing on
old inputs, then hand to `/session-flow:keep-going` to actually pick the work
back up.

## What it re-anchors

1. **Handoff / plan premises.** For every PR, issue, or branch a handoff or
   locked plan references, confirm it is still in the state the document claims
   — open vs merged/closed, same head, same base, not renamed. A plan that
   assumes an in-flight PR is often built on one that already landed.
2. **Base-branch drift.** Check whether the working branch's base has moved
   since the session's inputs were written — the branch may now be behind, or a
   premise ("this isn't on main yet") may already be false. When
   `/source-control:worktree` is installed, cite its status for the full
   per-worktree staleness inventory (behind-base counts, dirty state, PR
   linkage) instead of recomputing it; otherwise do the reduced local check (a
   `git` behind-count) and report the fuller inventory as unavailable.
3. **Renamed / retired / version-drifted surfaces.** For the skills, plugins,
   and commands the session's inputs name, confirm they still exist under that
   name and that installed plugin versions match the repo source — a rename or a
   version bump silently invalidates cited invocations and assumed behavior.
4. **Stale memory-tier files.** For the session's handoff / todo / working-memory
   files, flag entries whose subjects have since merged or landed, so the next
   step neither re-does settled work nor chases a closed thread.

## Flow

1. Gather the session's inputs — the handoff / plan / memory files and any PRs,
   issues, branches, skills, or plugin versions they name.
2. Run the four checks above against live reality (git, `gh`, installed vs
   repo-source manifests).
3. Report drift as a short list — premise → claimed state → actual state — plus
   the re-anchored picture. Surface it; do not silently rewrite the plan or
   auto-fix. The session re-plans on the corrected reality.

## What this skill does NOT do

- **Does not resume or continue the work.** It verifies premises; picking the
  work back up is `/session-flow:keep-going`.
- **Does not inventory worktrees.** Per-worktree/branch staleness (behind-base
  counts, dirty state, PR linkage) lives in `/source-control:worktree` status
  when that plugin is installed; this skill cites it, never reimplements it, and
  falls back to a reduced local base-drift check (flagging the fuller inventory
  as unavailable) when it is absent.
- **Does not classify PR feedback or run the PR loop.** Per-PR fresh-evidence
  discipline and feedback triage are `/source-control:babysit-prs`'s job when
  it is installed; reanchor never performs them — it only checks whether a
  *referenced* PR is still in its claimed state.
- **Does not re-anchor a standing rule or discipline.** Correcting behavioral
  doctrine mid-session is the `re-anchor` plugin's concern; this skill re-anchors
  factual assumptions, not rules.
- **Does not auto-fix drift.** It reports; the session decides.

## Gotchas

- A premise that "looks" current is the failure mode: a PR cited as open may
  have merged minutes ago; a plugin cited by version may have bumped. Check the
  live source, never the input's own claim.
- Scope to what the session's inputs actually reference — re-anchoring is bounded
  by the premises in play, not a full-repo audit.
- It composes with, not replaces, its neighbors: reanchor to learn what drifted,
  then `keep-going` (same plugin) to resume; and, when they are installed,
  `/source-control:worktree` status for the worktree inventory and
  `/source-control:babysit-prs` for PR work.
