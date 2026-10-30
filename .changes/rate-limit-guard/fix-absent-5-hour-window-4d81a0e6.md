---
bump: patch
---

### Fixed

- For an account with no 5-hour limit, such as a verified Ultra account, the band row no longer shows a permanent `5h -`: once a reading arrives it shows only the windows the account reports. `/rate-limit-guard` says such a window is "not in the last response" rather than "no reading".
