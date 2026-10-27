---
bump: patch
---

### Fixed

- **`run-python-hook.sh` ignores a tmp launch-marker directory this user does not own.** With no plugin data root, the `--launch-marker` and `--skip-unless-marker` markers live under the shared `${TMPDIR:-/tmp}/disk-hygiene-<subdir>`, so another local user could pre-create that directory, or a symlink in its place, and plant or suppress a `.launched` marker; an empty planted directory reads as "no guard launched" and skips the guard-launch monitor. A tmp marker directory that is a symlink or that this user does not own is now neither read nor written by the launcher, the same check its no-interpreter notice already made, and the launcher creates its marker directories with mode 700. The node launcher's own pre-bash skip (`hooks/exec-bash.mjs`) does not check ownership yet.
