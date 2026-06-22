# Migration playbook

How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a
time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,
vet it against best practices, then publish.

All schema and behavior claims below were verified against the official docs on 2026-06-22. Re-verify
fresh before acting — see `CLAUDE.md` "Fresh-docs mandate".

## Intent

The point of moving a skill/hook out of a private repo and into a plugin is **reuse and developer
experience**: it should drop into any repository and work, and a consumer should be able to customize
behavior without filing an issue or editing the plugin. If a consumer needs to change a workflow, add an
action, or adapt to their repo, that is an **extensibility point** the plugin must expose by design.

## Design charter

Every plugin is designed to these principles (named here as the bar; apply, don't recite):

- Low coupling, high cohesion
- Vertical slice architecture
- SOLID
- Clean code
- DRY / single source of truth / no duplication

Concretely for plugins: a plugin owns one cohesive capability, depends on nothing repo-specific, and
exposes its variability through declared configuration rather than internal forks.

## Extensibility model — what works today

These are the proven, documented mechanisms for consumer customization that do not confuse the agent.
Prefer them in this order; the earlier ones are simplest and least surprising.

| Mechanism | What it does | Use for |
|---|---|---|
| Consumer `CLAUDE.md` / `.claude/rules` | The skill reads the consuming project's own context and rules | Project-specific conventions, naming, policies — the default extension surface |
| `${CLAUDE_PROJECT_DIR}` | Path to the consumer's project root, substituted in hook/MCP/monitor commands and exported to subprocesses | Referencing project-local scripts/config |
| `userConfig` → `${user_config.KEY}` | Values Claude Code prompts for at enable time (typed: string/number/boolean, optional sensitive). Also exported as `CLAUDE_PLUGIN_OPTION_<KEY>`. Non-sensitive stored in `settings.json` `pluginConfigs`; sensitive in keychain | Endpoints, toggles, tokens — consumer config without editing the plugin |
| `${CLAUDE_PLUGIN_ROOT}` | Path to the plugin's own installed directory | Referencing bundled scripts/assets (mandatory under cache isolation) |
| `${CLAUDE_PLUGIN_DATA}` | Persistent per-plugin directory that survives updates (`~/.claude/plugins/data/<id>/`) | Installed deps, caches, generated state |
| `hooks/hooks.json` | Event handlers the plugin ships | Behavior consumers opt into by enabling the plugin |

Design a skill so its variable parts route through the table above. "If you need to customize X, set
`userConfig` Y / add it to your project rules" — never "open an issue" or "fork the skill".

## Plugin-form caveats (works in-repo, breaks as a plugin)

Catalog these per migration; they are the usual failures when an in-repo skill becomes a plugin.

- **Cache isolation.** Installed plugins are copied to `~/.claude/plugins/cache`. Any reference to files
  outside the plugin directory (`../../tools/...`, `.claude/rules/...`) breaks. Fix: bundle dependencies
  inside the plugin and reference them via `${CLAUDE_PLUGIN_ROOT}`; persist state via `${CLAUDE_PLUGIN_DATA}`.
- **Namespacing.** An in-repo `/foo` becomes `/melodic-software:foo` (plugin-namespaced). Internal
  cross-references to the bare name break — update them.
- **Agent shadowing.** Project/user `.claude/agents/` override same-named plugin agents. A leftover
  in-repo copy masks the plugin version until removed from the source repo.
- **Headless registration.** `extraKnownMarketplaces` auto-registration requires the interactive trust
  dialog; CI/headless/cloud must run `claude plugin marketplace add` explicitly or pre-seed via
  `CLAUDE_CODE_PLUGIN_SEED_DIR`.

## Per-plugin migration gate

For each skill/hook/agent being migrated:

1. **Research fresh.** WebFetch the official docs for every component involved (see `CLAUDE.md`).
2. **Scope one capability.** One cohesive plugin; no grab-bags.
3. **De-couple from the source repo.** Remove hardcoded paths/names; route project-specifics to the
   consumer's context.
4. **Bundle + isolate.** Move required assets inside the plugin; reference via `${CLAUDE_PLUGIN_ROOT}`.
5. **Expose extensibility.** Declare `userConfig` for consumer choices; document each option.
6. **Strip PII / secrets.** Hard gate — before the first commit.
7. **Idempotent, modular, extensible.** Re-running is safe; pieces compose; variability is declared.
8. **Validate.** `claude plugin validate`; test with `--plugin-dir` in a clean repo that is NOT the
   source repo (proves repo-agnosticism).
9. **Version.** Set an explicit semver `version` in `plugin.json`.
10. **Publish.** Add the entry to `.claude-plugin/marketplace.json` and document it in the README.

## What to wait on / avoid for now

- Don't pre-build cross-plugin `dependencies` graphs until two plugins genuinely share a need.
- Don't abstract a shared library before a second consumer exists (Rule of Three).
- Don't rely on any mechanism not confirmed from current docs this session — if a customization need has
  no proven native path yet, record it here as a gap and keep the workaround in the consumer's repo until
  the native mechanism is verified.
