---
bump: none
---

Test only: `session-retention.test.sh` exits from a SIGHUP trap, so a closed terminal no longer leaves its temp directory behind; the shipped hook is unchanged.
