# Application portfolio

Generated on 2026-09-11 from current repository plus reference graph. Remote facts: not used.

Last touched is the local HEAD of each checkout unless a remote fact says
otherwise, so a stale checkout reports a stale date. `unknown` means no probe
could derive the value.

`Runtime` and `Dependencies` are runtime scope, what the repository runs on.
`Tooling` and the development-scope dependencies below the table are what it
is built with.

| Repository | Owner | Target framework | Runtime | Dependencies | Tooling | Last touched |
|---|---|---|---|---|---|---|
| claude-code-plugins | melodic-software | unknown | shell | (none) | node, python | 2026-09-11T06:27:34+00:00 |

## Development-scope dependencies

Truncated to ten per repository; the record carries the full list.

- claude-code-plugins: `@anthropic-ai/claude-code`, `@biomejs/biome`, `htmlhint`, `iniconfig`, `markdownlint-cli2`, `packaging`, `pluggy`, `pygments`, `pytest`, `pyyaml` (+10)

## Evidence

| Repository | Fact | Source |
|---|---|---|
| claude-code-plugins | owner | origin remote URL |
| claude-code-plugins | runtime | shell: lib/hook-utils.sh |
| claude-code-plugins | tooling | node: package.json (development scope), python: .github/requirements-ci.txt (development scope) |
| claude-code-plugins | target_framework | no framework declaration for runtime shell |
| claude-code-plugins | dependencies | no runtime-scope dependency manifest |
| claude-code-plugins | dev_dependencies | package.json (devDependencies), .github/requirements-ci.txt (development scope) |
| claude-code-plugins | last_touched | git log -1 --format=%cI (local HEAD) |
