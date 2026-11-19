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
   `--remove-unrecorded <file>` once per yes. A named file the preview did not list stops the reset
   before anything is written.
3. **`--yes` is the single yes only.** It restores every recorded file and skips each folder without
   a record, saying why.
4. **User settings are never offered.** User `settings.json` without a record is left alone, and a
   committed `.claude/settings.json` is never written.

## Considered options

- **Today's `clear` behavior: name the keys and change nothing.** Rejected by the owner: a reset
  that leaves profile entries it can see is not a reset.
- **Remove them under the single yes.** Rejected by the owner: one yes for recorded files would then
  also delete entries a person wrote, which no record shows a profile wrote.

## Consequences

- An unattended `reset --yes` never removes an entry no profile recorded.
- The preview grows by one row per such folder, and each defaults to keep.
- Every caller that runs reset for a person asks per folder in the tool's own question text, which
  the `--json` preview carries.

## Revisit triggers

- Records gain a way to be rebuilt after a fresh clone, so fewer folders lack one.
- The owner finds the per-folder questions too many in practice.
