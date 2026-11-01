---
bump: patch
---

### Security

- The babysit-loop telemetry upsert now accepts a `--body-dir` only when it is this plugin's data dir (its last segment names source-control) and never `/`, the home dir or an ancestor of it. The body path is canonicalized with `realpath`, opened once and re-checked through `/proc` on Linux.
- The leak scan also withholds a body naming a home path or a private or fleet hostname, and recognizes npm, Google API, Pulumi and Azure storage keys, URL credentials, JWTs and Docker registry auth.
- A symlinked or malformed stored lane instance is refused without echoing it. The skill gives the data dir as an absolute path, since its reference file reaches Bash unsubstituted.
