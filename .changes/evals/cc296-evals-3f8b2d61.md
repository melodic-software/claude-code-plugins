---
bump: patch
---

### Fixed

- **`plugin-eval` preflight no longer blocks Macs over Docker Desktop's own links.** On macOS with Claude Code 2.1.293 or later, links under `~/.docker/bin` no longer set `sandbox_backend: not-ready`, following the 2.1.293 changelog entry. Links in a `$DOCKER_CONFIG` store elsewhere, and other links, such as the ones Docker Desktop's WSL integration creates, still block a `Bash`-granting suite. The Docker fact row no longer quotes the old refusal text; it points at the changelog entry and records that the plugin-evals and sandboxing pages do not mention this check.
- **`plugin-eval` preflight checks git before any spend.** Preflight now reads `git --version` and reports it beside `floor_met`; a git older than the CLI's git floor sets `floor_met: false`, so a too-old git is caught before any spend. The floor is read from the plugin-evals requirements section rather than stated in the skill.
- **`/evals:validate` no longer treats `TaskOutput` as a no-grant tool, and accepts `AskUserQuestion`.** Claude Code removed `TaskOutput` in 2.1.277, and the plugin-evals page lists `AskUserQuestion` among the tools a case may use without a grant. The validator's read-only set, and the lists in the `plugin-eval` skill and its case-authoring reference, now match that page.
