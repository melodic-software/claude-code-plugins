# Plugin philosophy

This is the durable design policy for plugins in this marketplace. The
[migration playbook](MIGRATION-PLAYBOOK.md) applies it to migration and release work; the
[plugin artifact protocol](PLUGIN-ARTIFACT-PROTOCOL.md) defines the shared artifact seam used by
lifecycle plugins.

## Design boundary

A plugin is a reusable, independently useful vertical slice of one cohesive capability. It must work
outside the repository and organization that produced it. Publisher metadata may identify its source;
runtime behavior must not depend on publisher names, organization-specific environment variables,
repository names, absolute machine paths, or an undocumented consumer layout. The artifact-agnostic
form of this doctrine — consumer-agnostic behavior, externalized consumer-varying configuration,
consumer tiers, explicit adoption — is owned by `melodic-software/standards`
`conventions/engineering/shareable-artifact-design.md`; this document specializes it for Claude Code
plugins and adds only what is plugin-specific.

Keep plugins horizontally decoupled:

- A plugin owns its skills, hooks, agents, scripts, dependencies, and state.
- It never imports files from a sibling plugin or discovers another plugin's installation directory.
- Cooperation uses a documented public seam: an artifact contract, an explicit invocation argument,
  or an optional namespaced skill invocation.
- Native manifest `dependencies` are reserved for hard requires — a plugin genuinely broken without
  its collaborator. Optional collaboration stays presence-gated with a documented fallback. The
  first versioned dependency brings the `{name}--v{version}` release-tag step
  (`claude plugin tag --push`) with it.
- Every plugin remains useful alone. If an optional collaborator is absent, use a documented fallback
  or report the missing optional capability clearly.
- Every cross-plugin reference is therefore either declared (the `dependencies` array above, which
  Claude Code installs automatically) or guarded behind an "if installed" check with the documented
  fallback. A bare unguarded cross-plugin reference is a defect.

This follows Claude Code's distinction between project-specific standalone configuration and plugins
intended for reusable, versioned distribution. Namespaced skill invocations are part of that isolation,
not an implementation detail.

## Naming

A skill name is an imperative verb phrase; the plugin namespace supplies the object
(`/machine-health:audit`, `/source-control:commit`). Names compose into instruction sentences —
"/discovery:explore the module, then /planning:interview me" — and one grammar keeps every name in
the marketplace predictable. This is a deliberate, documented deviation from the official authoring
guidance's gerund preference; that guidance sanctions imperative alternatives and treats
collection-wide consistency as a requirement, which this section provides.

Verb meanings are fixed:

| Verb | Contract |
|---|---|
| `audit`, `scan` | Read-only findings report. Mutation only behind an explicit user override such as an autofix argument, never on bare invocation; safety qualifiers may narrow what an override touches. |
| `check` | Deterministic pass/fail gate. |
| `clean`, `tidy`, `fix` | Mutates the target. |
| `setup` | Configures the plugin for a consumer, per the setup section below. |
| `update` | Refreshes vendored upstream material. |

When a bare verb would collide with or under-specify against a sibling in the same namespace, a
topic qualifier follows the verb with a hyphen (`audit-noise` beside `audit-encapsulation`,
`scan-todos` under `work-items`); the verb keeps its fixed meaning from the table.

