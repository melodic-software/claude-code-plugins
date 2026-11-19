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
   for it. **One layer per reset:** in one run at most one row writes or asks about a settings
   file. A file with its own record, in any state, is handled by that record's row; a moved record
   is offered for the file only when the file has no record of its own and no moved record applied
   later points at it. Every other moved record is kept, asks nothing and writes nothing, and its
   line says a later record goes first. So a repository with profiles applied before and after a
   move goes back one layer per run, newest first: each run is an ordinary single-record restore,
   and each layer's before-values are the after-values of the layer below, so after the last layer
   the file holds what it held before the first apply. A run that put back a file a moved record
   waited behind exits 3 and says how many records wait and to run reset again; a no at any layer
   keeps the file and every record. A gone subfolder or linked worktree of a repository still there
   is only kept.
5. **The write answers one preview.** The `--json` preview carries `previewId`; a caller that
   previewed in one process and writes in another passes it, and the write refuses, writing
   nothing, when what it would write differs from that preview.
6. **A reset cut off part way.** Before each file's write its record is saved as `restoring`, with
   the hash of the text it is about to write and the hash of the file it read. The next reset
   finishes a file holding the written text, and restores one still holding the text read or every
   entry the profile wrote. A file changed since in any other way is ambiguous: "the write finished,
   then an entry was edited" and "the write never happened, then entries were put back by hand"
   look the same. When no recorded entry still holds the value the profile wrote, nothing is left
   to put back: the file is left as it is and its record removed. Otherwise reset keeps the record,
   writes nothing by itself and asks a yes for that file through the per-file question of
   [ADR 0114](0114-remove-a-folders-unrecorded-profile-entries-only-on-a-yes-for-that-folder.md),
   default no: the yes puts back only the entries still at the profile's values, never one changed
   by hand, then removes the record; a no, `--yes` alone or nobody to answer keeps the file and
   its record, and later resets list it again. Owner decision of 2026-11-19 (Q10); it replaces the
   plan's rule that reset deletes such a record without writing, which left the entries still at
   the profile's values with no way back when the write had never happened.

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
- **Delete a cut-off reset's record when the file changed since, writing nothing.** Rejected
  (owner, Q10): when the earlier write never happened, the entries still at the profile's values
  lose their only way back.
- **Delete the record of a folder that cannot be found.** Rejected (owner, P4): a moved repository
  and a gone one look the same, and the record is the only path back.
- **Fold every record of a moved repository's file into one write.** Tried and dropped: each fold
  rule (a newer record at the new place, a repository moved twice, a fallback for `--yes` alone,
  a newer record that is cut off or unreadable) met a combination it did not cover, and the last
  one asked two questions about one file and let a yes to one undo a no to the other, against
  decision 6. One layer per run needs no rule beyond a single-record restore and costs another
  run per layer.

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
