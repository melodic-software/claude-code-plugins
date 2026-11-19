---
bump: minor
---

### Added

- `profiles.mjs reset` puts every settings file a profile changed on the machine back, user settings included, behind one preview and one yes; a reset stopped part way finishes on the next run. It reads a record only from a home that can hold it, refuses a write that no longer matches the preview passed with `--preview-id`, and exits 3 when it wrote what it could and named each file it skipped. A moved repository with another profile applied at its new place is one row: its yes puts the file back to what it held before the first apply, in one write, and removes both records; with `--yes` and no answer for it, the newest profile is put back and the older record kept for a later reset; a repository moved more than once is one row too, folding every record. A no to the one question keeps the recorded files and still asks each file's own question (`--keep-recorded` for a caller). A file changed by hand after a reset was stopped before its write keeps its record and gets its own yes (`--finish-cut-off`, `--keep-cut-off`), which puts back only the entries still at the profile's values.
- The `/plugin-profile` picker has a **Reset** row under No profile, and the profile skill has a reset action; both show the same preview and ask before writing, and a folder without a record changes only on a yes for that folder. Each per-file question in `reset --dry-run --json` carries its answers' labels and flags.
- Reset notes the bytes it left in each file it put back, so a later reset does not offer that file's own entries for removal while it is unchanged; an edit or an apply ends that.

### Changed

- A one-session file also names each installed plugin of every other marketplace some profile governs, at its value at launch, so a reset or another profile elsewhere never changes that session's plugins; a later `/plugin` toggle of such a plugin reaches only sessions started after it.

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since, including one cleared or reset while it lists the installed plugins: it saves its record only while the pending record it read is unchanged.
