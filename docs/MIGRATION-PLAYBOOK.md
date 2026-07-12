# Migration playbook

How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a
time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,
vet it against best practices, then publish.

All schema and behavior claims below were verified against the official docs on 2026-06-22 (the
"Reintegration" section's marketplace-settings claims — `extraKnownMarketplaces` / `enabledPlugins` in a
project's `settings.json` — on 2026-06-29, against the discover-plugins "Configure team marketplaces"
guide). Re-verify fresh before acting — see `CLAUDE.md` "Fresh-docs mandate".

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

## Organization — one plugin per cohesive concern

The charter's "one cohesive capability" is also the packaging boundary: **one plugin per cohesive
concern or capability**, grouped in the catalog through `category` / `tags` rather than by splitting.
A cohesive plugin MAY hold several units — a first-party plugin bundles many skills of one concern, a
hooks plugin bundles many hooks of one concern. One-unit-per-plugin is not the norm; do not ship a
plugin per hook.

- **Skills group by capability.** Distinct capabilities are distinct plugins; a single capability's
  always-together facets bundle (e.g. a prototyping capability's `logic` and `ui` skills ship together).
- **Hooks group by concern.** Per-hook selectivity comes from an env kill-switch
  (`HOOK_<PLUGIN>_ENABLED`), a `matcher`, or an `if` guard — author-managed control inside the bundle,
  the ecosystem norm.
- **Whole-product / vendor-brand bundles** driven by distribution are a separate, allowed shape.

**Why capability, not grab-bag.** Enabling and disabling happen at the plugin level, and the
`skillOverrides` setting explicitly *excludes* plugin skills (those are managed through `/plugin`), so
there is no clean per-skill à-la-carte toggle. Bundling several skills is therefore acceptable only
*within* one cohesive capability you would never split — it forbids lumping *distinct* capabilities into
a single plugin. Hooks differ: the env kill-switch gives clean per-hook control inside a bundle. The
discriminating axis is **silent-always-on** components (hooks — keep atomic, or toggle via env) versus
**opt-in-per-invocation** components (skills — group by capability).

## Naming

Name a plugin and its units by this precedence — an earlier rule wins on conflict:

1. **Semantic accuracy, zero confusion.** The capability is unambiguous from the name; qualify an
   overloaded generic term (a bare `audit` is collision bait).
2. **Official docs + ecosystem precedent.** kebab-case, no spaces; the namespace is the plugin's own
   `name` (not the marketplace name); mirror established Claude Code patterns.
3. **Explicit naming.** A domain-noun plugin name; no noise suffix (`-plugin` / `-tool` / `-helper`);
   no unit-type suffix (`-hook` / `-skill`) unless load-bearing; names track their semantic scope.

Applying that precedence:

- **Plugin `name` is a domain noun, kebab-case** (e.g. `feature-dev`, `pr-review-toolkit`).
- **Skill name follows its KIND.** An action / user-invoked skill reads as a **verb-phrase**
  (`create-plugin`, `review-pr`); a knowledge / model-invoked skill is a **noun-phrase**
  (`cqrs-implementation`, `agent-development`). The "reads-as-a-verb-phrase" heuristic scopes to action
  skills only — a `noun:noun` name is correct for a knowledge skill.
- **`/plugin:skill` doubling is idiomatic** (`/prototype:prototype`, first-party `/code-review:code-review`)
  — docs-blessed, not an anti-pattern. Do not contort a name solely to avoid the doubling.
- **Generic skill names are safe under namespacing** (`help`, `list`, `configure`) — the overloaded-term
  caution governs plugin *identity*, not a namespaced skill leaf.
- **Tool-scope shows up as brand-in-name, not a structural split.** A branded name signals a tool-scoped
  plugin; a plain domain-noun signals a tool-agnostic one. No marketplace separates plugins by tool-scope
  — do not formalize such a split.

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

## Persistence, configuration & external integration

A skill is a markdown prompt (plus optional scripts), not a compiled runtime — so ports / adapters /
CQS layering is a **category error** here. Expose variability the way real plugins and the extensibility
model above already prescribe:

- **Persistence.** Write generated state and caches to `${CLAUDE_PLUGIN_DATA}` (the per-plugin directory
  that survives updates — see the extensibility table). Choose JSON / JSONL / SQLite per need.
- **Configurable location or behavior.** One `userConfig` knob (`${user_config.KEY}`, per the
  extensibility table) with a sane default — never a consumer-bound interface. Add a knob **only** where
  a real repo-specific behavior surfaces (Rule of Three; no speculative knobs — see the design charter).
- **External systems (issue trackers and the like).** Use backend-neutral **"work item"** vocabulary
  plus either a direct CLI call (e.g. `gh`) or dependence on an **MCP server** — swapping the backend
  means swapping the MCP server, not introducing a pluggable-tracker abstraction (every official
  integration is a bare MCP wrapper).
- **Cross-skill references.** Hand off through the slash invocation when the target skill is present;
  degrade gracefully to prose when it is absent.

This is deliberately **not** ports / adapters: there is no runtime seam to invert in a prompt medium, so
a declared config surface, not an abstraction layer, is the extension point.

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

## Migration order, PRs & parallelization

**Seams first** (Fowler's Branch by Abstraction). Establish the shared foundations — the conventions in
this playbook, the shared `lib/` source of truth (see "Shared code across plugins"), and the
persistence/config pattern above — in one small sequential PR *before* fanning out. Everything downstream
builds on those seams.

**Per-unit atomic PRs, authored in parallel.** One PR per cohesive migratable unit: small changesets
review faster and more thoroughly, and the per-unit acceptance gate makes each one atomic and
rollback-safe. Parallelize with one worktree (or worker) per unit — **conflict-free by design**, because
each plugin is an isolated `plugins/<name>/` directory, so N units become N concurrent PRs with no merge
conflicts. Group units into one PR only when they are hard-coupled, or when the change is a single
mechanical bulk edit.

**Expect one shared-file conflict, resolved at merge.** The two files parallel PRs all touch are the
catalog manifest (`.claude-plugin/marketplace.json`) and the README catalog table. Those conflicts are
expected — resolve them by **serializing the final merges**, not by serializing authorship.

**Gate every unit before publish.** Each unit clears its parity / acceptance gate — the per-plugin
migration gate and the plugin-acceptance security review below — before it ships.

**Sequence heuristic.** Order lowest-coupling units first (clean, self-contained units with graceful
degradation). Defer risky units (hard external dependencies, no graceful degradation) and any
license-gated units to per-item triage rather than a blanket hold. The ordering is reversible.

## Plugin-acceptance security review

A plugin runs code on the consumer's machine and can wire Claude to external systems. **Every plugin accepted
here — new, or a version bump that adds a trust surface — passes this review** in addition to the migration
gate above (whose step 6 gates PII/secrets). **Deny by default** any surface below that can't be justified.
Facts verified against the plugins/MCP reference 2026-07-09; re-verify per the `CLAUDE.md` fresh-docs mandate.

1. **Code execution — hooks & scripts.** A hook command runs shell on the consumer's machine on matched events,
   with `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`, `${user_config.*}`, and any
   `${ENV_VAR}` interpolated in. Check: which binaries it spawns; whether it mutates files in place and is
   **advisory** (exits 0, never blocks) vs gating; no `eval` / `curl … | sh` / outbound network; untrusted
   input (file contents, tool args, PR/issue text) never flows unquoted into a shell; a kill switch
   (`HOOK_<PLUGIN>_ENABLED`) exists.
2. **Remote MCP servers — `.mcp.json` / inline in `plugin.json`.** **Net-new surface** — no current plugin
   ships one. A plugin's MCP server **starts automatically when the plugin is enabled** (subject to per-server
   approval). Check: the server host/URL and who runs it (first-party vs a third party you're delegating trust
   to); transport (local `stdio` vs remote `http`/`sse`/`ws`); **what data leaves the machine** — a remote
   server receives whatever Claude sends and, if it returns external content, is a prompt-injection vector
   (official guidance: "Verify you trust each server before connecting it"); auth shape (header/Bearer/OAuth)
   with any token sourced from `userConfig` `sensitive` or an env var, **never hardcoded**; a stated reason the
   capability can't be a local `stdio` server. **Do not accept a third-party remote MCP server** without an
   explicit recorded trust decision naming the vendor, the data egress, and the token scope.
3. **Consumer config — `userConfig`.** Any credential/token option MUST set `"sensitive": true` — that masks
   input and stores the value in the system keychain (or `~/.claude/.credentials.json`), **not** `settings.json`.
   Non-sensitive values land in `settings.json` under `pluginConfigs[<id>].options` and are readable — never put
   a secret there. Endpoints and toggles are fine as non-sensitive. Every option is documented.
4. **Cache isolation — no reach-outs.** References only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`;
   persists state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs, no absolute paths, no reading consumer files
   outside `${CLAUDE_PROJECT_DIR}`.
5. **Data egress — telemetry & network.** Any telemetry (e.g. `HOOK_TELEMETRY_SINK`) is opt-in (unset = exact
   no-op), never writes to the hook's stdout/`additionalContext` channel, and emits only the declared envelope —
   no payload beyond the documented schema. Name any other outbound network call and justify it.
6. **Provenance & third-party trust.** Verify authorship (does `plugin.json` `author` match who actually
   submitted the PR?), license, and that the source is what it claims. A plugin that promotes or wires a
   third-party SaaS is a trust delegation — record accept/deny with rationale. Note the platform already blocks
   plugin-shipped **agents** from declaring `hooks` / `mcpServers` / `permissionMode` "for security reasons" —
   don't design around that.

Record accept/deny + rationale for any plugin touching surfaces 2, 5, or 6; a later version bump that
introduces a new surface re-triggers this review.

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
- **Project conventions** → for a hook plugin, the consumer's own tool config files that the hook already
  reads (`biome.json`, `.shellcheckrc`, `.editorconfig`, …) — that is where these plugins pick up project
  conventions, **not** `CLAUDE.md`. (`CLAUDE.md` / `.claude/rules` reach only a plugin's *skill/agent*
  components, which run in Claude's model context; hook scripts see only env vars and file-based config.)
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
   `enabledPlugins` (project `settings.json`, so clones inherit it on trust — the interactive trust prompt
   both registers and installs the enabled plugin). Headless/CI has no such prompt, and registering a
   marketplace does not install its plugins, so do both explicitly: `claude plugin marketplace add <repo>`
   then `claude plugin install <plugin>@<marketplace> --scope project` — otherwise the marketplace is known
   but the plugin is absent, and step 3's verify edit would run with no plugin hook.
2. Rewire the kill-switch env var to the plugin's name; keep the `HOOK_TELEMETRY_SINK` wiring and the
   sink script (the bridge), adapting the sink for any observability-contract divergence.
3. **Verify before retiring** the old hook (blue-green — keep it recoverable, but never run both on the
   same edit). Matching `PostToolUse` hooks run concurrently, so leaving both registered would race two
   formatters on the just-edited file (last-writer-wins clobbering, plus doubled telemetry and context) —
   idempotence only makes *serial* re-runs converge, not concurrent writes safe. So **exactly one is
   active at a time**: disable the in-repo hook by setting its kill-switch env var to `"false"` (or, if it
   has none, removing its registration entry — `settings.json` is JSON, so toggling the value or removing
   the entry is the edit, never a `//` comment). With the old hook off and the plugin enabled, edit a
   governed file and confirm: the plugin formats/lints and surfaces findings, the telemetry sink receives
   the expected envelope (so a broken remap is caught now, not when observability is next needed), and the
   consumer's hard gate (commit hooks, CI) is untouched — those are independent of the edit-time hook. If
   verification fails, **disable the plugin first, then re-enable the old hook** (always flip one off as you
   turn the other on) and debug before retrying — so the two never run together and there is never a
   no-hook gap.
4. Only once verified, remove the in-repo hook's `settings.json` registration and delete the hook script
   **and its test**.

**Bootstrap-direction caveat.** While a repo is still the harvest *source* (its hooks are mid-migration
out), reintegrating one plugin makes it consume one plugin while still running the rest in-repo — a mixed
state. Flip a repo from source to consumer deliberately, not incidentally, and ideally once the repo's
ported plugins can move together.

## Shared code across plugins — decision record (2026-07-04)

Decided when four plugins carried byte-identical `hooks/hook-utils.sh` copies — the Rule-of-Three
threshold below, exceeded. The mechanism is **single source of truth at authoring time, plain copies
at runtime**:

- `lib/hook-utils.sh` is the only copy to edit. `scripts/sync-hook-utils.sh` propagates it into every
  carrying plugin; a plugin opts in by committing an initial `hooks/hook-utils.sh` copy.
- CI (`hook-utils-sync` lane) fails a PR when any plugin copy drifts from the source, and when the lib
  changed but a carrying plugin's manifest version did not — the plugin `version` is the update cache
  key, so an unbumped plugin never delivers the change to consumers.
- Runtime is untouched: each installed plugin stays self-contained under cache isolation, with no
  cross-plugin coupling and no change to the one-plugin install UX.

Alternatives weighed (docs verified 2026-07-03):

- **Dependency plugin carrying the lib — rejected as not viable.** A hook sees only its own
  `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; no variable or documented mechanism exposes a
  *dependency's* install path, and cache directories are per-version (with a commit-SHA suffix for
  tag-resolved dependencies), so computing the path is unsupported by design (plugins-reference
  "Plugin caching and file resolution"; plugin-dependencies guide). Revisit iff Claude Code ships a
  documented dependency-path variable — that would also allow sharing the lib beyond this marketplace.
- **Marketplace-internal symlinks — deferred.** Documented mechanism: a symlink from a plugin to a
  file elsewhere in the same marketplace is dereferenced at install, copying the target's content into
  the cache — native SSOT with no sync script (plugins-reference "Share files within a marketplace
  with symlinks"). Deferred because such symlinks are *skipped* for `--plugin-dir` / local-path
  installs (breaking the local development loop above) and are fragile to author and clone on Windows,
  the primary environment on both the authoring and consuming side. Revisit if the dev loop stops
  depending on `--plugin-dir` or the Windows constraint lifts.
- **Copies with only a byte-identity CI gate — subsumed.** The chosen shape is that gate plus a
  canonical source and one sync script, removing the edit-×N-by-hand step at negligible cost.

The lib's unit tests live beside the source as one consolidated suite (`lib/hook-utils.test.sh`,
run by the same CI lane) rather than as per-plugin copies — byte-identity of the copies means
testing the source covers them. Plugins keep only their own black-box hook contract tests.

## What to wait on / avoid for now

- Don't pre-build cross-plugin `dependencies` graphs until two plugins genuinely share a need.
- Don't abstract a shared library before a second consumer exists (Rule of Three); at the threshold,
  the shared-code decision record above is the settled shape — extend it rather than re-deciding.
- Don't rely on any mechanism not confirmed from current docs this session — if a customization need has
  no proven native path yet, record it here as a gap and keep the workaround in the consumer's repo until
  the native mechanism is verified.

## Deferred surfaces — decision record (2026-07-12)

Three general-purpose surfaces in the harvest-source repo (`melodic-software/medley`) are held out of this
wave's plugin migration deliberately, each with an explicit revisit trigger — recorded here so the deferral
is a decision, not a silent omission. The medley side carries a thin pointer back to this record at each
surface (the workflow-engine authoring rule, the `onboard` skill, and the `gh-bot.sh` bot-identity
convention), so a contributor who touches a deferred surface finds the trigger without leaving that repo.

- **Workflow engines** (`code-review.js`, `codebase-review.js`, `deep-research.js`,
  `research-deep-fanout.js`, `skills-audit.js`, `skills-evals.js`, `skills-remediate.js`): not a plugin
  component per current docs — the `Workflow` tool loads an engine script from disk and a plugin manifest
  has no native slot to ship one, so these may be removed entirely rather than migrated. **Revisit
  trigger:** the engines survive the next usage review (still earning their keep) → package as a plugin
  skill that dispatches the engine through the `Workflow` tool's `scriptPath`, resolved under
  `${CLAUDE_PLUGIN_ROOT}`; the smoke test for that path is specced in the extensibility-contract v2.1
  playbook amendment.
- **`onboard` skill:** repo-specific today — its phase gates encode this repo's exact runtime, linter, and
  tooling pins. **Revisit trigger:** a second repo needs environment-prerequisite auditing → extract a
  generic core through the extensibility-contract seams (the convention-resolution ladder infers or asks
  for the per-repo pins), leaving repo specifics in tracked config rather than baked into the skill.
- **`tools/github-auth` (`gh-bot.sh`):** hardcodes the org's bot App / installation identity. **Revisit
  trigger:** a second repo needs bot-actor GitHub operations → parameterize org / App / installation
  through the seams (`userConfig` scalars, `sensitive` for the key) instead of standing up a second
  hardcoded wrapper.
