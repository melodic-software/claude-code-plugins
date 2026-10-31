---
bump: minor
---

### Added

- `scripts/repo-visibility.mjs` reports who can read a directory's repository, or a named GitHub repository: `public`, `private` or `internal` as GitHub reports it, `local` with no `.git` in the directory or any ancestor or with no remote, and `unknown` when git fails where a `.git` exists or a remote URL's visibility cannot be read, which callers treat as public. A directory reads `private` or `internal` only when every fetch and push URL of every remote does; any public URL makes it `public`. With `--commit <sha>`, a public directory reads `public` only when a public remote's tracking ref holds that commit. A directory that does not exist yet is judged by the repository it would land in.
- `/knowledge:absorb-upstream` reads a local checkout of a GitHub repository, pinned to its HEAD commit and read through git, so a private repository is absorbed from its checkout. The hardened clone stays public-only.

### Changed

- `/knowledge:absorb-upstream` checks the source and destination visibility before reading the source, a local checkout at its pinned commit, and writes no record of a source not proven public (`private`, `internal`, `unknown`, or `local` with no remote) in a public or unknown destination: it tells the person to rerun with `--out` into a private checkout's `docs/upstream`, or from that checkout, where the full record is written. An absolute `--out` is valid when its directory reads `private`, `internal` or `local`. Its team-layer root comes from `scripts/work-root.mjs` instead of `CLAUDE_PROJECT_DIR`.
- `/knowledge:course-digest` writes nothing, the `.work/` checklist included, unless its work root is in a private or internal repository or one with no remote. On a public or unreadable one it stops and names `library_dir` pointed at a private corpus checkout, since course material is paid content kept for personal use.
- The Dometrain adapter notes and the adapter discovery checklist describe page reads as accessibility snapshots in the picked browser tool, not Claude in Chrome's tool vocabulary.

### Security

- The hardened clone drops git config passed through the environment (`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`, `GIT_CONFIG_VALUE_<n>`) and points `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` at an empty file with `GIT_CONFIG_NOSYSTEM=1`, so an inherited `url.<x>.insteadOf` no longer redirects it.
- `scripts/repo-visibility.mjs` runs git with `-C`, without any inherited `GIT_*` variable, and with global and system config at the null device, so a caller's `GIT_DIR` or `insteadOf` rule cannot make a public repository read as private.
