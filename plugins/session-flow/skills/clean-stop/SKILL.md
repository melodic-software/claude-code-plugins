---
description: "Reach a clean stopping point before the machine may go away: sweep every repo and worktree touched for uncommitted, unpushed, or PR-less work, push it, record follow-ups in PR and issue bodies, prune only the provably safe, and give a free-and-clear verdict. Use when: 'clean stop', 'get to a clean stopping point', 'safe to shut down', 'wrap up before I lose this machine', 'make everything durable', 'stopping for the day', 'is anything stranded', 'leave it clean'. Gates destructive cleanup."
argument-hint: "[unattended]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Make everything durable before the machine goes away
---

# Clean stop

## Purpose

Before a machine may disappear, whether that is end of day, a spot instance about to
reclaim, a container about to be torn down, or just walking away, in-flight
work is easy to strand: a commit that never pushed, a branch with no PR, a
plan that lives only in a local file, a worktree nobody will find again. This
skill sweeps everything touched this session to a durable, linked resting
state and reports whether it is genuinely safe to shut down.

Where `/session-flow:keep-going` recovers a session AFTER an interruption,
clean-stop is its go/stop mirror. It makes the interruption safe BEFOREHAND,
so there is nothing to recover. It supersedes a local `/session-flow:handoff`
when the machine itself may go away: a handoff file is a machine-local
save-point, and a save-point that dies with the disk is no save-point.
clean-stop leaves the resumable state where it survives the machine, in the
PR and issue bodies on the remote.

## Arguments

`unattended` is the only argument. It only gates the `/export` step (record the suggestion in
output, do not ask); remote artifacts are always created without prompting, as step 3 states.

## Steps

1. **Inspect first, never assume.** Enumerate every repository and worktree
   this session touched and read its real state: uncommitted changes,
   stashes, unpushed commits, branches without a PR, which PRs/issues already
   carry the resumable context, and any ignored, machine-local state that is
   not reproducible, a generated handoff, local config, hand-made
   credentials, which `git status` hides but which dies with the disk just
   the same. Act only on the gaps. Running
   clean-stop when a branch is already pushed and its PR already describes the
   work must NOT re-push, open a duplicate PR, or re-file issues. The sweep
   converges on what is missing, not on redoing what is done.
2. **Durability sweep.** Make the gaps durable. Push unpushed commits; for
   coherently committable work, including a clean, coherent stash, commit
   it with a real message and push. What is NOT coherently committable,
   ambiguous work-in-progress, a half-edit, a stash that will not cleanly
   apply, is not force-committed and not silently dropped: surface it in the
   verdict as an explicit "not durable, do X before shutdown" item. A bad
   commit and a lost stash are both worse than a named dangling item. Ignored,
   machine-local state that must not go to the remote, secrets, credentials,
   deliberately-ignored files, is never pushed; when it is not reproducible,
   surface it as a "preserve off the machine before shutdown" item so it is
   not silently lost with the disk.
   The conversation itself is another machine-local, non-durable item:
   transcripts live only in this machine's `~/.claude` tree and are
   retention-swept besides. When the session is worth keeping:
   If /export is available in your session (gate basis: **Verification record: `/export`** below), suggest that the person run it for a durable conversation copy at `<memory_dir>/exports/<YYYYMMDDTHHMMSSZ>-<topic>.txt` after verifying the memory root's self-ignore guard (a `.gitignore` containing `*`; create it and announce it when absent). This skill never invokes `/export` itself. **`unattended`:** record the suggestion in output; do not ask.
   That destination is machine-local, so when the machine may go away, also
   surface copying the export off the machine as a "preserve off the machine" item.
3. **Linkage + breadcrumbs (redact before any remote write).** Before a PR
   or issue body is created or updated, sweep everything outbound: remaining
   tasks, dependencies, resume context, any pasted terminal output or diffs,
   for secrets, API keys, tokens, credentials, connection strings, and PII,
   and replace each hit with a shape marker (`<REDACTED: API key>`), never the
   value. This scrub is a hard gate: the breadcrumbs land on a remote shared
   with others and pass no human review first, so nothing outbound is written
   before it runs. Then link the work: every pushed *non-default* branch gets
   a PR. A branch that is the repo's default (`main` / `master` / `trunk`, or
   whatever `git symbolic-ref refs/remotes/origin/HEAD` resolves to) carries
   no PR and needs none once pushed. Every follow-up gets filed as an issue
   LINKED to that PR; dependencies, remaining tasks, and the context needed to
   continue live in the PR and issue bodies, never only in a local file. The
   acceptance bar is a cold agent: someone who finds the PR or issue with no
   memory of this session should have everything needed to offer to continue.
   Every remote artifact is created unattended, so the issue-linkage decision
   is made up front, never left for an interactive prompt: use the closing
   keyword when the branch or context names an issue, otherwise an explicit
   no-linkage reason. For an orphan branch, a hotfix, refactor, or drift
   sweep with no issue in its name, open the PR with the forge's own tooling,
   passing that no-linkage reason, the title, and the body non-interactively:
   the guaranteed non-interactive path. Route through
   `/source-control:pull-request create` (if that plugin is installed) or a
   work-item capability only when it can run unattended with that decision
   passed in; if it would stop to ask, use `git` and the forge's own tooling
   carrying the same decision instead.
