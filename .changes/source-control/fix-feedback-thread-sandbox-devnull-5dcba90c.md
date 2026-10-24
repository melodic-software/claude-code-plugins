---
bump: patch
---

### Fixed

- `feedback-thread.sh record` no longer refuses a VALID reply because the lane's sandbox masks a dotfile in the checkout (such as `.bash_profile`) with `/dev/null`. It skips a character device that is not a symlink, as `check-affected.sh` does. An untracked symlink to `/dev/null` is still refused. This was why address-feedback stopped with `feedback-invalid` or `feedback-incomplete` on lane PRs whose findings it had fixed.
