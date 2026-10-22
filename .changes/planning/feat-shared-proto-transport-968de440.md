---
bump: minor
---

### Added

- A live prototype the owner approves in a shared interview now runs: its own quick tunnel (a trycloudflare.com host, never the session's) to a copy of its build folder that a new static server (`liveserve.py`, 127.0.0.1, GET and HEAD only, no listing or dotfiles, a strict CSP) serves, or to a port the owner runs and attested. A tunnel or server that exits is restarted with a new address and no new Approve, and the entry ends after 5 failed restarts. `share.sh live-stop <id>` ends one, `share.sh stop` ends every one, and `status` lists them. ADR 0083.

### Security

- A live target is refused when it is the session's own guest or control port or answers the session-bridge ping as a control listener does, and a port entry ends once nothing listens on it, so a later server there never inherits its address. `add-live` and the start refuse a build folder holding a link, a hard link, a hidden name or a special file, or over 2000 files or 50 MB. A live link's origin must be a quick tunnel's. The static server sends `form-action 'self'` in its CSP and `Cross-Origin-Opener-Policy: same-origin`, and closes a connection that sent a body. A server the owner runs on a port is never stopped, and `share.sh` says it keeps running.
- A session holding a live entry ended as `failed` (the new reason) does not load in an earlier build.
