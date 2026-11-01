---
bump: patch
---

### Security

- The babysit-loop telemetry upsert now accepts a `--body-dir` only when it is this plugin's data dir (its last segment names source-control) and never `/`, the home dir or an ancestor of it. The body path is canonicalized with `realpath`, opened once and re-checked through `/proc` on Linux.
- The leak scan also withholds a body naming a home path or a private or fleet hostname, and recognizes npm, Google API, Pulumi and Azure storage keys, URL credentials, JWTs, Docker registry auth, base64-encoded PEM blocks and netrc passwords.
- A symlinked or malformed stored lane instance is refused without echoing it. The skill gives the data dir as an absolute path, since its reference file reaches Bash unsubstituted.
- The data-dir name is checked again after `realpath`, so a symlink named for the plugin that points elsewhere is refused, and the home-dir check reads the account's passwd entry, so an overridden `HOME` cannot disable it. A machine path or hostname is reported as such, with no rotation advice, and a path under a GitHub-hosted runner's home dir is not withheld. URL credentials need a password of 6 or more characters that is not a placeholder (`$` and `*` allowed), and base64-encoded PEM blocks and netrc passwords are caught too.
- netrc passwords are caught in the `default` entry and on a `password` line of their own.
