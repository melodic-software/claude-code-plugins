# Remove a folder's unrecorded profile entries only on a yes for that folder

- Status: accepted
- Date: 2026-11-19
- Refs: [#17354](https://github.com/melodic-software/claude-code-plugins/issues/17354); owner
  decisions of 2026-11-18 (interview, relayed by the control-hub session);
  [ADR 0113](0113-reset-every-recorded-settings-file-on-the-machine-found-through-repository-pointers-and-a-scan.md)

## Context

A folder's `.claude/settings.local.json` can hold `enabledPlugins` or `skillOverrides` entries with
no record of a profile apply: the record was lost with a fresh clone, an earlier tool wrote them, or
a person wrote them by hand. Without a record the tool cannot tell which entries a profile wrote,
so `clear` names the keys and changes nothing. A machine-wide reset meets such folders in numbers,
and the owner wants reset to cover them without a person's own entries going under the yes they
gave for the recorded files.

## Decision

1. **Listed, not hidden.** Reset lists each folder it knows whose `settings.local.json` holds those
   entries and no record, in the same preview, with each entry.
2. **A yes per folder.** Its `enabledPlugins` and `skillOverrides` keys are removed only after a yes
   for that folder: a terminal asks one question per folder after the single yes, and a caller that
   has asked already (the `/plugin-profile` picker, the profile skill) passes
   `--remove-unrecorded <file>` once per yes and `--keep-unrecorded <file>` once per no, which is
   reported as kept at that answer. A named file the preview did not ask about stops the reset
   before anything is written, and the refusal names the files it does ask about.
3. **`--yes` is the single yes only.** It restores every recorded file and skips each folder without
   a record, saying why.
4. **User settings are never offered.** User `settings.json` without a record is left alone, and a
   committed `.claude/settings.json` is never written.
5. **A file reset put back is not offered again while unchanged.** Each time reset leaves a file
   at its bytes before any profile, it notes their hash beside where that file's record is saved,
   under the same rule for which homes may hold it. A later reset skips a file whose bytes still
   match its note: no row, no question, no write, and one preview line counting such files. An
   edit makes the note stale, so the file is listed under 1 and 2 again and the next reset that
   writes removes the note; an apply removes it, and a record always wins over a note. Owner
   decision of 2026-11-19 (Q9, option b): without it a second reset offered to delete the
   entries the first had just put back.

## Considered options

- **Today's `clear` behavior: name the keys and change nothing.** Rejected by the owner: a reset
  that leaves profile entries it can see is not a reset.
- **Remove them under the single yes.** Rejected by the owner: one yes for recorded files would then
  also delete entries a person wrote, which no record shows a profile wrote.
- **Keep listing a file reset just put back, with "may be your own" wording only.** Rejected by the
  owner (Q9): it still offered a person's own entries for deletion after a complete reset.

## Consequences

- An unattended `reset --yes` never removes an entry no profile recorded.
- The preview grows by one row per such folder, and each defaults to keep.
- Every caller that runs reset for a person asks the single question and each per-folder question
  in the tool's own text, which the `--json` preview carries. The single question says it covers
  only the files with a record, and a per-folder question names the count and the first few
  entries, the full list staying in the preview.

## Revisit triggers

- Records gain a way to be rebuilt after a fresh clone, so fewer folders lack one.
- The owner finds the per-folder questions too many in practice.
