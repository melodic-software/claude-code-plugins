---
bump: patch
---

### Changed

- fable-5 `recovery.md`: the environmental tool-failure class no longer lists permission denied; a denial points to trust-and-authority, "A denied action is a boundary, not an obstacle".
- fable-5 `calibration.md`: new section, price optional security hardening against what the attacker already holds.
- fable-5 `verification.md`: new section, rule out the test setup before raising a probe result as a finding.
- fable-5 chapter routing: recommending optional security hardening loads `calibration.md`, and raising a probe or sandbox result as a finding loads `verification.md`.
- New plugin eval case `denied-call-stops-and-reports`: a call a guard hook denied is stopped and reported, not routed around.
