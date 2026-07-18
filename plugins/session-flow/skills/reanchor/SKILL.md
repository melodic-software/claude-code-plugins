---
name: reanchor
description: "Verify a session's working assumptions are still true before building on them — referenced PRs/issues/branches still in the state a handoff or plan claims, base-branch drift, cited skills/plugins that were renamed or version-drifted, and memory-tier files whose subjects have since landed. Reports what drifted and re-anchors; does not resume the work. Use when: 'reanchor', 're-anchor', 'is this still current', 'verify my assumptions', 'has main moved since', 'are these premises still valid', 'is the handoff stale', 'resuming an old plan', 'check freshness'. Not for resuming work (use /session-flow:keep-going), the cross-worktree staleness inventory, PR feedback triage, or re-anchoring a standing behavioral rule (this re-anchors factual premises, not rules)."
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
2. **Base-branch drift.** Check whether the working branch is now behind its
   base. Derive the base from the base branch of the PR whose head is the current
   working branch (or, absent such a PR, the remote's default HEAD) — not another
   referenced PR's base and not an assumed `main` — and mark the check
   unverifiable if the base cannot be resolved. Fetch that resolved base ref
   explicitly and count against the just-fetched tip: `git fetch <remote>
   <base-branch>`, then measure against `FETCH_HEAD`
   (e.g. `git rev-list --count HEAD..FETCH_HEAD`). A bare `git fetch`, or a count
   against a local `origin/<base>` tracking ref, can read falsely clean in a
   single-branch or shallow checkout where that ref was never updated —
   `FETCH_HEAD` always holds what this fetch actually retrieved. If the fetch
   cannot run, report the check as unverifiable rather than assuming none. Unless the inputs record a base-tip
   or merge-base baseline, report the *current* divergence rather than claiming
   it all accrued since the inputs were written — the branch may already have
   been behind. This is reanchor's own check. `/source-control:worktree`, when
   installed, is a related but distinct capability — a cross-worktree inventory
   by path / branch / PR / commit-age staleness — that does not report
   behind-base or dirty-tree signal; cite it for that inventory, not for the
   drift evidence here.
3. **Renamed / retired / version-drifted surfaces.** For the skills, plugins,
   and commands the session's inputs name, confirm they still exist under that
   name and — when the session is working inside a plugin's source tree — that
   the version effective in the current project's scope (honoring user / project /
   local scope precedence, not merely the highest installed version a plugin
   listing reports) matches that source manifest; a rename or version bump
   silently invalidates cited invocations and assumed behavior. When a cited plugin's source manifest is not
   locatable in the working tree, report the version comparison as unverifiable
   rather than guessing Claude Code's internal cache layout.
4. **Stale memory-tier files.** For the session's handoff / todo / working-memory
   files, flag entries whose subjects have since merged or landed, so the next
   step neither re-does settled work nor chases a closed thread.

## Flow

1. Gather the session's inputs — the handoff / plan / memory files and any PRs,
   issues, branches, skills, or plugin versions they name.
2. Run the four checks above against live reality — fetch/read the live source
   (`git fetch` the base, query `gh`, read installed vs repo-source manifests).
   When a check cannot reach what it needs (no network, no `gh`, no fetch),
   report that premise as **unverifiable** rather than assuming it is unchanged;
   a silent "no drift" from stale local state is the exact failure this skill
   exists to prevent.
3. Report drift as a short list — premise → claimed state → actual state — plus
   the re-anchored picture. Surface it; do not silently rewrite the plan or
   auto-fix. The session re-plans on the corrected reality.

## What this skill does NOT do

- **Does not resume or continue the work.** It verifies premises; picking the
  work back up is `/session-flow:keep-going`.
- **Does not inventory worktrees.** Enumerating every worktree by
  path / branch / PR / commit-age staleness is `/source-control:worktree`
  status's job when that plugin is installed; reanchor does its own base-drift
  check (a `git` behind-count on the working branch) and never reimplements that
  cross-worktree inventory.
- **Does not classify PR feedback or run the PR loop.** Per-PR fresh-evidence
  discipline and feedback triage are `/source-control:babysit-prs`'s job when
  it is installed; reanchor never performs them — it only checks whether a
  *referenced* PR is still in its claimed state.
- **Does not re-anchor a standing rule or discipline.** Correcting behavioral
  doctrine mid-session (a standing-rule re-anchor) is a separate concern; this
  skill re-anchors factual assumptions against live reality, not rules.
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
