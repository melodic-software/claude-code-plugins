---
bump: patch
---

### Fixed

- pr-verify no longer judges a `pr-require-checks` run that started while the pull request was a draft. A pull request opened as a draft and marked ready seconds later gets two runs at one head. Before, pr-verify judged the draft run, whose suites all skipped, uploaded a FAIL for "no tests ran", and then skipped the ready run as already judged. pr-verify no longer treats a FAIL judged from such a run as judging the head, so the ready run's judgment goes ahead, and the pr-merge lane's verdict gate no longer counts that FAIL either.
