---
bump: minor
---

### Added

- Shared `resolve-convention-home.sh` synced: `--ref` (a 40-hex commit id or `origin/<name>`) reads the pointer and the home as committed, `-` reads the region from stdin, a `declined` line in the region exits 4 so the caller does not ask again, and a root that is `$HOME`, an ancestor of it or outside a git work tree exits 5 (not applicable).
- Shared `config-cascade.mjs` synced: `resolve()` takes a `floors` option (key path to `Floor direction`), and a personal `.local.yaml` value that loosens a floor key the team set is dropped with an error naming the layer, file and key. A `.local.md` H2 section replaces the team `.md` section with the same heading, returned as `sections`.

### Changed

- The config cascade has four layers (default, `userConfig`, team, personal): a file under `~/docs/conventions/` is no longer read. An invalid team or `userConfig` value falls to the default, never to a lower layer's value; an invalid personal value leaves the team value standing.
- With no `--root`, `resolve-convention-home.sh` reads the git toplevel of `CLAUDE_PROJECT_DIR` (else of the current directory): one home per git root.
- `detect.mjs --config` reads no team or overlay file when the repository declined a convention home or none applies (the project is `$HOME`, an ancestor of it, or outside git): the bundled defaults apply, and `home_skipped` says why.

### Fixed

- A `CLAUDE.md` symlinked to `AGENTS.md`, or the reverse, no longer prints a `duplicate:` notice.
- A convention home whose name starts with `..` (such as `..conf`) is no longer refused as outside the project.
