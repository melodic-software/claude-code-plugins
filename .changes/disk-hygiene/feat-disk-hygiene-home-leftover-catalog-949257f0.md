---
bump: minor
---

### Added

- Baseline hints for the home-root leftovers a manual WSL2 cleanup removed: Claude Code sandbox 0-byte placeholders at write-denied names (shell startup and git files, package-manager files, `.env*`, an empty `node_modules` tree; Linux and WSL2), `.claude.json.pre-onboarding.bak`, the pytest, Ruff, Playwright CLI, Storybook, CUDA (`~/.nv` and `%APPDATA%\NVIDIA\ComputeCache`), `dotnet new`, Semgrep, n, legacy pip and Biome folders, the mcp-remote token store, the Ubuntu MOTD stamp and Landscape log, and the evals plugin's legacy docker link lock. Each names its owner and native command; `reference/home-leftover-hints.md` points at each owner's source.
- A hint may set `requires` (`zero_bytes`, `absent_siblings`, `absent_children`, `unreferenced`), each failing closed. A hint whose condition fails is dropped and the entry records why in `unmet_hint_conditions`, so a non-empty `.npmrc`, a project `.storybook`, a `.semgrep` holding its API token or an `.mcp-auth` that a home MCP config still names stays out. Checking a condition lists no directory.
- Owner-registry entries for the evals plugin's `~/.ev` run roots (`prune-run-roots.py`) and its docker link swap manifest (`docker-links.py restore`).
