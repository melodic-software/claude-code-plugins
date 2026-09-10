# Application portfolio

Generated on 2026-09-10 from an explicit repository list (`--repos`). Last
touched is the local HEAD of each checkout; nothing was fetched, so a stale
checkout reports a stale date. Every value comes from the file the
`portfolio-facts.sh` probe named; `unknown` means no probe could derive it.

`Runtime` and `Dependencies` are runtime scope, what the repository runs on.
`Tooling` is development scope, what it is built with: npm `devDependencies`,
CI requirement pins, anything under a dot-directory. This repository is shell
and markdown that lints with Node and Python tooling, which is why it has no
runtime dependencies at all.

| Repository | Owner | Target framework | Runtime | Dependencies | Tooling | Last touched (local HEAD) |
|---|---|---|---|---|---|---|
| claude-code-plugins | melodic-software | unknown | shell | (none) | node, python | 2026-09-10T16:50:21+00:00 |

Development-scope dependencies, truncated to ten: `@anthropic-ai/claude-code`,
`@biomejs/biome`, `htmlhint`, `iniconfig`, `markdownlint-cli2`, `packaging`,
`pluggy`, `pygments`, `pytest`, `pyyaml` (+10).

## Evidence

| Fact | Source |
|---|---|
| Owner | origin remote URL (no CODEOWNERS default rule) |
| Runtime | shell: `lib/hook-utils.sh` |
| Tooling | node: `package.json` (development scope); python: `.github/requirements-ci.txt` (development scope) |
| Target framework | no framework declaration for runtime shell |
| Dependencies | no runtime-scope dependency manifest |
| Development dependencies | `package.json` (devDependencies), `.github/requirements-ci.txt` |
| Last touched | `git log -1 --format=%cI` (local HEAD) |
