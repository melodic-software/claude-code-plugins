---
bump: patch
---

### Security

- The lanes telemetry upsert now accepts a `--body-dir` only when it is this plugin's data dir (its last segment names harness-ops) and never `/`, the home dir or an ancestor of it, so a caller-chosen `--body-dir ~` no longer contains anything. The body path is canonicalized with `realpath`, opened once and re-checked through `/proc` on Linux.
- The leak scan also withholds a body naming a home path or a private or fleet hostname, and recognizes npm, Google API, Pulumi and Azure storage keys, URL credentials, JWTs and Docker registry auth.
