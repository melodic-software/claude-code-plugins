---
bump: minor
---

### Changed

- The babysit merge gate reads pr-review-main's `verdict=none reason=<reason>` check run as a
  designed stop. The stop counts no CRITICAL finding and binds no lane. With no verdict on the
  head, the lane's unbound reason is `main-review-stop:<reason>` instead of
  `lane-source-changed`, so the gate report names why. It stays the same MED
  `evidence-unbound:<lane>` lane cause, with no new person hold. Any other title that does not
  read still counts one CRITICAL.
- The merge job reads less for a pull request that changes a lane source. It lists only the
  security lane's pull_request runs, because the code lane binds there on a main-run review
  alone, and reads the code lane's `pr-review-main` check runs on the head only. The security
  lane still reads every head of the pull request, so a CRITICAL finding on any head still
  carries.
