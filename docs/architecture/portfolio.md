# Application portfolio

Generated on 2026-09-08 from an explicit repository list (`--repos`). Last
touched is the local HEAD of each checkout; nothing was fetched, so a stale
checkout reports a stale date. Every value comes from the file the
`portfolio-facts.sh` probe named; `unknown` means no probe could derive it.

| Repository | Owner | Target framework | Runtime | Dependencies | Last touched (local HEAD) |
|---|---|---|---|---|---|
| claude-code-plugins | melodic-software | >=24 | node,python | iniconfig, packaging, pluggy, pygments, pytest, pyyaml, ruff, tree-sitter, tree-sitter-bash, tree-sitter-c-sharp (+6) | 2026-09-08T12:45:20-04:00 |

## Evidence

| Fact | Source |
|---|---|
| Owner | origin remote URL (no CODEOWNERS default rule) |
| Runtime | node: `package.json`; python: `.github/requirements-ci.txt` |
| Target framework | `package.json` (`engines.node`) |
| Dependencies | `package.json` (dependencies + peerDependencies), `.github/requirements-ci.txt` |
| Last touched | `git log -1 --format=%cI` (local HEAD) |
