---
description: "Inventory and tidy the gitignored `.work` memory tiers (the repo's memory root and `~/.work`): report what is stale and what is in flight, normalize misplaced handoffs and retros, and remove stale known items behind one confirmation. Opt-in only; nothing runs unless invoked. Use when: 'tidy .work', 'clean up .work', 'what is piling up in .work', 'prune old handoffs', 'clear stale save-points', 'normalize my memory folder'. Handing off is /session-flow:handoff; making work durable before shutdown is /session-flow:clean-stop."
argument-hint: "[report|normalize|clean] [--days N] [--offline] [--memory-dir DIR]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tidy_work.py report:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse-concern-value.sh:*)"]
metadata:
  workflow-stage: session
  summary: Report, normalize, and clean stale .work memory items
---

# Tidy work

## Purpose

The memory root (default `.work/`, see
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md))
and `~/.work` collect handoffs, running-retro ledgers, workflow checklists, and slice folders
that nothing else deletes. This skill inventories them with age, size, and kind, marks what is
still in flight, and, only on request, moves misplaced items into the standard layout or removes
stale ones. `${CLAUDE_PLUGIN_ROOT}/scripts/tidy_work.py` does the work; this skill sequences it
and owns the confirmation.

Nothing runs unless the user invokes this skill.

## Actions

| Action | Effect |
|---|---|
| `report` (default) | Read-only inventory: path, age, size, kind, in-flight or stale, per item |
| `normalize` | Moves misplaced known-kind items into the standard layout. Never deletes, never overwrites an existing target |
| `clean` | Removes items that are a known kind and not in flight |

Pass `--days N` (default 14) to change the recency window. Pass `--offline` to treat every linked
issue or PR as unknown, which counts as in flight; without it the script asks `gh` for the open
issues and PRs of each repository a handoff names.

## Steps

1. **Resolve the memory root.** From the repository root, run
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse-concern-value.sh .claude/topic-docs.yaml memory_dir`,
   adding as a third argument a `memory_dir` the repo documents only in prose (`CLAUDE.md` or
   `.claude/rules/`). Empty output means the default `.work`. Pass the result as
   `--memory-dir <root>` on every invocation below; a `--memory-dir` the user gave wins. The
   resolution order is the one handoff uses
   ([`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md),
   "Where save-points live").
2. **Report.** Run
   `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tidy_work.py report --memory-dir <root> [--days N] [--offline]`
   and show the table. `report` is the only `tidy_work.py` invocation `allowed-tools`
   pre-approves. For `report` alone, stop here.
3. **Dry-run `normalize` or `clean`.** Run the same script with the action name and no
   `--apply`. It prints the exact absolute path of every move or removal and changes nothing.
   Show those paths to the user verbatim.
4. **Ask one confirmation** covering exactly the listed paths. A refusal, or silence, ends the
   run with nothing changed.
5. **Apply.** After a yes, re-run the identical command with `--apply`. That call is not
   pre-approved, so it goes through the normal permission flow. Report what moved or was
   removed, and any path the script refused.

## Always kept

An item whose kind is not recognized (for example a `drain/` status tree or any tool's own
folder) is always kept and always reported, by `report`, `normalize`, and `clean` alike. So is
every entry of another skill's concern dir (`reviews/`, `exports/`, `overengineering/`,
`enforceability/`, `docs-hygiene/`, `lanes/`): that skill reads it back. In-flight items are kept
too:

- a slice whose `INDEX.md` `status:` is not `done`, or that holds a child slice whose status is
  not `done` (`active`, `parked`, missing, and unrecognized all keep it)
- a workflow checklist with an unfinished stage
- a change inside the window
- a later handoff that names the item
- a handoff or running retro that names an open issue or PR, or one whose state could not be
  read

No flag overrides any of these.

## What this skill does NOT do

- **Does not delete or move anything without `--apply` and a confirmation** naming the paths.
- **Does not modify anything git tracks.** The script refuses a memory root whose `.gitignore`
  lacks a line `*`, refuses an item with a tracked file under it, and rejects a memory root that
  is the repository root.
- **Does not touch a path outside the resolved memory roots**, and does not follow a symlink
  that leaves one.
- **Does not write a handoff or make git state durable**; those are `/session-flow:handoff` and
  `/session-flow:clean-stop`.

## Next

/session-flow:clean-stop makes the remaining repo and worktree state durable before the machine goes away.

## Gotchas

- **`--offline` reads as "in flight", not "stale".** With link state unknown, every handoff
  that names an issue or PR is kept, so an offline `clean` removes less than an online one. That
  is the safe direction.
- **A bare `#N` is a reference into the repo that holds the memory root.** A handoff written in
  another repo can name an unrelated open item of this one and stay; in `~/.work`, where no
  repository is known, a bare `#N` counts as unknown and keeps the handoff. `owner/repo#N` and
  `github.com/.../issues/N` URLs are looked up in the repository they name.
- **Age is the item's modification time.** A restored or copied file looks fresh; the report
  shows the age it computed, so read it before confirming.
- **Confirm the dry-run you showed.** If the tree changed between the dry-run and `--apply`,
  re-run the dry-run and ask again rather than applying a stale list.
