---
bump: minor
---

### Added

- `merge.verify-capture.proxy`: the key proxy the capture's driven Claude Code reaches the API through, with its token cap, model, `max_tokens`, body, beta and block allowlists, the driven session's models, and the Claude Code version the capture installs, which must equal `package-lock.json`'s pin.
- `pr-verify-capture`'s `capture` job starts the key proxy as its own OS user with the key on stdin before isolating the runner, then a sibling sandbox with no network and no secret, whose reach probe must also miss a sentinel credential planted outside it, and runs the driver's launch, ready and log there through the launch broker, so the pull request's plugin code runs with a dummy key. The sandbox writes only the run directory (the workspace, the head and main's checkout are read-only), sees an empty `/run` but for the proxy's socket directory, and can make no user namespace and hold no capability; its check fails the job unless those hold, no name resolves, and the proxy's is the only unix socket that answers. The probe also reads through links to `/proc/self/environ` and its fence file, and holds the driver's Write and Grep: a Write through a link to `~/.claude` and a Grep through the environ link must be refused too. The sandbox and the proxy are stopped whenever they started, the collect step copies nothing unless the sandbox stopped, and the run directory loses its top-level dot entries once it has. The proxy limits per job the requests that reach its count_tokens preflight (`max-preflight-requests`). `merge.verify-capture.app` stays unset until a runner probe passes.

### Changed

- `capture-subscription` reads no secret and runs no model: after the capture job's gates it uploads a capture recorded `blocked`, because a subscription token cannot go behind the key proxy.
- The capture's collect step copies no symlink and drops anything but regular files and directories before the upload.

### Removed

- The `capture-fallback` job, whose fallback token is a subscription token too.
