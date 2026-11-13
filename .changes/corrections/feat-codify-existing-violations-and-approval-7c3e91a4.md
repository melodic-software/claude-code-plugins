---
bump: minor
---

### Changed

- **`/corrections:codify` proposals state existing violations and offer their cleanup.** A proposed check or rule now states how many places in the current tree already break it, and offers their cleanup in the same change, carried out by `/implementation:implement`. The `/toolchain:ratchet` offer (`ratchet_offer`) now applies only when the violations are too many to fix in that one change, or cannot be counted. Codify still fixes nothing itself.
- **Approval rule recorded.** Codify's "Consent and write" section states that every change it proposes needs a person's approval, and that applying one without approval becomes allowed only where an evaluation set scores the changed surface and the change does not lower the score.
