---
bump: patch
---

### Changed

- `babysit_verify_evidence.py evidence` takes what its caller already holds before reading GitHub: the config files at the base commit from the checkout `BABYSIT_CONFIG_CHECKOUT` names when its HEAD is that commit, the default branch from `BABYSIT_DEFAULT_BRANCH` for the run's own repository, and the pull request record from the file `BABYSIT_VERIFY_PULL` names when it is the same repository, number and head. The default branch's tip is read once per run. Anything else reads the API as before. ci-status's merge-queue step passes all three, so a lanes App pull request's verdict read makes about six fewer `GITHUB_TOKEN` requests.
