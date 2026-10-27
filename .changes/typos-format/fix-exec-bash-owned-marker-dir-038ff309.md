---
bump: patch
---

### Security

- The `--skip-unless-marker` hook launcher no longer skips a monitor because of a launch-marker directory in the shared temp folder that another local user created, or a symlink in its place: off Windows that directory counts only when it is a real directory owned by the current user, as the disk-hygiene hook script already required.
