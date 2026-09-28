# Go LSP control case

Short park for
[#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539).
The cluster decision lives in
[`ide-lsp-marketplace-ownership.md`](ide-lsp-marketplace-ownership.md).

## Decision

**Park. Do not own.** This marketplace does not ship a Go language-server
plugin. `gopls-lsp@claude-plugins-official` plus a native `gopls` on PATH
stay the provisioned path.

**Claim:** Go LSP stays a host control case, not a marketplace plugin;
decline marketplace ownership with #3536 until a maintainer funds an owned
server.
**Basis:** #3539 (`needs-human`, `priority: low`, child of #3535). #3535
rewrite (2026-09-01): `gopls.exe` native, stable, works untouched. Official
plugin declares `command: gopls`. No Go LSP skill under `plugins/`.
Cluster ledger `docs/out-of-scope/ide-lsp-marketplace-ownership.md`.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds marketplace ownership of gopls, or asks this
repo to record a fresh attended-desktop yes/no per platform.

## Prior requests

- #3539 (2026-09-28): Go LSP control case; Option A.
