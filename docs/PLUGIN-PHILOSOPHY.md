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

This follows Claude Code's own distinction between standalone configuration — for "personal
workflows, project-specific customizations, quick experiments" — and plugins, for "sharing with
teammates, distributing to community, versioned releases, reusable across projects"
([create plugins](https://code.claude.com/docs/en/plugins#when-to-use-plugins-vs-standalone-configuration),
verified 2026-08-10). Namespaced skill invocations are part of that isolation, not an
implementation detail.

## Naming

A skill name is an imperative verb phrase; the plugin namespace supplies the object
(`/machine-health:audit`, `/source-control:commit`). Names compose into instruction sentences —
"/discovery:explore the module, then /planning:interview me" — and one grammar keeps every name in
the marketplace predictable. This is a deliberate, documented deviation from the official authoring
guidance's gerund preference — and the guidance sanctions it: gerunds are what it says to "consider
using", action-oriented names (`process-pdfs`, `analyze-spreadsheets`) are listed under "Acceptable
alternatives", and what it puts under Avoid is "inconsistent patterns within your skill collection",
which is exactly the consistency this section supplies
([skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
verified 2026-08-10).

Verb meanings are fixed:

| Verb | Contract |
|---|---|
| `audit`, `scan` | Read-only findings report. Mutation only behind an explicit user override such as an autofix argument, never on bare invocation; safety qualifiers may narrow what an override touches. |
| `check` | Deterministic pass/fail gate. |
| `clean`, `tidy`, `fix` | Mutates the target. |
| `realign` | Consumes a findings artifact a sibling `audit` produced and drives the human-gated realignment it recommends; never re-judges the surface itself. Mutation only behind explicit per-item user acceptance, never on bare invocation and never under a blanket approval. |
| `setup` | Configures the plugin for a consumer, per the setup section below. |
| `update` | Refreshes vendored upstream material. |

When a bare verb would collide with or under-specify against a sibling in the same namespace, a
topic qualifier follows the verb with a hyphen (`audit-noise` beside `audit-encapsulation`,
`scan-todos` under `work-items`); the verb keeps its fixed meaning from the table.

Nouns are reserved for knowledge routers (`principles`, `methodology`) and lifecycle-object routers
(`worktree`, `pull-request`). Six further documented exceptions: a single-skill vendor-CLI wrapper
repeats its tool name (`firecrawl:firecrawl`); a `-deep` suffix marks the heavier
isolated-execution tier of a sibling skill (`research`/`research-deep`); a knowledge router named by
its method's own literature term keeps that term when renaming would destroy recognized craft
vocabulary (`songwriting:object-writing`, `meter-prosody`, `song-form` — Pattison's terms); a
playbook router named by its source keeps the source's own identifier, because provenance is the
content's identity (`playbooks:boris`, `playbooks:fable-5` — one scheme, person or model alike);
and an object-pronoun qualifier is kept when the skill's defining boundary IS that the object under
test is the user themself (`education:quiz-me` — the `-me` distinguishes quizzing the human on
completed work from teach's in-workspace content quizzing, where a bare `quiz` would under-specify
the object the grammar normally delegates to the namespace); and an upstream utterance-interjection
is kept when the skill is a port whose typed phrase IS the mechanism — the user's own words at the
moment of use — and the upstream name carries cross-repo muscle-memory parity
(`discipline:wait-what` — the lost reader's literal interjection; an imperative paraphrase destroys
the zero-translation recall the command depends on precisely when its user is, by definition, lost,
and orphans users arriving from the upstream repo).
Every exception is an entry on this list, decided per name — a name class is never
blanket-sanctioned.

A plugin skill declares no frontmatter `name`. The field is optional and defaults to the directory
name ([frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference), fetched
2026-08-10), and the directory here is already the name the skill is documented and invoked by, so
declaring it restates the path in the character set the Agent Skills specification allows. The one
effect a declaration still buys is the bare alias: in a plugin skill a declared `name` also registers
the bare `/<name>` alongside the namespaced command, unless another command already owns that token
([how a skill gets its command name](https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name)).
Declare it only to take that alias deliberately, and only with the value the directory already
carries. A `name` that *differs* from its directory is out of bounds here even though the harness
honors it: it would relocate the last command segment away from the directory that
`scripts/check-skill-leaf-names.sh` derives every leaf from, desynchronizing the cross-plugin
collision registry from the commands that actually resolve — which is why `skill-quality`'s check 1
fails a divergent `name` and only warns on a redundant one.
Never degrade a name to dodge a built-in command: plugin skills are namespaced and cannot collide
with other levels. When a name matches a built-in, the bare token still belongs to the built-in; the
namespaced form is the plugin skill's only command.

Resolution settled, **display** follows from it. The docs pin the history — before v2.1.216 a
declared `name` replaced the whole command, so the menu showed the bare form and the namespaced one
did not autocomplete; that is gone. The rest is observed in the client rather than documented
(2.1.225): the picker labels a row with the command it resolves — `/planning:plan`, prefix and all —
and appends a bare alias in parentheses only when what you typed prefix-matches that alias, so a
skill declaring no `name` never renders the stuttering `/plugin:skill (skill)`. Re-observe before
relying on the parenthetical; the labelling itself follows from resolution and is the stable part.
Origin is spelled out again in the description: a plugin skill
renders as `(<plugin-name>) <description>`, a personal skill as `<description> (user)`, a project
skill as `(project)` or `(project, gitignored)` depending on whether it came from shared or local
settings, and a built-in, bundled, or MCP entry carries no marker at all. So a leaf name shared
across plugins is unambiguous to *invoke* and to *read* — its prefix distinguishes it in both
columns. Never rename to buy display uniqueness; spend the effort on the description's first clause
carrying the distinguishing object, since that column is what a reader actually scans.

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

### Recorded gate runs

Platform surfaces the gate has been run against, recorded in the
[upstream-drift](conventions/upstream-drift/README.md) four-part shape — claim, basis, as-of date,
trigger. Defer and decline are results, not omissions; the trigger, never the date, is what obliges
re-deriving a row.

| Surface | Verdict | Basis and reason | Recheck trigger | Verified |
|---|---|---|---|---|
| [Run agents in parallel](https://code.claude.com/docs/en/agents) | Adopt, as a citation | The upstream comparison of every way Claude Code runs multiple agents — subagents, agent view, agent teams, dynamic workflows. Adopted as the [dispatch ladder](#dispatch-ladder)'s canonical index and cited there, never restated, so the menu an author chooses from cannot go stale inside this file. | The page adds or drops a parallelism surface. | 2026-08-10 |
| [Feature availability](https://code.claude.com/docs/en/feature-availability) | Adopt, as a citation | Per-feature availability by model provider and subscription plan — the canonical input to the [cross-platform contract](#cross-platform-contract), cited there. Its "platform" sense is the *provider* platform (Anthropic Console, Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, Microsoft Foundry), never the host surface a consumer runs in; that axis is [Platforms and integrations](https://code.claude.com/docs/en/platforms), a separate row below. Copying it is barred by [evidence and validation](#evidence-and-validation): a provider matrix is exactly the volatile table that rule names. | A plugin proposes narrowing its platform support — re-fetch the matrix then, never trust a restatement. | 2026-08-10 |
| [Agent teams](https://code.claude.com/docs/en/agent-teams) | Defer | Fails gate 2 and stops there: "Agent teams are experimental and disabled by default", gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, with limitations the page states outright — "No nested teams: teammates cannot spawn their own teammates", and `/resume` and `/rewind` do not restore in-process teammates. Defer rather than decline: the gap question stays open while the surface is opt-in and churning, and no plugin may depend on a team meanwhile. | The page drops the experimental warning or the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` requirement. | 2026-08-10 |
| [Cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging) | Decline | Fails gate 1: the channel is for "independent sessions that you start and steer yourself", not for a skill dispatching a worker. It could not be a portable rung either — "Claude Code doesn't offer cross-session messaging on native Windows", and it is absent on Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, and Microsoft Foundry. | Either premise moves: the page stops scoping the channel to sessions you steer yourself, or its Availability section stops excluding native Windows or any of those four providers. | 2026-08-10 |
| [Sessions](https://code.claude.com/docs/en/sessions) | Decline | Fails gate 1. Resume restores "the full history, including tool calls and results" — the authoring story the [inline-template conventions](#inline-template-conventions) exist to withhold, so it is the opposite of a fresh-eyes rung rather than a missing one. A human session-management surface with no plugin-authoring seam. | `sessions` grows a plugin-facing seam: a manifest field, a tool, or skill frontmatter. | 2026-08-10 |
| [Platforms and integrations](https://code.claude.com/docs/en/platforms) | Adopt, as a citation | The upstream index of every host Claude Code runs in — CLI, Desktop, VS Code, JetBrains, web, mobile — and the integrations beside them. Adopted as the [cross-platform contract](#cross-platform-contract)'s canonical input for the host axis, which the already-adopted [feature availability](https://code.claude.com/docs/en/feature-availability) does not carry: that page's axes are provider and plan, and it scopes itself to what runs locally — "The Claude Code CLI and everything that runs locally work on every provider." The host axis is load-bearing because a host can withhold the plugin system outright rather than one capability: a Desktop session in WSL 2 lists "connectors and plugins" among features that "aren't available in WSL sessions yet"; on mobile, "commands that only run in the terminal interface, such as `/plugin` and `/resume`, don't work from the app"; Desktop's Cowork tab sources its plugins from claude.ai configuration, "not from the CLI's `~/.claude` directory"; and the VS Code extension carries only a "Subset" of the CLI's "Commands and skills", so a skill this fleet ships may simply not be reachable there. None of those four is restated in the contract — only the rule they establish is. | `platforms` adds or drops a host, or `feature-availability` grows a host-surface axis, which would make this citation redundant. | 2026-08-10 |
| [GitHub Enterprise Server](https://code.claude.com/docs/en/github-enterprise-server) | Decline | Does not fail gate 1 by subject — it is a real plugin-distribution surface, "Plugin marketplaces \| ✅ Supported", and the only page in this run that names one. It fails on need. Nothing in this repo documents a GHES-hosted mirror or fork of this marketplace, and no README anywhere ships a full-git-URL install path — the form GHES requires. Census of the 65 plugin READMEs: 54 carry the literal `/plugin marketplace add melodic-software/claude-code-plugins`; 9 carry no install block; `dometrain` points at another github.com marketplace; and `github`, being marketplace-agnostic, uses the placeholder `<marketplace-owner>/<marketplace-repo>`. All of those are the same `owner/repo` shorthand, which the page says "always resolves to github.com" — correct for this marketplace, and the one place the finding could bite: a consumer redistributing the `github` plugin from a GHES-hosted marketplace would follow that README and silently resolve to github.com instead of their own host. The GHES-specific obligations — full git URL, `extraKnownMarketplaces` pre-registration, `hostPattern` allowlisting — otherwise land on a consumer running their own instance, not on this marketplace. | This repo documents a GHES-hosted mirror or fork, or any README gains an install path that is not `owner/repo` shorthand — a full git URL being the form that means a non-github.com host is in play. Also fires if `plugins/github/README.md` starts naming a concrete GHES-hosted marketplace. | 2026-08-10 |
| [Ultrareview](https://code.claude.com/docs/en/ultrareview) | Decline | Fails gate 1: no seam a plugin can reach. Each run is human-gated and metered — "Claude Code shows a confirmation dialog with the review scope, your remaining free runs, and the estimated cost", then "typically \$5 to \$25 in usage credits" — so it can never be a rung in an automated dispatch ladder. Nor is `review:fanout` a custom rebuild of it that Native-first would retire: fanout normalizes many in-session finding producers into one ranked report, where this is one confirmed cloud run. | The page documents a non-interactive or programmatic entry point. | 2026-08-10 |
| [Chrome](https://code.claude.com/docs/en/chrome) | Decline | Fails gate 1: a consumer-installed browser integration delivered as a built-in skill — Claude Code "asks for permission to use the `claude-in-chrome` skill" — so a plugin has nothing to declare here and must not rebuild automation the platform already ships. Recorded rather than dismissed because the page only *looked* cited: the repo's sole reference is a `docs/en/browser` URL that now returns 404, inside `plugins/playbooks/skills/boris/vendor/SKILL.md` — a verbatim upstream baseline kept for drift detection, which is why it is deliberately not hand-edited here. | A plugin proposes shipping browser automation, or `/playbooks:update` refreshes the boris baseline and the stale slug persists. | 2026-08-10 |
| [Checkpointing](https://code.claude.com/docs/en/checkpointing) | Decline | Nothing to adopt, and the reason is the outcome: `/rewind` cannot be a mutating skill's undo story, because "Checkpointing does not track files modified by bash commands" and, for any subagent other than a foreground forked skill, "rewinding doesn't restore the edits. Use git to revert them." The restored carve-out is narrow — a `context: fork` skill running in the foreground — so a skill that mutates through a shell script or a background worker states a git-based rollback and never leans on `/rewind`. | The limitations section drops either the bash-command or the subagent exclusion. | 2026-08-10 |

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
| [Hooks](https://code.claude.com/docs/en/hooks) | Adopt on need | Exec form (`args`) is mandatory wherever `${user_config.*}` appears — shell form errors since v2.1.207; otherwise read the `CLAUDE_PLUGIN_OPTION_<KEY>` mirror. Windows exec form spawns real executables only (no `.cmd`/`.bat` shims): use `"command": "node", "args": [...]`, a `${CLAUDE_PLUGIN_ROOT}`-rooted path, or shell form with `"shell": "bash"` — never a bare `bash`/`sh` (WSL relay) or `python`/`python3` (WindowsApps alias stub), whose launch fails non-blockingly and leaves a guard hook silently enforcing nothing. Prose cannot self-verify, so `scripts/check-hook-exec-form.sh` turns that rule into a mechanical check across hook configs and skill/agent frontmatter alike. | 2026-07-17 |
| [MCP servers](https://code.claude.com/docs/en/mcp) | Adopt on need | Clears the plugin-acceptance security review for egress and trust delegation. Also the only component type that can cost a consumer their prompt cache: every other kind only appends to the request, while enabling or disabling a plugin that provides an MCP server forces a full re-read whenever the server's tools load into the prefix instead of being deferred by tool search ([actions that invalidate the cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache), verified 2026-08-10). | 2026-08-10 |
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

Two reviewer-visible comment tokens carry that declaration, and they differ in REACH rather than in
strength. `portability-ok: <reason>` records one site: the coupling on that line (or the line below
a comment block carrying it) is excused and nothing else in the file is. `portability-scope:
<reason>` declares the whole file inherently locked — the case a forge-locked capability under a
forge-neutral name actually needs. Reach is the entire distinction, so the choice is a claim about
what is true: a per-site annotation on a file that is genuinely scope-locked buries the boundary,
and a whole-file declaration used to silence one awkward line exempts every future coupling added to
that file, including ones nobody reviewed. Neither is a frontmatter field; both are ordinary
comments a reviewer reads in the diff. `scripts/check-skill-portability.sh` enforces this, with the
coupling tokens it matches held as data in `scripts/skill-portability-tokens.txt`.

Detection evidence is scoped to the coupling class that authored it. A command proving which
*branch* was resolved says nothing about which *remote* holds it, so it cannot excuse a hardcoded
remote name that happens to share the line — a guard that generalizes across classes turns one
legitimate resolution into a blanket exemption for couplings it never examined.

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
- for any `sensitive: true` option, the plugin's README documents `/plugin configure
  <plugin>@<marketplace>` as the rotation/clear path (see
  [`docs/extensibility-contract-smoke-tests.md`](extensibility-contract-smoke-tests.md) Test E —
  plugin identity is always marketplace-qualified; the bare name alone is not a documented command
  under a same-name, two-marketplace install). This is the only way to change or blank a sensitive
  value after initial enable — the `/mcp` server menu's "Clear authentication" is OAuth-only and
  silently no-ops for a plugin using static `userConfig`-substituted headers, and `/plugin`'s own
  detail view carries no reconfigure entry once a required value is already set. Targetless prose
  ("use `/plugin configure`") names the surface, not an install identity, and stays unqualified.
  `/plugin configure` is undocumented on the official docs site as of this writing; do not assume it
  will stay that way without re-verifying, but do not omit the guidance merely because upstream
  hasn't written it down.

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

Apply the same anchoring rule to bundled assets: one skill citing another skill's supporting file
writes the full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form, optionally paired with a
relative markdown link target for browsing on GitHub — for example
``[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md)``.
A bare `context/…`-style path is reserved for a skill's OWN supporting files; it resolves against
the citing skill's directory, so a cross-skill citation written that way points at a file that is
not there.

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

The uniform contract: the skill is named `setup`, sets `disable-model-invocation: true` — matching
upstream's own rule for the flag, "for workflows with side effects that you want to trigger
manually" ([best practices](https://code.claude.com/docs/en/best-practices), verified 2026-08-10) —
and offers `check` (read-only inspect and verify) and `apply` (idempotent configure) actions. The
rest of the shape is house doctrine, and says so: upstream documents native *initialization*
surfaces (below) but takes no position on a consumer-facing `setup` skill, so the `check`/`apply`
split and the criteria above rest on the reasoning given here rather than on upstream backing. This
is a normative target — setup skills that predate this contract are nonconforming until brought into
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
  <plugin>@<marketplace>` — see above); the only thing an `apply` could write is the `pluginConfigs`
  this contract forbids.
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

Two native idioms are the sanctioned initialization surfaces (verified 2026-08-10 against the
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
feature is a defect. The broader false-green class — healthy-while-dead and green-with-hidden-
findings on health, status, advisory, and gate surfaces — is owned by the
[liveness-assertion convention](conventions/liveness-assertion/README.md); this section's
prerequisite-absence rules are one slice of that contract, specialized here for runtime absence.

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
| Plugin-data report keying, retention, and overwrite | [`docs/conventions/plugin-data-report-keying/`](conventions/plugin-data-report-keying/README.md) |
| Repository standards index | [`docs/conventions/standards/`](conventions/standards/README.md) |
| Skill layout contract and evals schema | `skill-quality` plugin (contract gate + bundled schema) |
| Review severity vocabulary | `review` plugin (`context/severity.md`) |
| Seam phrasing (presence-gated fallbacks) | [`docs/conventions/seam-phrasing/`](conventions/seam-phrasing/README.md) |
| Loop-lane topology, escalation, capability tiers, loop invariants | [`docs/conventions/loop-lane/`](conventions/loop-lane/README.md) |
| Shell test-helper duplication and exit-code divergence | [`docs/conventions/shell-test-helpers/`](conventions/shell-test-helpers/README.md) |
| Finding suppression (deliberately-kept audit findings) | [`docs/conventions/finding-suppression/`](conventions/finding-suppression/README.md) |
| Liveness assertion (false-green / healthy-while-dead surfaces) | [`docs/conventions/liveness-assertion/`](conventions/liveness-assertion/README.md) |
| Detector findings (non-fanout producers reaching the apply relay) | [`docs/conventions/detector-findings/`](conventions/detector-findings/README.md) |
| Fresh-eyes declaration pattern contract | `skill-quality` plugin (`skills/check/reference/fresh-eyes-declarations.md`) |
| Upstream-drift verification stamps and recheck triggers | [`docs/conventions/upstream-drift/`](conventions/upstream-drift/README.md) |
| Windows path emission across the Git Bash → native boundary | [`docs/conventions/windows-path-emit/`](conventions/windows-path-emit/README.md) |

## Cross-platform contract

Windows, macOS, and Linux are supported unless a plugin explicitly declares a narrower, inherent
platform boundary. Consequently:

- build paths from documented anchors with platform path APIs;
- never assume Bash, `jq`, executable bits, symlinks, a package manager, or a browser is present;
- state a shell requirement and provide the supported Windows path when a shell script is unavoidable;
- keep tracked filenames, encoding, and generated output portable; and
- verify OS-sensitive changes on each supported platform, or record an honest manual-verification gap.

Optional platform integrations must degrade visibly and preserve the portable core result.

[Feature availability](https://code.claude.com/docs/en/feature-availability) is this contract's
canonical input: fetch it when a platform, provider, or plan question decides something, and restate
none of it here (verified 2026-08-10, [recorded gate runs](#recorded-gate-runs)). A capability the
platform itself does not ship on a supported OS is the platform's gap, never the "narrower, inherent
platform boundary" a plugin may declare — the plugin still owes a portable path.

That input carries two axes, model provider and subscription plan. The *host surface* a consumer
runs in — CLI, Desktop, an IDE extension, web, mobile — is a third, read separately from
[Platforms and integrations](https://code.claude.com/docs/en/platforms) and the per-host pages it
indexes, cited and never restated (verified 2026-08-10, [recorded gate runs](#recorded-gate-runs)).
It is a distinct axis because a host can withhold the plugin system itself rather than one
capability, and where no plugin loads there is no portable path for one to owe. Host-surface absence
is therefore neither a plugin defect nor a boundary a plugin may declare: the OS rule above governs
the three operating systems, and a plugin answers for its behavior on every host that loads it,
never for the hosts that do not.

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

## Instruction economy

Every standing instruction this marketplace ships — a CLAUDE.md line, a hook that corrects model
behavior, a skill's always-loaded listing text — is a per-session tax on every consumer, paid
whether or not the instruction ever fires. Official doctrine is explicit: "CLAUDE.md is loaded
every session, so only include things that apply broadly… For each line, ask: 'Would removing this
cause Claude to make mistakes?' If not, cut it," and "If Claude already does something correctly
without the instruction, delete it or convert it to a hook"
([best-practices](https://code.claude.com/docs/en/best-practices), verified 2026-08-10). Anthropic
applied the same doctrine to Claude Code itself, removing over 80% of its system prompt for the
Opus 5 / Fable 5 generation with no measurable loss on its coding evaluations
([The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models),
verified 2026-08-08). Four rules follow:

- **Evidence-gated additions.** A new standing instruction requires observed, repeated stumble
  evidence against the current model — the same failure seen more than once — never anticipation
  of a failure a past model had. Name the evidence where the instruction is added (PR body or an
  adjacent comment). Anticipatory instructions are the veteran-engineer failure mode: they encode
  the last model's weaknesses as the next model's ceiling.
- **Generation-triggered ablation.** Instructions are disposable per model generation. At each
  frontier model release, re-audit standing instruction surfaces against the new model
  (`claude-config:audit-instructions` for the static text-vs-doctrine pass;
  `claude-config:unhobble` for the empirical bare-baseline experiment) and delete what the model no
  longer needs. The trigger is the model release, not the calendar.
- **Evals outlive instructions.** Per-skill evals are the durable asset across this churn: keep and
  extend them until a model generation saturates them, then replace them with evals derived from
  newly observed struggles. Expect an eval to outlive the instructions it graded by roughly one to
  three model generations. Deleting an instruction never deletes its eval; the eval is how the next
  deletion round proves itself safe.
- **The durable tier is exempt.** Deterministic policy hooks (gates that enforce team or safety
  policy regardless of model capability) and team conventions checked into git are the officially
  carved-out durable instruction tiers. Classify a hook honestly before keeping it: a hook that
  enforces policy survives ablation; a hook that corrects model behavior is an ablation candidate
  like any prose instruction.

### Classifying a hook

This is the standing rubric for the classification the durable-tier rule requires. It was first
applied across this marketplace's 44 wired hook entries in the 2026-08 audit (issue #2021), and it
is the pass any consumer repo can run over its own hook surface at each generation-triggered
ablation. Score every wired hook entry on two independent axes:

- **Mechanism** — what the hook does structurally: deny-gate (blocks a tool call), context-injection
  (adds text to the model's context), deterministic-transform (edits an artifact, model not in the
  loop), or notification/infra (output goes to a human or a log, not the model).
- **Class** — why the hook exists: **policy** (an invariant you would keep with a perfect model —
  security, team convention, irreversibility protection); **behavioral** (corrects model behavior a
  better model gets right unaided); or **hybrid** (both — name the split explicitly, because the
  remediation is a trim or a narrowing, never whole-hook deletion).

Mechanism never implies class. A context-injection can be pure policy (relaying a linter's measured
findings), and a deny-gate can be behavioral (a block whose predicate is a guess about model
competence rather than a checkable invariant).

One nuance does the most work: a hook with a *behavioral purpose* but a *non-derivable ground-truth
oracle* — diffing written flags against a binary's live `--help`, globbing the live plugin tree
after a rename, querying git history for a path's disappearance — is a keep, not an ablation
candidate. It corrects hallucination with machine ground truth no model can know unaided, so "it
corrects the model" alone is never the delete criterion; "the model could derive this itself" is.

Remediation applies the same evidentiary rigor to removal that **Evidence-gated additions** above
requires for addition: config-disable first where a kill switch exists, delete only with recorded
rationale; a hybrid gets its behavioral surface trimmed while its policy residue stays; and the
security carve-out below overrides every row of the rubric.

Model-capability claims never relax the security posture. Injection resistance in current models is
measurably better but bounded and hedged in the primary sources; the plugin-acceptance security
review's deny-by-default stance on egress and trust delegation is policy, not a model-era
workaround, and stays regardless of model generation.

The complementary task-design doctrine — describe the task, guardrails, and exit criteria, give the
model a way to verify its own work, and skip step-by-step procedure — is already this marketplace's
encoded practice: the `verification`, `planning` (goal conditions), `tdd`, and `testing` plugins are
its implementation, and need no new mechanism on its account.

## Fresh-eyes checkpoints

A context that produced work is structurally the weakest place to judge that work: the reasoning that
made a mistake plausible is still active, so a self-check inherits the bias. A fresh-context (non-fork)
subagent — generic or named — removes it: it starts in its own fresh context window, blind to the
reasoning under review. A fork does not: it inherits the parent session's full conversation history, so
it carries the same bias forward
([subagents](https://code.claude.com/docs/en/sub-agents), verified 2026-08-10).
Upstream now states the doctrine, not only the mechanism: a fresh context "improves code review
since Claude won't be biased toward code it just wrote", and a verification subagent exists "so the
agent doing the work isn't the one grading it" — a reviewer in a fresh subagent context "sees only
the diff and the criteria you give it, not the reasoning that produced the change"
([best practices](https://code.claude.com/docs/en/best-practices), verified 2026-08-10). This
section is the authoring-time form of that guidance, applied where an invoker cannot be relied on
to remember it.

The rule: **a skill step whose output judges work produced in the same context delegates that judgment
to a fresh-context (non-fork) subagent** — generic or named; what the rule requires is the fresh
context window, not a fork. Mandatory in the skill's design, not left to the invoker to remember.
Three bias classes name the trigger:

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
([subagents](https://code.claude.com/docs/en/sub-agents), verified 2026-08-10), which is exactly the
independence the checkpoint buys. A skill may prefer an installed **named agent** on the next rung —
but only when the named-agent bar below is met, and the site always states the generic fallback
(presence-gate-plus-fallback, [seam phrasing](conventions/seam-phrasing/README.md)). The top rung, for
high-stakes verdicts where correlated model blind spots are the risk, is a **cross-vendor advisor**
when one is installed — same presence-gate shape, same generic fallback.

Those rungs are one choice among the platform's parallelism surfaces;
[run agents in parallel](https://code.claude.com/docs/en/agents) is the canonical upstream comparison
of all of them (verified 2026-08-10). Why the fleet takes the subagent rung today rather than agent
teams or cross-session messaging is recorded once in the [gate runs](#recorded-gate-runs) — re-derive
from that table's triggers instead of re-arguing it at a checkpoint site.

### Inline-template conventions

A dispatch prompt at any rung:

- says **fresh-context** work is expected — the worker judges the artifact it is handed, with no
  access to the reasoning that produced it;
- hands over the **artifact, not the story** — the diff, file, or plan itself, never the authoring
  session's rationale, which would re-import the bias being removed;
- **degrades when absent** — a preferred named agent or advisor that is not installed routes to the
  generic fresh-context subagent, never to a command that may not resolve; and
- **bounds what counts as a finding** — correctness and the stated requirements, everything else
  optional. Upstream names the failure this prevents: "A reviewer prompted to find gaps will
  usually report some, even when the work is sound, because that is what it was asked to do", and
  chasing all of them "leads to over-engineering"
  ([best practices](https://code.claude.com/docs/en/best-practices), verified 2026-08-10). An
  unbounded adversarial prompt buys noise at the same price as judgment.

### Named-agent bar

A named agent is earned, not default: **the same worker with the same instructions dispatches from
multiple sites (or repeats via description-triggered direct invocation) AND a model pin, an effort
pin, or an enforced tool restriction is load-bearing.** Otherwise the generic subagent with inline instructions
is the simpler, equally independent form. On tool cages: an allowlist that includes Bash bars
Edit/Write and recursive spawning but is **not read-only** — Bash can write; state what the cage
actually enforces, never "read-only" ([plugin agents support `tools` frontmatter](https://code.claude.com/docs/en/plugins-reference),
verified 2026-08-10).

### Model tiers

The ladder is relative to the session: **a consequential verdict runs at the session-model tier or
above, never below; tedious or mechanical preparation may drop one tier.** The heavy default must be
explicit — an agent definition that omits `model` defaults to `inherit`, the main conversation's
model ([subagents: model resolution](https://code.claude.com/docs/en/sub-agents#choose-a-model),
verified 2026-08-10; frontmatter accepts `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or
`inherit`). Consumers hold one global override knob: `CLAUDE_CODE_SUBAGENT_MODEL`, set via the
settings `env` map, which overrides both the per-invocation `model` parameter and frontmatter —
except at the value `inherit`, which since v2.1.196 means normal resolution rather than forcing the
session model, so the knob has an off position as well as an on one
([model config: environment variables](https://code.claude.com/docs/en/model-config#environment-variables),
verified 2026-08-10; `env` applies to every session and spawned subprocess,
[settings](https://code.claude.com/docs/en/settings), verified 2026-08-10). There is no per-plugin
model seam — plugin `userConfig` declares only generic typed options with no model semantics
([plugins reference: user configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration),
verified 2026-08-10) — so doctrine travels by authoring-time conformance in each skill, not runtime
configuration.

Tier-to-model mapping, dated 2026-08-04 (recheck trigger: a new Claude model family reaches GA, or
the session default model changes):

| Tier | Model (2026-08-04) |
|---|---|
| Consequential verdict (session tier or above) | The active session model; under the fleet's current `opus[1m]` pin that is Opus 5, with Fable 5 the rung above |
| Mechanical prep, one tier down | Sonnet 5 |
| Bulk mechanical sweeps | Haiku 4.5 |

Row 1 is relative by construction — the invariant above makes the ladder relative to the active
session, so a session already running Fable 5 has no rung above and dispatches consequential
verdicts at its own tier. The named models are the resolution under the fleet's pinned session
default (`opus[1m]`, an alias): `opus` resolves to Opus 5 on the Anthropic API — "for complex
agentic coding and enterprise work" — while Fable 5 is "the most capable model in Claude Code",
positioned for tasks larger than a single sitting rather than for harder verdicts at ordinary
length. Opus 4.8, the previous row-1 entry, is now a legacy
model. Rows 2 and 3 re-verify unchanged: Sonnet 5 and Haiku 4.5 remain the current Sonnet and Haiku.
The trigger itself re-tested negative: a further family, Claude Mythos 5, now appears upstream but
has not fired it — Mythos "is not generally available", offered invitation-only to approved
customers under Project Glasswing, so no lane may reach for it. The figures behind the cost ordering
below are upstream-owned
([pricing](https://platform.claude.com/docs/en/about-claude/pricing)) and are not restated here.
([model config](https://code.claude.com/docs/en/model-config),
[models overview](https://platform.claude.com/docs/en/about-claude/models/overview), both verified
2026-08-10.)

That ladder is a cost ordering, and one capability does not travel down it: **interleaved thinking —
a thinking block between tool calls rather than only before the first and after the last.** Claude Code
models it per model, as the `interleaved_thinking` capability value
([model config: customize pinned model display and capabilities](https://code.claude.com/docs/en/model-config#customize-pinned-model-display-and-capabilities),
verified 2026-08-10; a pinned model's unlisted capabilities are disabled). The per-model roster is
upstream-owned — resolve it at
[thinking: interleaved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#interleaved-thinking),
which today states that interleaving is automatic on every model supporting adaptive thinking with
no beta header, and that Claude Haiku 4.5 does not support it (verified 2026-08-10, corroborated by
the model roster's adaptive-thinking column; recheck trigger: a new Haiku generation reaches GA, or
that page's per-model sentence changes).

The dispatch consequence, phrased as capability rather than family name so it survives an alias
moving under it: **require interleaving only where extended reasoning between tool results is
load-bearing — a mid-sweep judgement that has to change what gets called next. A task that chains
calls, or that reasons over its results at the end, does not need it.** The boundary is much
narrower than the capability's name suggests, and the same page draws it: "Consecutive tool calls do
not require interleaved thinking. Claude can chain tool calls with or without interleaved thinking;
interleaving changes where thinking blocks appear between tool calls, not whether tool calls can
chain." What the capability adds is a thinking block at that seam, so what its absence removes is
deliberation *at that point* — not the tool result from context, and not the ability to act on it.
So the bottom tier row stands for bulk mechanical sweeps and for straightforward triage or research
passes that decide at the end; the case it does not cover is a fan-out whose worth is deliberating
partway through, where the next call must change because of what the last one returned.

The **dispatch-seam** tier enforcement is structural at two binding sites:
`plugins/implementation/agents/implementer.md` and
`plugins/implementation/agents/phase-verifier.md` (both bind the loop-lane convention's strong-tier
current alias; raise the pair together, and note frontmatter binds a floor — the session-relative
raise above it stays a per-invocation override at the dispatch site). That pair is the seam, not the
recheck list: the trigger above re-audits **every** agent-frontmatter `model` value in this
repository, which `git grep -n '^model:' -- 'plugins/*/agents/*.md'` enumerates rather than any
list restated here.

That floor is the consumer's to lose. An enterprise `availableModels` allowlist applies "everywhere
a user can specify a model" — frontmatter pins included — and where this document once recorded the
blocked-pin branch as unresolved upstream, upstream now resolves it, per surface and differently for
each. A blocked **subagent** override "falls back to the subagent's inherited model … rather than
failing the request", except that on the Anthropic API and Claude Platform on AWS a blocked *family
alias* instead follows the substitution rule and runs "on the newest permitted version of its
family" — a v2.1.222 change the page dates, before which the alias fell back like any other blocked
value. A blocked **skill or command** override behaves differently again: "Claude Code ignores the
override, including a blocked family alias, and the skill or command runs on the session model."

The earlier derivation's conclusion survives its replacement. A blocked subagent alias can still
land **below** the session — session on Opus 5, lane pinned `opus`, allowlist permitting only an
older Opus — and a blocked *cheap* pin lands on the inherited model, which is the session's and
therefore not cheap. So the tier invariant above is still not self-enforcing for a subagent lane: it
may depend on its pin in neither direction, and no error is raised either way. Only the skill and
command branch is now pinned down, and it degrades upward-bounded — to exactly the session model,
never below it. A design whose correctness needs a tier still needs a mechanism that is not a
frontmatter pin
([model config: restrict model selection](https://code.claude.com/docs/en/model-config#restrict-model-selection),
[sub-agents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model), both
verified 2026-08-10; recheck trigger: either page's blocked-override behavior for a subagent,
skill, or command changing).

### Effort tiers

Effort routes per lane the way model does. Skill and subagent frontmatter `effort` overrides the
session level while that lane is active — but never the `CLAUDE_CODE_EFFORT_LEVEL` environment
variable — and accepts all five level names including `max`; a level the active model does not
support falls back to the highest supported level at or below it
([skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference),
[model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level),
verified 2026-08-10). The ladder itself — level names, per-model availability, per-model defaults —
is upstream-owned: resolve it from the model-config page at decision time, never from this document.

What a pin actually buys is bounded by how allocation works: thinking is adaptive, so the model
"evaluates each request and decides for itself whether to think and how much", and the caller sets
an intent and optionally the effort while the model "allocates reasoning where it judges reasoning
will help" ([steering thinking](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost),
verified 2026-08-03). A lane pin is therefore a posture, never a switch — a lane pinned `low` still
thinks where the model judges thinking earns its cost, and a turn carrying no thinking is that
mechanism working rather than a pin misfiring. Authoring conformance follows the posture: pin the
lane, then let allocation vary per request instead of writing prose that tries to force it uniform.

Lane rules, dated 2026-07-29 (recheck trigger: a model change on any pinned lane, or the
model-config effort table changes — the effort scale is calibrated per model, so the same level
name is not the same underlying value across models):

- **Consequential-output lanes with a frontmatter surface pin `high`** — verdicts, and research
  that feeds decisions, wherever the lane is a named agent or a skill doing that work in its own
  context. The pin exists so the lane does not silently degrade inside a session tuned down for
  cost (the environment variable still wins, per above). The pin is not relative: on a model
  whose own default sits above `high`, it caps the lane below that model's default — the recheck
  trigger above exists exactly for this. The reach is the mechanism's, not the rule's: a generic
  Agent-tool dispatch carries no effort control — the tool takes a per-invocation `model`
  parameter with no effort counterpart
  ([sub-agents](https://code.claude.com/docs/en/sub-agents), doc-silence corroborated by the live
  tool schema, 2026-07-29) — so it structurally inherits the session level and its floor is the
  session baseline; promoting such a lane to a named agent is how it gains the pin (a
  load-bearing effort pin satisfies the named-agent bar's pin clause). An orchestrator skill
  whose consequential work executes in generic dispatches is likewise out of reach: a skill-level
  pin governs the orchestrating conversation, and whether it propagates to subagents spawned
  while the skill is active is undocumented — treat propagation as unknown alongside the cache
  caveat below.
- **Bulk mechanical sweeps may pin `low`** — upstream pitches `low` for simpler tasks needing the
  best speed and lowest cost, "such as subagents", and lower effort spends fewer tool calls
  ([effort](https://platform.claude.com/docs/en/build-with-claude/effort)) — but not at the model
  ladder's own bottom rung, because the two ladders do not compose there. Effort is a per-model
  capability and Haiku has none: "Models not listed here do not support effort", and no Haiku
  appears in that table
  ([model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level)),
  which the model roster corroborates with adaptive thinking off for Claude Haiku 4.5
  ([models overview](https://platform.claude.com/docs/en/about-claude/models/overview), both
  verified 2026-08-10). The documented unsupported-level fallback above does not reach this case:
  it presupposes a supported level to fall back *to*, and here there is none. What the harness then
  does with the pin — ignore it, warn, or fail — is **undocumented, and unverified here**; the
  pages above establish the absent capability and nothing about the runtime handling, so no reading
  of them settles it. The rule does not rest on that gap: a lane wanting the cheapest tier takes it
  by model alone and omits the pin, because the dial it would be reaching for only exists one rung
  up.
- **Every other lane omits the pin** and inherits the session level: effort is a general
  preference, not a task-by-task decision
  ([choosing a model and effort level](https://claude.com/blog/claude-model-and-effort-level-in-claude-code)).
- **No lane pins `max` without eval evidence** — upstream warns it adds significant cost for
  relatively small quality gains and can lead to overthinking. A pin above `high` (e.g. `xhigh`)
  is a deliberate per-lane choice grounded in the target model's own recommended-levels guidance,
  never a reflex.
- **Effort is the first lever in either direction; steering prose is the second.** Upstream states
  the order plainly — set the effort level matching the lane's workload, then "add prompt guidance
  only if Claude's triggering still doesn't match your needs at that level" — and gives the
  rationale that lowering effort "is usually the better first lever, since it is a calibrated
  control rather than a wording-sensitive instruction"
  ([steering thinking: effort levels](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#effort-levels),
  verified 2026-08-03). Both directions: shallow output from a pinned-`low` lane raises the lane's
  effort rather than prompting around it, and a lane thinking more than the work needs lowers the
  pin before any prose telling the model to think less — upstream states that reduce direction
  outright and warns it "may reduce quality on tasks that benefit from reasoning". A lane that must
  hold its level for latency is the one case that reaches for steering prose first; it then owes
  the measurement upstream asks for — a representative sample run with and without the guidance,
  compared on trigger rate, output tokens, latency, and quality — because steering effectiveness is
  wording-sensitive in a way a level is not. Authoring a lane's prose against its own pin, in
  either direction, is the inversion this rule exists to catch.
- **Cache caveat**: changing effort between requests invalidates cached prompt prefixes, so a
  skill pin firing mid-session is expected to cost the main conversation's cache (harness-side
  request assembly unconfirmed), while a subagent pin is scoped to the subagent's own requests —
  treat skill-lane pins as cache-costly in cost-sensitive loops. State the outcome and not the
  mechanism: the platform page and the harness page agree that an effort change forces a full
  re-read but describe *why* differently, so an explanation that picks one is asserting more than
  either source supports. Two corollaries follow. Setting a lane's effort explicitly to the model's
  own default is a no-op that "does not break the cache", so a pin that merely documents the
  default costs nothing. And **per-message steering is the cache-safe escape hatch** — guidance
  appended to the newest user message "leaves earlier cache breakpoints intact, where a
  configuration or effort change does not", which is what makes a skill's invocation-time
  instructions cheaper than a mid-session pin. The convention that falls out, and the reason a lane
  pin is a design-time choice rather than a per-task one: pick the level once and keep it, steer
  per message when one turn needs more or less, and move the configuration only at natural breaks
  between tasks ([steering thinking: prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#prompt-caching),
  verified 2026-08-03). The harness page states the same convention in its own words — "Pick your
  model and effort level at the top of a session, then save `/compact` for natural breaks between
  tasks" — and adds the interactive consequence a plugin author cannot see from the platform page
  alone: once a conversation has started, Claude Code "shows a confirmation dialog before applying
  an effort change that would invalidate the cache", so a mid-session change is a prompt the
  consumer must clear rather than a silent cost. The same section independently corroborates the
  no-op corollary above — a change resolving to the level already in effect "skips the dialog and
  keeps the cache" ([prompt caching: changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level),
  verified 2026-08-10; recheck trigger: a Claude Code release changes the effort-change
  confirmation flow, or that section is reworded).

**Effort is one dial of two, and the other is not an effort value.** The `thinking` parameter decides
whether Claude reasons in thinking blocks; `effort` decides how hard the whole response works,
"which in adaptive mode includes how often and how deeply it thinks". Upstream states the resulting
trap outright — "Don't pass `adaptive` as an `effort` value: `adaptive` is a thinking mode, not an
effort level" — and a frontmatter `effort` field is exactly where that trap is reachable, because the
two dials share vocabulary. The second consequence bounds what any pin can promise, in upstream's own
words: "**You need a hard ceiling on spend:** use `max_tokens`. Effort is soft guidance; `max_tokens`
is a strict limit." Read what that limit bounds before reaching for it. `max_tokens` is a request
parameter capping one response's output — it "includes all thinking Claude generates in the current
turn" — so it binds per response and constrains neither input and cache reads nor the further
requests an agentic lane makes. **And no documented frontmatter field reaches it.** Those fields set
the model and the effort level, and a subagent adds `maxTurns`, which bounds agentic turns rather
than tokens and has no skill-frontmatter counterpart; neither field list carries a token cap, because
the parameter belongs to the API request that the lane-pin surface does not assemble. So the rule
this section can actually state is narrower than the quote: a lane wanting to spend less lowers
`effort` knowing it is guidance, and a hard cap has to be imposed by whoever builds the request
([thinking and effort](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-effort),
[subagent frontmatter](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields), and
[skill frontmatter](https://code.claude.com/docs/en/skills#frontmatter-reference), all verified
2026-08-03; recheck trigger: the accepted `effort` value set changes on the model-config or effort
page, or either documented frontmatter field list gains a token cap). Checking the value set mechanically stays deferred: a lint rule's source of truth is
the harness's own accepted-value list, which this section deliberately does not restate.

Session-level effort is the consumer's own knob, out of plugin scope: `low` through `xhigh`
persist via the `effortLevel` setting, while `max` and `ultracode` are session-only — `max` is
durable only through the `CLAUDE_CODE_EFFORT_LEVEL` environment variable. Plugins never set
session effort.

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
authoritative self-updating master list. Claude Code pages load-bearing for this document, each
re-fetched 2026-08-10 and confirmed to still carry the topics named beside it (the
`melodic-software/standards` entry below is not a Claude Code page and was not re-checked on that
date):

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
