---
bump: patch
---

### Fixed

- count a lane comment record only once it is complete

  The lane now closes each attempt's comment record with a
  `{"complete":true}` line once its publish and hold steps did not fail
  (ci-workflows pr-review-cli). The lane-binding checker counts a record as
  covering its attempt only when it holds that line; an attempt cut off
  between posting and recording reads as one that left no record, so its
  comments fall to the time-window check instead of being rejected.

  Test fixtures for lane comments with no binding now carry their
  createdAt, ready for LEGACY_CUTOFF, which stays null here. The Python
  test pins its cutoff to the JavaScript port's.
