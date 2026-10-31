---
bump: minor
---

### Added

- The `ready` report has a measure verdict line when `/verification:measure` recorded one for the
  head it flipped: the verdict with the claim it judged, reading `CANNOT QUANTIFY` when no
  baseline was captured before the change. A head with no measure verdict gets no line. The line
  is advisory, so no measure verdict holds the PR in draft.
