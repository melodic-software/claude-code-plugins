# Reset every recorded settings file on the machine, found through repository pointers and a scan

- Status: accepted
- Date: 2026-11-19
- Refs: [#17354](https://github.com/melodic-software/claude-code-plugins/issues/17354); owner
  decisions of 2026-11-18 (interview and plan approval, answers P2 and P4, relayed by the
  control-hub session); extends [ADR 0109](0109-switch-plugin-sets-by-profile-and-gate-optional-calls-on-enabled-skills.md)

## Context

A profile apply keeps a record of what it changed beside each settings file it wrote: in the
repository's git common folder for a folder in git, in `~/.claude/plugin-profiles-state` for user
settings, and in the plugin's data folder otherwise. `clear` restores one file from its record, so
backing every profile out of a machine meant running `clear` in each folder a profile was ever
applied in. A record's file name is a hash of its settings file's path, so nothing in the tool
listed the repositories that hold records.

## Decision

1. **Scope.** `profiles.mjs reset` restores every settings file on this machine whose record the
   tool can find, whenever it was applied: each folder file, a worktree's or subdirectory's own file,
   and user settings for the initial profile, behind one preview. It does not reach another lane,
   another machine or another config folder.
2. **Finding repositories.** Each apply into a repository, and each session start in one whose
   folder has a record, writes one pointer file per repository under
   `~/.claude/plugin-profiles-state/repositories/`, keyed by a hash of the record home, so concurrent
   applies never write the same file. Every reset also reads the folders in `~/.claude.json`
   `projects`, each one-session record's folder, each live session's folder and the folder it runs
   in, resolves each to its repository, and reads the user state home and every data folder.
   Records are grouped by settings file, so a file with records in two homes is restored once. A
   record counts only from a home that can hold it (the same homes `clear` reads for that file);
   one elsewhere, such as a repository's `.git` naming user settings or another repository's file,
   is listed as ignored and never written from.
3. **What stays unfound.** A repository with no pointer whose every known path is gone (a removed
   worktree, a submodule known only from its superproject) until a session starts there, an apply
   from a plain terminal in a folder Claude Code never opened, and other config folders. The README
   and the scenarios table name them.
4. **A record whose folder is gone is kept.** Reset never deletes it under the one yes; when it was
   the record of a main checkout's root file and that repository moved, the preview names the
   repository's root file where it is now, which reset restores from the record only after a yes
   for it. A gone subfolder or linked worktree of a repository still there is only kept.
5. **The write answers one preview.** The `--json` preview carries `previewId`; a caller that
   previewed in one process and writes in another passes it, and the write refuses, writing
   nothing, when what it would write differs from that preview.

## Considered options

- **This folder plus the initial profile only.** Rejected by the owner: backing out still means
  remembering every folder.
- **Every lane at once.** Rejected by the owner: out of scope; each lane resets its own machine.
- **No new command.** Rejected by the owner: the per-folder steps are what the reset removes.
- **Pointer files only.** Rejected: misses every apply made before reset shipped.
- **Scan `~/.claude.json` only.** Rejected: its `projects` key is undocumented, and it misses a
  repository applied from a plain terminal.
- **One shared index file of repositories.** Rejected: concurrent applies in several terminals
  would race on one file, and no lock exists.
- **Walk a folder tree for `.git/plugin-profiles`.** Rejected: the tool has no general root, and a
  walk of a home folder is slow.
- **Delete the record of a folder that cannot be found.** Rejected (owner, P4): a moved repository
  and a gone one look the same, and the record is the only path back.

## Consequences

- The pointer file and its folder are a contract later versions read; changing their shape is a
  migration.
- A repository applied before reset shipped is found once any session starts in it, or through a
  folder Claude Code has opened.
- A record of a folder that is gone is listed on every reset until its repository is moved back or
  its moved file is restored.
- `~/.claude.json` is read tolerantly: a missing or reshaped `projects` key gives no folders.

## Revisit triggers

- Claude Code documents or removes the `projects` key of `~/.claude.json`.
- A live reset misses a folder the owner knows holds a profile.
- Claude Code ships a native plugin-set feature (ADR 0109's trigger).
