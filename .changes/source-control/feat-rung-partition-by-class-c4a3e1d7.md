---
bump: major
---

### Changed

- The babysit loop's rung partition admits C4 (structural) pull requests at `c3-autonomous`, `full-autonomy` and the typed `autopilot` + `--merge c3-this-run` widening, against the `C3-auto-merge` promotion cell, so the cell's blocking AI review is the gate and no human review or merge is required once it is effective-promoted. `c2-mechanical` still admits C2 alone. C5 (untrusted provenance) stays the one class no rung, config key or argument admits. The former C4 diff veto is now a diff-class check: the diff can raise a pull request's recorded class, never lower it, and a diff whose class cannot be read still fails closed. A C4 pull request in the eligible set can draw the pre-escalation resolver dispatch (#9668, #12068).
