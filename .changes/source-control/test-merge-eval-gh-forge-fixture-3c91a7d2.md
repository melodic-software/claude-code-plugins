---
bump: patch
---

### Fixed

- The `pull-request-merge-holds-on-unclassified-ci` eval case now runs against the offline `gh` stand-in (`fixtures/gh-forge`) with an open PR 482 that carries one failing check, so a correct run reaches `gh pr checks` and the merge hold its graders check. `install.sh` takes `--open` and `--failing-check <name>`, and the stand-in serves `pr checks` and the status rollup from them.
