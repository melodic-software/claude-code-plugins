---
bump: minor
---

### Added

- `interview`: optional plugin offers. `offers/offerable.json` lists the plugins the interview may offer (html-plan, an optional planner), and `offers/offer-source.mjs` checks each one: its marketplace must still list it under that name, and the newest commit on its source path sets the offer (under 3 months a plain offer, 3 to 6 months an offer with the date, older none). Each lookup is cached 24 hours in plugin data, a failed one too; any failure means no offer, and an unattended run looks nothing up (#12660).
- `interview`: with `surface` unset, the one surface line also names an installed optional planner (never required) and carries any offer. On a yes the interview installs the plugin at user scope and points to `/reload-plugins` (#12660).

### Changed

- `interview`: the page lane's clauses in the gate sections (the Brief cross-check's `--surface` flag and its Gates twin, where the confirmation gate is shown, the facts-field citation, the full recap, the procedure-check exception's tick rows) and the exit codes section move to `context/lane-page.md`; `SKILL.md` names no surface value in those sections (#12660).
