---
bump: none
---

Test only: `session-retention.test.sh` stops its archiver by pid instead of a host-wide `pkill -f 'sleep 30'`, which killed other suites' sleeps, and its archiver now really sleeps. The shipped hook is unchanged.
