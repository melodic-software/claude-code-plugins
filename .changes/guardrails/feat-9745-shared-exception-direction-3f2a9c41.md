---
bump: minor
---

### Added

- `block-cross-domain`: a `shared_exceptions` entry is now `{"path": <dir>, "from": [<domain>], "to": <domain>}` and opens that directory of `to` to sessions in the `from` domains, one way. A command from a `from` domain is allowed when every other domain's path it names is inside the directory and its text holds no `..` (a glob, brace or expansion right after the directory's name denies it too); a session in `to`, or in a domain `from` does not list, is still denied. A `path` that is not a path of `to` on this host, or an entry left as a plain string, grants nothing and is named in a once-per-session notice, without making the map malformed.
- `/guardrails:setup apply identity-domains`: `--shared-exception` now takes `FROM[,FROM...]:TO=PATH` and refuses a `PATH` outside `TO`'s tree and owner directories, or a `FROM` that lists `TO`.
