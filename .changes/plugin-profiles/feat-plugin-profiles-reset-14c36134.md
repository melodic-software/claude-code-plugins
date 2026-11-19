---
bump: minor
---

### Added

- `profiles.mjs reset` puts every settings file a profile changed on the machine back, user settings included, behind one preview and one yes; a reset stopped part way finishes on the next run. It reads a record only from a home that can hold it, refuses a write that no longer matches the preview passed with `--preview-id`, and exits 3 when it wrote what it could and named each file it skipped. A moved repository with profiles applied before and after the move goes back one layer per reset, newest first, each run writing a file from one record only; a run that leaves an older record waiting exits 3 and says to run reset again, and after the last layer the file holds what it held before the first apply. A no to the one question keeps the recorded files and still asks each file's own question (`--keep-recorded` for a caller). A file changed by hand after a reset was stopped before its write keeps its record and gets its own yes (`--finish-cut-off`, `--keep-cut-off`), which puts back only the entries still at the profile's values, counting an entry an unfinished switch still owes until it is back at its value before the profile.
- The `/plugin-profile` picker has a **Reset** row under No profile, and the profile skill has a reset action; both show the same preview and ask before writing, and a folder without a record changes only on a yes for that folder. Each per-file question in `reset --dry-run --json` carries its answers' labels and flags and a recommended answer with a one-sentence reason (`ask.recommend`; `questionRecommend` for the one question); the picker shows it as a line before the question and the skill marks that answer `(Recommended)`.- Reset notes the bytes it left in each file it put back, so a later reset does not offer that file's own entries for removal while it is unchanged; an edit or an apply ends that.

### Changed

- Every question the `/plugin-profile` picker and the profile skill ask lists the answer that changes nothing first (Cancel, Keep, No), so the picker pre-selects it, the apply, switch and clear confirms included; Esc is that answer.
- A one-session file also names each installed plugin of every other marketplace some profile governs, at its value at launch, so a reset or another profile elsewhere never changes that session's plugins; a later `/plugin` toggle of such a plugin reaches only sessions started after it.

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since, including one cleared or reset while it lists the installed plugins: it saves its record only while the pending record it read is unchanged.
