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
| `userConfig` → `${user_config.KEY}` | Values Claude Code prompts for at enable time (typed: string/number/boolean/directory/file, optional sensitive). Also exported as `CLAUDE_PLUGIN_OPTION_<KEY>`. Non-sensitive stored in `settings.json` under `pluginConfigs[<id>].options`; sensitive in the system keychain | Endpoints, toggles, tokens — consumer config without editing the plugin |
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
- **Namespacing.** Components are namespaced by the plugin's own `name`, not the marketplace name —
  an in-repo `/foo` becomes `/<plugin-name>:foo`. Internal cross-references to the bare name break —
  update them.
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
10. **Publish.** Add the entry to `.claude-plugin/marketplace.json` — the plugin `source` is the
    `./`-prefixed relative path (e.g. `./plugins/<name>`). Bare names fail `claude plugin validate --strict`
    even with `metadata.pluginRoot` set, despite the marketplaces-doc example to the contrary (verified
    2026-06-23). Then run `claude plugin validate --strict <repo-root>` to validate the **catalog manifest
    itself** — a bad entry surfaces only there, not in per-plugin validation. Document the plugin in the README.

## Local development loop

For a plugin that already ships here, iterate against your local clone without re-publishing and
without changing any consumer's marketplace registration. `--plugin-dir` loads a plugin straight from
a directory; when its `name` matches an installed marketplace plugin, **the local copy takes
precedence for that session**, so you exercise working-tree edits against the installed copy without
uninstalling it (verified 2026-06-24).

```shell
# from this repo root — point at the plugin directory, not the marketplace root
claude --plugin-dir ./plugins/<name>
```

- **Edit, then `/reload-plugins`** to pick up changes without restarting — it reloads skills, agents,
  hooks, and plugin MCP/LSP servers, reading the files on disk, so no commit or reinstall is needed.
- **Session-scoped and non-destructive.** The override lasts only for that session and never edits a
  consumer's `extraKnownMarketplaces`; the published registration stays on its GitHub remote. The lone
  exception: `--plugin-dir` cannot override a plugin that *managed* settings force-enable or
  force-disable.
- **Trust.** A locally loaded plugin carries the same trust considerations as any source — only load
  directories you control.
- **Then ship.** Run `claude plugin validate` before opening a PR; after merge, consumers pull the
  change with `/plugin marketplace update melodic-software`, gated by the `version` bump in `plugin.json`.

## Reintegration — a consumer adopts the published plugin

The forward migration (above) ends at *publish*. The lifecycle closes when the source repo stops running
its in-repo copy and instead **consumes the published plugin** — one source of truth, and the repo
dogfoods the marketplace. Reintegration is a *consumer-side* change: adapt through the documented
extension points, never by teaching the plugin a consumer's specifics.

**The plugin is generic; the consumer's own seams restore its specifics.** Map each behavior the
in-repo hook had that the generalized plugin dropped to one of these, in order:

- **Kill switch / toggles** → the plugin's own env var, set in the consumer's `settings.json` `env`
  (the name changes from the in-repo `HOOK_<OLD>_ENABLED` to the plugin's `HOOK_<PLUGIN>_ENABLED`).
- **Project conventions** → the consumer's `CLAUDE.md` / `.claude/rules`, which the plugin already reads.
- **Telemetry / observability** → the consumer's own **telemetry sink**. This is the key seam: the
  plugin emits the generic telemetry envelope contract to `HOOK_TELEMETRY_SINK`, and the consumer's sink
  script translates that envelope into the consumer's local observability shape. A consumer whose prior
  hook emitted a different status or hook-identity (e.g. `status=error` on a surfaced violation, or a
  legacy hook name) restores that contract **in its own sink**, by remapping the plugin's native envelope
  (`status=ok` + populated `findings`) — not by changing the plugin. Before remapping, verify how the
  consumer's observability actually keys events (e.g. on `status` vs a derived `exit_code`/findings count),
  so the remap preserves the real contract rather than a guessed one.

If a genuine specific has **no** seam, that is a real plugin gap → add a declared extension
(`userConfig`, or a new env var consistent with the plugin's existing ones) — but only when it carries
real behavior, not cosmetic prose a consumer's `CLAUDE.md` already establishes. Resist adding config
surface to a published plugin for a single consumer's low-value nicety.

**Cutover checklist:**

1. Register the marketplace in the consumer's `extraKnownMarketplaces` and enable the plugin in
   `enabledPlugins` (project `settings.json`, so clones inherit). Headless/CI needs an explicit
   `claude plugin marketplace add` — the auto-registration trust dialog is interactive-only.
2. Rewire the kill-switch env var to the plugin's name; keep the `HOOK_TELEMETRY_SINK` wiring and the
   sink script (the bridge), adapting the sink for any observability-contract divergence.
3. Remove the in-repo hook's `settings.json` registration and delete the hook script **and its test**.
4. Verify the plugin hook fires (edit a governed file, confirm format/lint + surfaced findings), and that
   the consumer's hard gate (commit hooks, CI) is untouched — those are independent of the edit-time hook.

**Bootstrap-direction caveat.** While a repo is still the harvest *source* (its hooks are mid-migration
out), reintegrating one plugin makes it consume one plugin while still running the rest in-repo — a mixed
state. Flip a repo from source to consumer deliberately, not incidentally, and ideally once its ported
plugins can move together.

## What to wait on / avoid for now

- Don't pre-build cross-plugin `dependencies` graphs until two plugins genuinely share a need.
- Don't abstract a shared library before a second consumer exists (Rule of Three).
- Don't rely on any mechanism not confirmed from current docs this session — if a customization need has
  no proven native path yet, record it here as a gap and keep the workaround in the consumer's repo until
  the native mechanism is verified.