4. **Local hygiene.** Prune only what is provably safe: branches whose work is
   fully merged, worktrees with no uncommitted or stashed state and no
   irreplaceable ignored files, background work that has genuinely finished. A
   plain `git status` hides ignored files, but `git worktree remove` deletes
   them, so before removing a worktree, inspect its ignored content
   explicitly (`git status --ignored`) and preserve or surface anything not
   reproducible: a local `.env`, credentials, generated handoff data, or files
   a bootstrap copied in. Anything still holding unmerged commits, dirty state,
   irreplaceable ignored files, or a running job is NOT pruned. It becomes a
   named item in the verdict.
5. **Free-and-clear verdict.** Lead the report with one of two honest
   outcomes: "clean to shut down, everything durable and linked", or a named
   list of the dangling items that still need a hand, each with the one
   action that would clear it; what was pushed, opened, and filed follows.
   Never report clean while step 2 or 4 left something surfaced.

## Autonomy policy. Make durable freely, gate destructive cleanup

- **Make durable without asking.** Pushing a commit, opening a PR for a
  pushed branch, and filing a linked follow-up issue are loss-prevention with
  low blast radius and are the whole point of the invocation: do them once
  the step 3 redaction gate has scrubbed anything outbound. Idempotency comes
  from step 1: act on gaps, never re-fire what already landed.
- **GATE destructive hygiene.** Deleting a branch, removing a worktree, or any
  force operation is irreversible. Do it only when step 1 PROVED it safe
  (fully merged, no uncommitted or stashed state, and, for a worktree, no
  irreplaceable ignored files a plain status hides). When safety cannot be
  proven, do not prune; name the item in the verdict instead. Losing unmerged
  work, or the only copy of an ignored `.env`, to a tidy-up is the exact
  failure this skill exists to prevent.

## Nothing-dirty case

If the sweep finds everything already durable and linked, nothing
uncommitted, nothing unpushed, every non-default branch that carries session
work has a PR (work committed straight to the default branch is durable once
pushed and needs none), nothing strandable left only on local disk, including
non-reproducible ignored state a plain status hides, say so and give the
free-and-clear verdict directly. A clean session is a valid, common outcome;
do not manufacture work to look thorough.

## Verification record: `/export`

- **Claim.** `/export` is a built-in interactive command (local-jsx, not a prompt): the Skill tool never lists it and it is unavailable headless, so this skill suggests it to the person and never runs it. It has no documented disable switch: a command that is not available to the person is left out of the menu.
- **Basis.** The `/export [filename]` row on <https://code.claude.com/docs/en/commands>, fetched 2026-09-29: "Export the current conversation as plain text. With a filename, writes directly to that file. Without, opens a dialog to copy to clipboard or save to a file". Probed 2026-08-24 on Claude Code 2.1.241: `claude --bare -p "/export <path>"` returned "/export isn't available in this environment."; invocation mode local-jsx on 2.1.263 (2026-09-11).
- **As of.** 2026-09-29.
- **Recheck when.** A Claude Code release note or the commands page adds an `/export` format or redaction flag, a headless or programmatic form, or an official conversation-sharing surface.

## What this skill does NOT do

- **Does not leave resumable state in a local file.** Context goes into PR
  and issue bodies precisely because a local file dies with the machine,
  that is what separates clean-stop from `/session-flow:handoff` and why it
  supersedes it when the machine may go away.
- **Does not force-commit ambiguous work.** Work that is not coherently
  committable is surfaced as a dangling item, never wrapped in a junk commit
  to make the tree look clean.
- **Does not prune unmerged or dirty state.** Destructive cleanup is gated on
  provable safety; when in doubt it names the item rather than deleting it.
- **Does not duplicate capability mechanics.** It routes PR, issue, and
  worktree work to whatever capabilities are installed and falls back to
  `git` and the forge's or tracker's own tooling; it does not reimplement them.
- **Does not report clean while something dangles.** The verdict is honest,
  either genuinely free-and-clear or a named list.

## Gotchas

- "Pushed" is not "linked". A branch can be safely on the remote and still
  strand its context if no PR or issue carries the why and the next step. The
  durability sweep and the breadcrumb bar are two separate checks; passing the
  first does not pass the second.
- Idempotency is load-bearing. clean-stop is often run more than once as a
  session winds down; every run must inspect real state first so the second
  run is a no-op on what the first already made durable, not a source of
  duplicate PRs or issues.
- A stash is invisible to a casual glance and cannot be pushed. Inspect for
  stashes explicitly; each one is either converted to a durable commit or
  named in the verdict, never left to die with the machine.
