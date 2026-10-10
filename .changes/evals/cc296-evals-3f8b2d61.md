---
bump: patch
---

### Fixed

- **`plugin-eval` preflight no longer blocks Macs over Docker Desktop's own links.** On macOS with Claude Code 2.1.293 or later, links under the Docker credential store's `bin/` directory no longer set `sandbox_backend: not-ready`, matching the CLI, which stopped refusing those runs in that release. Other links, such as the ones Docker Desktop's WSL integration creates, still block a `Bash`-granting suite. The Docker fact row no longer quotes the old refusal text; it points at the changelog entry and records that the plugin-evals and sandboxing pages do not mention this check.
- **`plugin-eval` preflight checks git before any spend.** Preflight now reads `git --version` and reports it beside `floor_met`; a git older than the CLI's git floor sets `floor_met: false`, because the CLI stops the whole suite before any case on such a host. The floor is read from the plugin-evals requirements section rather than stated in the skill.
- **`/evals:validate` no longer treats `TaskOutput` as a no-grant tool, and accepts `AskUserQuestion`.** Claude Code removed `TaskOutput` in 2.1.277, and the plugin-evals page lists `AskUserQuestion` among the tools a case may use without a grant. The validator's read-only set, and the lists in the `plugin-eval` skill and its case-authoring reference, now match that page.
