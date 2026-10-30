---
bump: patch
---

### Changed

- The review discipline gains an `INTENTIONAL` outcome ([#7642](https://github.com/melodic-software/claude-code-plugins/issues/7642)): a finding that describes the code correctly where the code is that way on purpose is answered with its reason in the D5 reply and files no tracker item. It is not available for a defect the change introduced, which stays `VALID (fix now)`.