Nouns are reserved for knowledge routers (`principles`, `methodology`) and lifecycle-object routers
(`worktree`, `pull-request`). Five further documented exceptions: a single-skill vendor-CLI wrapper
repeats its tool name (`firecrawl:firecrawl`); a `-deep` suffix marks the heavier
isolated-execution tier of a sibling skill (`research`/`research-deep`); a knowledge router named by
its method's own literature term keeps that term when renaming would destroy recognized craft
vocabulary (`songwriting:object-writing`, `meter-prosody`, `song-form` — Pattison's terms); a
playbook router named by its source keeps the source's own identifier, because provenance is the
content's identity (`playbooks:boris`, `playbooks:fable-5` — one scheme, person or model alike);
and an object-pronoun qualifier is kept when the skill's defining boundary IS that the object under
test is the user themself (`education:quiz-me` — the `-me` distinguishes quizzing the human on
completed work from teach's in-workspace content quizzing, where a bare `quiz` would under-specify
the object the grammar normally delegates to the namespace).
Every exception is an entry on this list, decided per name — a name class is never
blanket-sanctioned.

The frontmatter `name` always matches the skill directory name, in the character set the Agent
Skills specification allows. Never degrade a name to dodge a built-in command: plugin skills are
namespaced and cannot collide with other levels. When a name matches a built-in, the bare token
still belongs to the built-in; the namespaced form is the plugin skill's only command.

That guarantee is about **resolution**, and it does not extend to **display**. The slash-command
picker lists a skill by its short name and registers the namespaced form as a hidden alias — so
`/planning:` still filters to that plugin's skills, but `planning:plan` is not what the row is
labelled. Origin travels in the description instead: a plugin skill renders as
`(<plugin-name>) <description>`, a personal skill as `<description> (user)`, a project skill as
`(project)` or `(project, gitignored)` depending on whether it came from shared or local settings,
and a built-in, bundled, or MCP entry carries no marker at all. So sibling short names
across different plugins are unambiguous to *invoke* and identical to *read* — a shared leaf name
costs legibility in the description column, never correctness. Weigh it there; never rename to buy
display uniqueness, and keep the description's first clause carrying the distinguishing object,
since that column is what a reader actually scans.

## Native-first

Prefer a built-in native mechanism — `userConfig`, a native component type, a native lifecycle
event — over any custom extensibility point. Build custom only on genuine misfit, and document the
misfit where the custom mechanism lives.

Built-in-first is a gate on every customization surface, not a preference. Before building
any custom config surface — a YAML concern file, a bespoke seam — first verify against the *current*
official Claude Code plugin documentation that no native mechanism (`userConfig`, a built-in
per-repo config surface) can host the need; the platform moves, so re-fetch
the documentation rather than trusting memory or an old summary. A custom extensibility point is the
fallback only where the built-in surface genuinely cannot support the need.

Adoption gate, applied per mechanism: adopt a native mechanism when it

1. fills a real existing gap — never adopt for novelty;
2. is stable and works cleanly — experimental or immature features wait for maturity and are
   re-verified against current docs before each fleet audit; and
3. meets repository standards.

Never custom-build what a fitting native mechanism already covers; retire the custom channel when a
native one matures into fitness.

## Component stances

> **Staleness disclaimer.** The platform changes constantly. Every row carries the date its facts
> were verified against the linked official page. Always re-fetch the current page before acting on
> a row; never trust this table alone. A fetch that diverges from a row is that row's recheck
> trigger: update the row, refreshing its verified date with the outcome. The
> [upstream-drift convention](conventions/upstream-drift/README.md) owns this stamp discipline.

| Component | Stance | Rationale and constraints | Verified |
|---|---|---|---|
| [Skills](https://code.claude.com/docs/en/skills) | Primary surface | The default unit of capability. Newer frontmatter — `paths`, `context: fork` (+ `agent`), `arguments`, skill-scoped `hooks` with `once` — adopted case-by-case through the adoption gate. | 2026-07-17 |
| [`commands/`](https://code.claude.com/docs/en/plugins-reference) | Prohibited | Officially merged into skills; docs direct "use `skills/` for new plugins". Existing flat commands migrate to skill directories. | 2026-07-17 |
| [Agents](https://code.claude.com/docs/en/sub-agents) | Adopt on need | Plugin agents do not support `hooks`, `mcpServers`, or `permissionMode` (security restriction) — design within that limit rather than working around it. | 2026-07-17 |
| [Workflows](https://code.claude.com/docs/en/workflows) | Adopt on need | Native and not experimental: a script in `workflows/`, or wherever the `workflows` manifest field points (that field replaces the default scan), runs as a plugin-namespaced `/plugin:name` command. Availability, not maturity, is the constraint — workflows are paid-plan-gated, a consumer can switch them off (`disableWorkflows`, `CLAUDE_CODE_DISABLE_WORKFLOWS`), and an org can disable them fleet-wide in managed settings; so, as with `bin/`, never make a workflow the only path to a capability. Not "Wait": the [deferred workflow engines](MIGRATION-PLAYBOOK.md#deferred-surfaces--decision-record-2026-07-12) are a named candidate carrying a live trigger, so the gap is identified rather than hypothetical. None ship in this fleet today. | 2026-07-27 |
| [Hooks](https://code.claude.com/docs/en/hooks) | Adopt on need | Exec form (`args`) is mandatory wherever `${user_config.*}` appears — shell form errors since v2.1.207; otherwise read the `CLAUDE_PLUGIN_OPTION_<KEY>` mirror. Windows exec form spawns real executables only (no `.cmd`/`.bat` shims): use `"command": "node", "args": [...]`. | 2026-07-17 |
| [MCP servers](https://code.claude.com/docs/en/mcp) | Adopt on need | Clears the plugin-acceptance security review for egress and trust delegation. | 2026-07-17 |
| [LSP servers](https://code.claude.com/docs/en/plugins-reference) | Adopt on need | Consumer must have the language-server binary; declare the prerequisite per the failure-behavior rules. | 2026-07-17 |
| [Output styles](https://code.claude.com/docs/en/plugins-reference) | Adopt on need | — | 2026-07-17 |
| [`bin/`](https://code.claude.com/docs/en/plugins) | Adopt on need | Executables join the Bash tool's `PATH` while the plugin is enabled; names must be collision-safe (plugin-prefixed) — the platform does not namespace them. That `PATH` delivery is per-session and can silently fail ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066)), so never make bare-name invocation load-bearing: invoke via `${CLAUDE_PLUGIN_ROOT}/bin/`, and note that a `bash "…/bin/x"` invocation does not match a `Bash(x:*)` allow rule. | 2026-07-17 |
| [Plugin `settings.json`](https://code.claude.com/docs/en/plugins) | `agent` prohibited by default | Supports only `agent` and `subagentStatusLine`. `agent` takes over the main thread — a consumer-hostile default for a marketplace plugin; any exception requires documented justification in the plugin README. | 2026-07-17 |
| [Monitors](https://code.claude.com/docs/en/plugins-reference) | Wait | Experimental (`experimental.monitors`); interactive-CLI-only, unsandboxed at hook trust level, no `${user_config.*}` and no `CLAUDE_PLUGIN_OPTION_*` in monitor processes; keep running after mid-session disable. Re-verify before each audit. | 2026-07-17 |
| [Themes](https://code.claude.com/docs/en/plugins-reference) | Wait | Experimental (`experimental.themes`); schema may change between releases. Re-verify before each audit. | 2026-07-17 |
| [Channels](https://code.claude.com/docs/en/plugins-reference) | Wait | No longer carries an official experimental label, but fails the adoption gate today: no fleet gap it fills. Re-verify before each audit. | 2026-07-17 |
| [Dependencies](https://code.claude.com/docs/en/plugin-dependencies) | Adopt on need (hard requires only) | See the design boundary: hard requires only, semver-constrained, released via `{name}--v{version}` tags. None exist in this fleet today. | 2026-07-17 |

## Two-lane convention posture

A plugin must not arrive at an arbitrary consuming repo carrying pre-prescribed conventions. A
convention baked in as a fixed default — a branch-naming grammar, a commit structure, a directory
layout — is a hardcoded assumption that the consumer's practice will never differ from the plugin's;
that is the definition of a dependency, and dependencies are externalized and abstracted, not shipped
as defaults. This governs every plugin and every convention, not one class. Two lanes hold:

1. **Non-conflicting good-practice defaults.** A shipped default is legitimate only when it is a
   good-practice value that cannot conflict in *any* repo the plugin drops into. This lane is narrow:
   most conventions a consumer already holds an opinion on (Conventional Commits in a repo that does
   not use them, for instance) do not qualify, because dropping the plugin in would then impose the
   wrong convention.
2. **Discover via setup, externalize as configuration.** In the general case the plugin's setup
   action or skill discovers the consuming repo's conventions — branch naming, commit structure,
   patterns — and externalizes them as configuration extensibility points rather than coming to the
   table assuming them. A convention a consumer could reasonably do differently belongs in lane 2, as
   a discovered-and-externalized extensibility point, never as a lane-1 default.

A bare lane-1 hardcode in a skill declared agnostic — a fixed default branch, forge, ecosystem, or
tracker where the consuming repo could reasonably differ — is a defect, mechanically caught rather
than asserted only in prose. A detection-first or presence-gated use is compliant. A capability
genuinely and inherently locked to one branch, forge, ecosystem, or tracker declares that narrower,
inherent scope at the coupling site — the same declared-narrower-boundary allowance the
cross-platform contract makes for OS platform — rather than shipping the assumption bare under a
neutral name.

## Configuration ownership and scope

Choose one authoritative owner for each value:

| Concern | Owner and mechanism |
|---|---|
| Invocation-specific choice | Explicit skill argument |
| Personal or administrator-provided scalar | Manifest `userConfig` |
| Tracked repository convention or rich team policy | A documented file under the consumer project |
| Personal project instruction | A documented, gitignored local overlay where the convention supports one |
| Installed dependencies, cache, or generated machine state | `${CLAUDE_PLUGIN_DATA}` |
| Bundled plugin code and assets | `${CLAUDE_PLUGIN_ROOT}` |

`userConfig` is not repository configuration. Claude Code reads its stored `pluginConfigs` values only
from user settings, `--settings`, and managed settings. It ignores project and local settings for this
key. Claude Code owns the configuration prompt and storage; plugin skills must not hand-edit
`pluginConfigs` or invent a marketplace-qualified plugin ID.

Use `userConfig` to its full native extent. Every personal or administrator scalar that flows
through a custom channel — an environment-variable toggle, a gitignored personal file, a documented
hand-edit — migrates to `userConfig` with the schema used honestly:

- correct `type` (`string`, `number`, `boolean`, `directory`, `file`);
- a `default` that preserves zero-config behavior;
- `required: true` only where the plugin is genuinely unusable without the value;
- `sensitive: true` for secrets — noting that on platforms without a supported keychain the value
  lands in `~/.claude/.credentials.json`, so verify storage on the target platform before migrating
  a secret; and
- `claude plugin install --config` documented in the plugin's setup skill for headless use — note
  in that same documentation that this flag only seeds a value on a fresh install; re-running it
  against an already-installed plugin does not update the stored value (empirically verified); and
- for any `sensitive: true` option, the plugin's README documents `/plugin configure <plugin>` as
  the rotation/clear path. This is the only way to change or blank a sensitive value after initial
  enable — the `/mcp` server menu's "Clear authentication" is OAuth-only and silently no-ops for a
  plugin using static `userConfig`-substituted headers, and `/plugin`'s own detail view carries no
  reconfigure entry once a required value is already set. `/plugin configure` is undocumented on
  the official docs site as of this writing; do not assume it will stay that way without
  re-verifying, but do not omit the guidance merely because upstream hasn't written it down.

Hook processes read the native `CLAUDE_PLUGIN_OPTION_<KEY>` mirror — a hook-only export: a Bash
call made by a skill and monitor processes do not receive it. A non-hook consumer (a `bin/` script,
a skill-invoked shell script) takes the value through non-sensitive `${user_config.*}` substitution
in skill or agent content, an explicit argument, or a component field that substitutes it. The
custom environment variable is retired when the migration lands.

A hook kill switch is such a scalar: per-hook selectivity ships as a `userConfig` boolean with a
`default` of `true`, read through the hook mirror. Per-project control stays whole-plugin via
scope-level `enabledPlugins`; a genuinely project-scoped per-hook behavior graduates to the tracked
consumer-project file on demonstrated need — never a custom env channel.

`version` lives in `plugin.json` only, never in a marketplace entry. The platform resolves
plugin.json first, but a marketplace-entry copy is dead metadata that silently becomes live if the
manifest field is ever removed — one home, no shadow.

For project configuration, use neutral repository-relative paths anchored at
`${CLAUDE_PROJECT_DIR}`. Validate configured paths at the boundary, reject absolute paths and traversal
when the contract requires containment, and document precedence. Do not add an environment variable
merely to create a second configuration channel.

## Setup is explicit and repeatable

A plugin requires a `setup` skill iff it has (a) a consumer-project configuration surface, (b) an
external prerequisite — CLI, service, credential — or (c) non-trivial `userConfig`. Apply the
criteria through the modular, configurable, repo-, machine-, and user-agnostic lens; zero-config
zero-prerequisite plugins are exempt — setup is never blanket ceremony. For formatter and linter
plugins the requirement is a thin check-centric setup; where one is not yet shipped, the fleet
conformance audit tracks the gap.

`userConfig` is **non-trivial** when at least one option has a correct value that Claude Code's
native configuration prompt alone cannot establish. An option is non-trivial when it

- names an external referent whose existence, writability, validity, or identity must be verified
  before the plugin behaves as advertised — a path, file, credential, token, account, or model
  identifier;
- carries no default preserving documented zero-config behavior, so the plugin is degraded or blocked
  until the consumer supplies a value; or
- is coupled — its correct value depends on another option's value, or on state outside the manifest
  (wiring, a tracked file, a repository convention) — so the set cannot be settled option by option.

Every other option is trivial: a self-contained scalar — boolean, number, or closed enum — with a
default preserving zero-config behavior and no illegal value to get wrong, including one whose
out-of-set values are documented as falling back to that default. A manifest is trivial when all its
options are, however many it holds: count is not the test and neither is declared `type`.

The line follows from what the native prompt is — a collector, not a verifier. It stores what the
consumer typed; it never confirms the path exists, the token authenticates, or two options agree. A
`setup` skill's `check` is the only surface that can, which is why a non-trivial option requires one.
A trivial option requires none: every legal value is valid by construction and the default already
works, so a `setup` skill would have nothing to verify and nothing to advise. Criterion (c) is the
only criterion this definition governs — a plugin whose `userConfig` is trivial still requires setup
whenever (a) or (b) holds, which is the ordinary case for a plugin whose real surface is a project
config file or an external tool and whose manifest carries only a kill switch.

The uniform contract: the skill is named `setup`, sets `disable-model-invocation: true`, and offers
`check` (read-only inspect and verify) and `apply` (idempotent configure) actions. This is a
normative target — setup skills that predate this contract are nonconforming until brought into
conformance, and the fleet conformance audit tracks the gap rather than the doctrine pretending it
is closed. Setup must be:

- idempotent and safe to rerun;
- transparent about what it inferred, changed, skipped, or could not verify;
- limited to configuration the plugin owns;
- safe for existing files, preserving unrelated user content; and
- non-interactive when complete arguments are supplied, so automation and headless use remain possible.

Setup is one **plugin-level** `setup` skill, never a per-skill setup action. Setup granularity
follows install granularity: a plugin installs and is configured as a unit, and its configuration
surface — tracked project files, external prerequisites, `userConfig` — is plugin-scoped and
routinely shared across skills, so one `setup` skill is the single discoverable entry point
(`/<plugin>:setup`) and the one place `disable-model-invocation` is set for configuration, not a
flag fragmented across per-skill actions. Where distinct skills carry distinct readiness, the one
setup skill aggregates and reports it per skill.

The verb set is deliberately closed at `check` and `apply` — no standalone `remove`, `reset`, or
`migrate` verb joins the mandatory contract (teardown, where genuinely needed, rides as a `remove`
argument to `apply`, per the teardown rule below). `apply` is *state-assessing*: it reads current
state and converges, which the idempotency and preserve-unrelated-content requirements above already
demand, named as a verb contract rather than a new bar. It reconciles conservatively — fill absent
keys at current defaults, preserve keys it does not recognize, and report (never silently rewrite)
values it cannot reconcile, so an obsolete or renamed key surfaces on re-run instead of sitting
silently inert. Schema evolution is handled this way, without a separate `migrate` verb: a plugin
that versions its own config contract may carry a forward, directional, user-confirmed upgrade of a
recognized older version — still under `apply`, never a separate verb and never a silent write (the
versioned standards index is the fleet example) — while a plugin that instead takes topic-docs'
clean-break path relocates by hand with no compatibility tooling. What the clean-break stance rules
out for either is silent backward-compatibility shims and dual-read windows that translate a changed
shape behind the user's back. `reset` decomposes to teardown plus `apply`.

Setup may inspect the repository and create or update the plugin's tracked project configuration. It
must not write into the installed plugin cache, mutate Claude Code user settings, or write
`pluginConfigs`. Personal scalar configuration is collected through Claude Code's native plugin
configuration surface.

`apply` is owed wherever the plugin owns a **writable artifact**, and only there. The test is
ownership plus permission, not location: an artifact whose schema this plugin defines and documents
*and* which this contract permits setup to write — its tracked project config, or a machine-scope
file the plugin owns and the operator may edit — is reachable through `apply`, scoped to exactly that
artifact and nothing adjacent to it.

**Check-only carve-out.** Where a plugin's configuration surface contains no writable artifact, a
check-only setup is conforming: `check` verifies and reports, and no `apply` is offered because there
is nothing it could conformingly write. Three kinds of surface qualify, in any combination:

- **Native `userConfig`.** Reconfiguration routes through the native flow (`/plugin configure
  <plugin>` — see above); the only thing an `apply` could write is the `pluginConfigs` this contract
  forbids.
- **Claude Code settings this contract forbids setup to mutate** — statusline wiring, a settings-level
  key, anything in the user's own `settings.json`. This surface is neither `userConfig` nor tracked
  project config; the prohibition two paragraphs above is what makes it unwritable, and a plugin
  whose behavior is delivered through it is a normal shape, not an exception. Silence is not the
  conforming response: `check` prints the exact edit, fully resolved and ready to paste, states that
  it is the operator's to apply, and names what re-invalidates it (a plugin update moving
  `${CLAUDE_PLUGIN_ROOT}`, say).
- **External prerequisites setup can only verify** — a system tool, service, or credential, per the
  prerequisites section. `check` probes and reports the remediation; installing is the operator's.

Check-only is therefore a consequence of having nothing conforming to write, never a preference and
never a shortcut. A plugin with even one writable owned artifact takes the narrow-write shape
instead — `apply` bounded to that artifact, while every unwritable surface is still handled the
check-only way above. Which shape a plugin takes is settled by its surface, not by its author, and
both are conforming when the surface is what selected them. Two plugins with the same unwritable
settings surface can therefore differ legitimately: the one that also owns a documented machine-scope
file must offer the narrow `apply`; the one that owns nothing writable must not invent one.

Bare `apply` converges to the configured state and never removes; genuine teardown — converging to
the *absence* of the plugin's own tracked project config — is the one thing `apply` will not do
unasked. A plugin that genuinely needs it exposes it as an optional apply-scoped operation (an
`apply remove`, under the same never-blind, preserve-unrelated discipline), bounded to the tracked
project config the plugin owns and never to `pluginConfigs` — whose reconfigure-or-clear path stays
the `/plugin configure` flow the check-only carve-out above routes to. Teardown stays off the
mandatory contract because it is destructive and, across the fleet today, unexercised — grounds to
defer it with a trigger, not proof it is never needed: a second plugin needing teardown graduates a
shared teardown shape into an owner doc before that second adopter — a step the fleet conformance
audit checks, the same enforcement every convention-registry row rides. The distinction is config versus
data: removing the plugin's own tracked setup config is teardown, whereas an apply-scoped operation
that mutates a managed inventory the plugin maintains (a status change over existing entries, say)
is ordinary `apply` surface, not teardown, and does not trip that trigger.

Two native idioms are the sanctioned initialization surfaces (verified 2026-07-17 against the
[hooks reference](https://code.claude.com/docs/en/hooks) and
[plugins reference](https://code.claude.com/docs/en/plugins-reference)): the `Setup` hook event
(`--init-only`, or `--init`/`--maintenance` in `-p` mode) for headless and CI preparation, and a
`SessionStart` hook comparing a bundled manifest against its `${CLAUDE_PLUGIN_DATA}` copy for
runtime-dependency installation.

These native idioms complement the `setup` skill; they do not compete with it, and native-first is
honored either way. The skill is the interactive, discoverable consumer-configuration face
(check/apply over tracked project config) — a need no native hook exposes, so the skill is not a
redundant custom mechanism. The `Setup` hook event and `SessionStart` install hook are the
unattended faces the same plugin may also carry, and unattended init routes to them rather than a
custom channel. Where both exist they converge to one idempotent state. The `setup` skill fulfills
the `setup`-skill requirement above; the headless dimension may be complemented — never replaced —
by these native idioms.

## Prerequisites and failure behavior

Declare every required runtime, shell, CLI, service, credential, and platform constraint at the point
of use and in the plugin README. Never download or execute an undeclared tool as an incidental fallback.

Classify absence deliberately:

- **Required for correctness:** stop at the entry point with a concise remediation message.
- **Required for an optional feature:** warn visibly, skip only that feature, and continue with the
  documented reduced result.
- **Not applicable:** exit quietly and successfully.

Anything with a runtime prerequisite (for example `jq` on `PATH`) degrades gracefully — never a hard
crash. Absence is surfaced to both the agent and the user; a candidate channel for durable
visibility is the hook-telemetry convention's OTel surface. No black boxes: a silently skipped
feature is a defect.

Hooks follow the event's official control contract. Use a blocking result only when the event can still
be blocked and the hook is enforcing a policy. Advisory hooks surface a visible non-blocking diagnostic.
Do not swallow errors or claim success when the promised result was not produced.

## Convention registry

One owner doc per shared concern. This registry names and points — it never restates; each owner doc
carries the rules, versioning, and adoption story. A new cross-plugin convention lands in an owner
doc before a second plugin adopts it. Fleet audits check conformance per row.

| Shared concern | Owner |
|---|---|
| Topic-docs two-tier binding | [`docs/conventions/topic-docs/`](conventions/topic-docs/README.md) |
| Lifecycle artifact protocol | [`docs/PLUGIN-ARTIFACT-PROTOCOL.md`](PLUGIN-ARTIFACT-PROTOCOL.md) |
| Shared hook utility library | `lib/hook-utils.sh`, synced by `scripts/sync-hook-utils.sh` |
| Cross-plugin shared-source clusters | `scripts/cross-plugin-source-registry.txt` |
| Config cascade — consumer-config layering and precedence | [`docs/conventions/config-cascade/`](conventions/config-cascade/README.md) |
| Commit-convention enforcement seam | [`docs/conventions/commit-convention/`](conventions/commit-convention/README.md) |
| PR-body required-sections convention | [`docs/conventions/pr-body-convention/`](conventions/pr-body-convention/README.md) |
| Ecosystem command resolution | [`docs/conventions/ecosystem-commands/`](conventions/ecosystem-commands/README.md) |
| Hook telemetry | [`docs/conventions/hook-telemetry/`](conventions/hook-telemetry/README.md) |
| Hook observability (status/failure surfaces) | [`docs/conventions/hook-observability/`](conventions/hook-observability/README.md) |
| Hook precision (false-positive discipline) | [`docs/conventions/hook-precision/`](conventions/hook-precision/README.md) |
| Hook config delivery (userConfig→hook channel matrix) | [`docs/conventions/hook-config-delivery/`](conventions/hook-config-delivery/README.md) |
| Permission-rule hygiene | [`docs/conventions/permission-rule-hygiene/`](conventions/permission-rule-hygiene/README.md) |
| Repository standards index | [`docs/conventions/standards/`](conventions/standards/README.md) |
| Skill layout contract and evals schema | `skill-quality` plugin (contract gate + bundled schema) |
| Review severity vocabulary | `review` plugin (`context/severity.md`) |
| Seam phrasing (presence-gated fallbacks) | [`docs/conventions/seam-phrasing/`](conventions/seam-phrasing/README.md) |
| Loop-lane topology, escalation, capability tiers, loop invariants | [`docs/conventions/loop-lane/`](conventions/loop-lane/README.md) |
| Shell test-helper duplication and exit-code divergence | [`docs/conventions/shell-test-helpers/`](conventions/shell-test-helpers/README.md) |
| Finding suppression (deliberately-kept audit findings) | [`docs/conventions/finding-suppression/`](conventions/finding-suppression/README.md) |
| Fresh-eyes declaration pattern contract | `skill-quality` plugin (`skills/check/reference/fresh-eyes-declarations.md`) |
| Upstream-drift verification stamps and recheck triggers | [`docs/conventions/upstream-drift/`](conventions/upstream-drift/README.md) |

## Cross-platform contract

Windows, macOS, and Linux are supported unless a plugin explicitly declares a narrower, inherent
platform boundary. Consequently:

- build paths from documented anchors with platform path APIs;
- never assume Bash, `jq`, executable bits, symlinks, a package manager, or a browser is present;
- state a shell requirement and provide the supported Windows path when a shell script is unavoidable;
- keep tracked filenames, encoding, and generated output portable; and
- verify OS-sensitive changes on each supported platform, or record an honest manual-verification gap.

Optional platform integrations must degrade visibly and preserve the portable core result.

## Evidence and validation

Research precedes design. For Claude Code behavior, fetch the current official documentation in the
same work session; do not rely on memory or an old summary. For a dependency or architectural choice:

1. establish the requirement from repository standards and the consumer contract;
2. prefer the primary specification and maintainer documentation;
3. validate maintenance, adoption, security posture, platform support, and fit using current trusted
   sources when the choice is not dictated by the platform;
4. distinguish documented behavior, official precedent, local empirical evidence, and repository
   policy; and
5. record the source and verification date near a time-sensitive decision without copying volatile
   limits, prices, or version tables.

Validate the shipped behavior, not only the prose: manifest validation, deterministic tests, negative
path and prerequisite tests, local `--plugin-dir` smoke tests, and the repository's plugin contract gate.
Apply the standards principles of explicit behavior, fail-fast boundaries, idempotency, one mechanism
per concern, cross-platform operation, and stress-testing before presentation.

## Fresh-eyes checkpoints

A context that produced work is structurally the weakest place to judge that work: the reasoning that
made a mistake plausible is still active, so a self-check inherits the bias. A fresh-context (non-fork)
subagent — generic or named — removes it: it starts in its own fresh context window, blind to the
reasoning under review. A fork does not: it inherits the parent session's full conversation history, so
it carries the same bias forward
([subagents](https://code.claude.com/docs/en/sub-agents), verified 2026-07-22).

The rule: **a skill step whose output judges work produced in the same context delegates that judgment
to a fresh-context (non-fork) subagent** — a named subagent that starts with a fresh context window, not
a fork. Mandatory in the skill's design, not left to the invoker to remember. Three bias classes name
the trigger:

- **author-verifier** — verifying a change the same context authored (a verification skill confirming
  its own session's implementation, a pre-PR self-review);
- **plan-attacker** — adversarially attacking a plan the same context helped shape (a devil's-advocate
  pass run in the authoring session);
- **self-grade** — scoring the same context's output against criteria (a quality gate in self mode, a
  synthesis step grading its own lock).

The delegation target has an independence ladder: a same-vendor fresh context removes the session's
reasoning but can still share the model's blind spots; a different-vendor advisor removes both. Where
the verdict is high-stakes and correlated blind spots are the risk, a checkpoint site prefers a
cross-vendor advisor **when one is installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the
stated fallback, never a route to a command that may not resolve. That reference is optional
collaboration, so it carries the presence-gate-plus-fallback shape
([seam phrasing](conventions/seam-phrasing/README.md)) at each site that instructs it; an advisor
plugin external to this marketplace is never a manifest dependency. Invocation mechanics —
synchronous waiting, diff-base selection, which artifacts a surface can judge — are the advisor
plugin's own documentation's concern: a checkpoint site names the capability and the fallback,
never the advisor's command flags, which drift against the surface their owner evolves.

What does not need it: deterministic gates (a script's pass/fail cannot be biased by context — prefer
one wherever the judgment is mechanical), and judgment over external input the context did not produce
(triage of another author's issue or PR). Delegation cost is real; the rule buys unbiased judgment
exactly where bias is structural, and nothing elsewhere.

The deterministic-gate exemption is narrow: it reaches the mechanical judgment itself — where the gate's
pass/fail *is* the verdict — not a subjective self-review that merely runs ahead of a gate. A build/test/lint
pass gates behavior and the conventions its linters encode, not scope creep or the conventions it leaves
unchecked; self-judging those stays the same-context judgment the rule targets even when a deterministic gate
sits downstream. A step that self-reviews both is exempt only for the gated part — the rest is still owed a
fresh-context pass.

## Delegation mechanics

How a fresh-eyes checkpoint dispatches. The mechanics live here once; a checkpoint site states its
judgment and its target, never re-derives these rules.

### Dispatch ladder

The default worker is a **generic fresh-context subagent carrying rich inline instructions** — the
task, the artifact, the criteria, and the output shape all travel in the dispatch prompt. A subagent
starts with a fresh, isolated context window and does not see the parent conversation
([subagents](https://code.claude.com/docs/en/sub-agents), verified 2026-07-22), which is exactly the
independence the checkpoint buys. A skill may prefer an installed **named agent** on the next rung —
but only when the named-agent bar below is met, and the site always states the generic fallback
(presence-gate-plus-fallback, [seam phrasing](conventions/seam-phrasing/README.md)). The top rung, for
high-stakes verdicts where correlated model blind spots are the risk, is a **cross-vendor advisor**
when one is installed — same presence-gate shape, same generic fallback.

### Inline-template conventions

A dispatch prompt at any rung:

- says **fresh-context** work is expected — the worker judges the artifact it is handed, with no
  access to the reasoning that produced it;
- hands over the **artifact, not the story** — the diff, file, or plan itself, never the authoring
  session's rationale, which would re-import the bias being removed;
- **degrades when absent** — a preferred named agent or advisor that is not installed routes to the
  generic fresh-context subagent, never to a command that may not resolve.

### Named-agent bar

A named agent is earned, not default: **the same worker with the same instructions dispatches from
multiple sites (or repeats via description-triggered direct invocation) AND a model pin or an
enforced tool restriction is load-bearing.** Otherwise the generic subagent with inline instructions
is the simpler, equally independent form. On tool cages: an allowlist that includes Bash bars
Edit/Write and recursive spawning but is **not read-only** — Bash can write; state what the cage
actually enforces, never "read-only" ([plugin agents support `tools` frontmatter](https://code.claude.com/docs/en/plugins-reference),
verified 2026-07-22).

### Model tiers

The ladder is relative to the session: **a consequential verdict runs at the session-model tier or
above, never below; tedious or mechanical preparation may drop one tier.** The heavy default must be
explicit — an agent definition that omits `model` defaults to `inherit`, the main conversation's
model ([subagents: model resolution](https://code.claude.com/docs/en/sub-agents#choose-a-model),
verified 2026-07-22; frontmatter accepts `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or
`inherit`). Consumers hold one global override knob: `CLAUDE_CODE_SUBAGENT_MODEL`, set via the
settings `env` map, which overrides both the per-invocation `model` parameter and frontmatter
([model config: environment variables](https://code.claude.com/docs/en/model-config#environment-variables),
verified 2026-07-22; `env` applies to every session and spawned subprocess,
[settings](https://code.claude.com/docs/en/settings), verified 2026-07-22). There is no per-plugin
model seam — plugin `userConfig` declares only generic typed options with no model semantics
([plugins reference: user configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration),
verified 2026-07-22) — so doctrine travels by authoring-time conformance in each skill, not runtime
configuration.

Tier-to-model mapping, dated 2026-07-22 (recheck trigger: a new Claude model family reaches GA, or
the session default model changes):

| Tier | Model (2026-07-22) |
|---|---|
| Consequential verdict (session tier or above) | Fable 5 / Opus 4.8 |
| Mechanical prep, one tier down | Sonnet 5 |
| Bulk mechanical sweeps | Haiku 4.5 |

### Declared patterns

Conformance is declared in the skill text itself, in one of two greppable forms: **delegation
wording** (the POSIX ERE `fresh[- ]context` on a line that also names the worker or dispatch,
plus the ladder conventions above) or an **exemption directive** (`<!-- fresh-eyes-exempt: <class> -- <reason> -->`, closed class set
`deterministic-gate` | `external-input` | `deferred`). The mechanical contract — grammar, classes,
canonical wording, check semantics — is owned by the `skill-quality` plugin
(`skills/check/reference/fresh-eyes-declarations.md`), where the conformance check points third-party
authors; this section carries the rationale and defers the spec there (convention-registry row
above). The declaration anchors in each skill's own scanned files even when the judgment mechanics
live in a plugin-level shared spoke — the generic checker cannot assume a plugin layout.

## Authoritative references

The complete categorized index of plugin-relevant official pages is
[`docs/OFFICIAL-DOCS.md`](OFFICIAL-DOCS.md); `https://code.claude.com/docs/llms.txt` is the
authoritative self-updating master list. Pages load-bearing for this document, verified 2026-07-17:

- [Create plugins](https://code.claude.com/docs/en/plugins) — plugin structure incl. `bin/` and
  plugin `settings.json`, namespaces, testing, and migration.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — component schemas,
  `userConfig`, experimental components, version management, cache isolation, persistent data.
- [Skills](https://code.claude.com/docs/en/skills) — frontmatter reference and skill lifecycle.
- [Hooks reference](https://code.claude.com/docs/en/hooks) — exec form vs shell form, event list,
  `Setup` event, skill-scoped hooks.
- [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies) — constraints, release
  tags, bundles.
- [Claude Code settings](https://code.claude.com/docs/en/settings) — settings scopes, precedence, and
  the special storage and read scopes of `pluginConfigs`.
- `melodic-software/standards` `conventions/engineering/shareable-artifact-design.md` — the
  artifact-agnostic consumer-facing design doctrine the design boundary, configuration ownership,
  and setup contract above specialize for plugins.
- `melodic-software/standards` engineering philosophy and cross-platform review criteria — repository
  design and verification policy.

Verified 2026-07-17:

- [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies) — the `dependencies`
  array, automatic installation, and version constraints.
- [Skills](https://code.claude.com/docs/en/skills) — command-name derivation and the plugin skill
  namespace.
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
  — naming-convention guidance this document deviates from deliberately.
- [Agent Skills specification](https://agentskills.io/specification) — `name` field constraints and
  directory matching.
