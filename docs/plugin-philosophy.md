# Plugin philosophy

## Contents

- [Design boundary](#design-boundary)
- [Naming](#naming)
- [Skills are processes](#skills-are-processes)
- [Native-first](#native-first)
- [Component stances](#component-stances)
- [Two-lane convention posture](#two-lane-convention-posture)
- [Configuration ownership and scope](#configuration-ownership-and-scope)
- [One owner per value](#one-owner-per-value)
- [Setup is explicit and repeatable](#setup-is-explicit-and-repeatable)
- [Prerequisites and failure behavior](#prerequisites-and-failure-behavior)
- [Convention registry](#convention-registry)
- [Cross-platform contract](#cross-platform-contract)
- [Evidence and validation](#evidence-and-validation)
- [Instruction economy](#instruction-economy)
- [Fresh-eyes checkpoints](#fresh-eyes-checkpoints)
- [Delegation mechanics](#delegation-mechanics)
- [Authoritative references](#authoritative-references)

This is the durable design policy for plugins in this marketplace. The
[migration playbook](migration-playbook.md) applies it to migration and release work; the
[plugin artifact protocol](plugin-artifact-protocol.md) defines the shared artifact contract used by
lifecycle plugins.

## Design boundary

A plugin is a reusable, independently useful vertical slice of one cohesive capability. It must work
outside the repository and organization that produced it. Publisher metadata may identify its source;
runtime behavior must not depend on publisher names, organization-specific environment variables,
repository names, absolute machine paths, or an undocumented consumer layout. `melodic-software/standards`
`conventions/engineering/shareable-artifact-design.md` owns the artifact-agnostic form of this
doctrine: consumer-agnostic behavior, externalized consumer-varying configuration, consumer tiers,
explicit adoption. This document specializes it for Claude Code plugins and adds only what is
plugin-specific. [Hardcoded consumer specifics](#hardcoded-consumer-specifics) routes the
machine-path and layout half to the audits that check it.

**Org-agnosticism** names the publisher half of that boundary, and it governs *tokens in shipped
content*, not only runtime behavior: the publishing organization's name, its marketplace id, its own
repository names, and publisher-prefixed configuration keys do not appear in a plugin's skill, agent,
or schema content. One use is sanctioned: a citation that *names a source rather than a target the
plugin acts on*, whether a documentation URL or a cross-plugin reference to this marketplace's own
published files, cited for a reader to consult. Whether that sanctioned citation is forfeited turns on the
target's owner: a skill instructed to fetch, poll, or write a **publisher-owned** file has made the
publisher a runtime dependency and is not conforming. A third-party documentation URL creates no such
dependency, so fetching one does not forfeit the citation. This rule reaches publisher-owned targets
only. For publisher-owned targets, distinguishing
an instruction to fetch from a citation offered for a reader remains genuinely hard, and this
statement does not settle it.
(`plugin.json` publisher metadata sits outside
this rule entirely, being neither skill, agent, nor schema content. Identifying the source is what
the manifest is for.)

A git config **vendor section that is not a publisher name** is the git-native place for a
convention any `git config --get` consumer must be able to read. We name such a section so it
collides with neither Git's own variables nor other popular tools', and document it. Pointer: for
third-party tool variables, see
[git-config(1) Variables](https://git-scm.com/docs/git-config#_variables). As of: 2026-09-08.
Recheck trigger: that paragraph being rewritten. Git already owns `worktree.*`
(`worktree.guessRemote`, `worktree.useRelativePaths`; Pointer:
[git-worktree(1) Configuration](https://git-scm.com/docs/git-worktree#_configuration). As of:
2026-09-08. Recheck trigger: git-config(1) adding a new `worktree.*` key), so a placement key
cannot live there. Popular tools typically name the section after the *tool* (`ghq.root`,
`git-town.*`, `lfs.*`, `wt.basedir`, `delta.*`, `hub.protocol`); a publisher-named key (`melodic.*`)
is still an org-agnosticism defect, and a plugin-named key (`source-control.*`) still couples
consumers to this marketplace's plugin identity. The worktree-placement key is therefore a
capability section that collides with neither Git nor those tools: `worktreeroot.path`
([ADR 0031](adr/0031-name-the-worktree-root-git-config-key-as-a-capability-section.md)). This ruling is git
config vendor sections only; it does not bind publisher-prefixed environment variables
(`MELODIC_*`), marketplace ids, or organization names in skill content.

Like the setup contract below, **this is a normative target, not a description of the fleet**.
Enforcement is the token classes in `scripts/org-agnosticism-tokens.txt`, one data file. Every
site either reads it or is a documented narrowing/extension of it:

- **fleet-id / fleet-key**: marketplace id, `melodic-software/github-iac`, and `MELODIC_*` keys,
  across every plugin skill `.md` (`scripts/validate-plugin-contracts.mjs`).
- **setup**: setup-skill files must not bind to a marketplace name (same validator).
- **autonomy**: a stricter extension covering the bare organization name and fleet repo names,
  scoped to the `autonomy` plugin (`plugin.json` `author` remains exempt).
- **github**: this plugin's markdown only, adding `melodic`, `medley`, and `pulumi`.
  `plugins/github/github.test.sh`'s "agnostic conformance" check is that extension, a sibling of
  that file's D4 zero-vendored-knowledge sweeps, not one of them. The validator fails if that
  test file is missing while the plugin exists, or if its regex drifts from the `github` class.
  An unknown class name in the token file is a hard error.

Agent content, schema files, and a fleet-wide bare organization name are **not gated**. That is a
deliberate narrowing of enforcement to the classes above, not an accident a green build absolves.
The independent `portability-lint` job stages a related publisher-token class in
`scripts/skill-portability-tokens.txt`; if that class activates it must consume or align with
`org-agnosticism-tokens.txt` rather than invent a third set. CI enforces that alignment via
`scripts/check-publisher-token-alignment.sh`.

Keep plugins horizontally decoupled:

- A plugin owns its skills, hooks, agents, scripts, dependencies, and state.
- It never imports files from a sibling plugin or discovers another plugin's installation directory.
- Cooperation uses a documented public interface: an artifact contract, an explicit invocation
  argument, or an optional namespaced skill invocation.
- Native manifest `dependencies` are reserved for hard requires: a plugin genuinely broken without
  its collaborator. Optional collaboration stays presence-gated with a documented fallback. The
  first versioned dependency brings the `{name}--v{version}` release-tag step
  (`claude plugin tag --push`) with it.
- Every plugin remains useful alone. If an optional collaborator is absent, use a documented fallback
  or report the missing optional capability clearly.
- Every cross-plugin reference is therefore either declared (the `dependencies` array above, which
  Claude Code installs automatically) or guarded behind an "if installed" check with the documented
  fallback. A bare unguarded cross-plugin reference is a defect.

This follows Claude Code's own distinction between standalone configuration and plugins: this
marketplace ships plugins because it distributes versioned capability to other people and projects.
Pointer: for when to use a plugin rather than standalone configuration, see
<https://code.claude.com/docs/en/plugins/overview#decide-whether-you-need-a-plugin>. As of:
2026-08-10. Recheck trigger: that section moves or drops the distinction. Namespaced skill
invocations are part of that isolation, not an implementation detail.

### Hardcoded consumer specifics

The rule is the first paragraph of [Design boundary](#design-boundary): no runtime dependence on one
machine's paths, one organization's repository names, or an undocumented consumer layout. A value
that varies per environment, operator, or consumer belongs in the consumer's own config layers
(`melodic-software/standards` `conventions/engineering/shareable-artifact-design.md`,
"Externalize what a consumer may decide"). This subsection is the doctrine owner; component-scoped
audits cite it instead of restating the rule:

- `plugin-quality:audit` recurring-concerns (per-component detection cues).
- `coupling:reduce` remediation catalog (code and document altitude).
- `harness-config:audit-permission-grants` (concrete home paths in permission grants only).

## Naming

A skill name is an imperative verb phrase; the plugin namespace supplies the object
(`/machine-health:audit`, `/source-control:commit`). Names compose into instruction sentences, such as
"/discovery:explore the module, then /planning:interview me", and one grammar keeps every name in
the marketplace predictable. This is a deliberate, documented deviation from the official authoring
guidance's gerund preference. We read that guidance as allowing action-oriented names and as
asking above all for one consistent pattern within a skill collection, which is what this section
supplies. Neither the guidance nor the Agent Skills specification requires one form, and Claude
Code validates no naming form (our probe: `claude plugin validate` 2.1.263 passed a non-conforming
name on 2026-09-10).

- **Pointer**: for skill naming, see
  <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#naming-conventions>
  and <https://agentskills.io/specification#name-field>.
- **As of**: 2026-09-10
- **Recheck trigger**: the guidance's list of names to avoid changes, the specification's example
  names change, or `claude plugin validate` starts rejecting a form.

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
(`worktree`, `pull-request`). Seven further documented exceptions: a single-skill vendor-CLI wrapper
repeats its tool name (`firecrawl:firecrawl`); a `-deep` suffix marks the heavier
isolated-execution tier of a sibling skill (`research`/`research-deep`); a knowledge router named by
its method's own literature term keeps that term when renaming would destroy recognized craft
vocabulary (`songwriting:object-writing`, `meter-prosody`, `song-form`, Pattison's terms); a
playbook router named by its source keeps the source's own identifier, because provenance is the
content's identity (`playbooks:boris`, `playbooks:fable-5`: one scheme, person or model alike);
and an object-pronoun qualifier is kept when the skill's defining boundary IS that the object under
test is the user themself (`education:quiz-me`: the `-me` distinguishes quizzing the human on
completed work from teach's in-workspace content quizzing, where a bare `quiz` would under-specify
the object the grammar normally delegates to the namespace); and an upstream utterance-interjection
is kept when the skill is a port whose typed phrase IS the mechanism, the user's own words at the
moment of use, and the upstream name carries cross-repo muscle-memory parity
(`discipline:wait-what`, the lost reader's literal interjection; an imperative paraphrase destroys
the zero-translation recall the command depends on precisely when its user is, by definition, lost,
and orphans users arriving from the upstream repo); and a user-typed initialism is kept when both
of those legs hold AND the skill ships a lane the fleet does not already have (`education:eli5`:
"ELI5" is the request as the user types it, and the name matches the upstream community plugin the
skill delegates to, so the word carries across marketplaces; the entry claims the namespaced
command only and makes no claim on bare `/eli5`). The recorded `bro` decline stands and this last
entry does not weaken it: `bro` asked for a second entry carrying nothing but `wait-what`'s
argument, for a capability this marketplace already shipped three times over, which is the blanket
sanction the closing rule forbids. `eli5` is admitted on what `bro` had none of: delegation to an
installed upstream skill, and a fixed visual-explainer lane (one idea per diagram, minimal text)
that no other skill here performs.
Every exception is an entry on this list, decided per name. A name class is never
blanket-sanctioned.

A plugin skill declares no frontmatter `name`. We rely on the directory supplying the name, and
the directory here is already the name the skill is documented and invoked by, so declaring it
restates the path in the character set the Agent Skills specification allows. The one effect we
would declare it for is the bare `/<name>` alias beside the namespaced command. Declare it only to
take that alias deliberately, and only with the value the directory already carries.

- **Pointer**: for the `name` field, see
  <https://code.claude.com/docs/en/skills#frontmatter-reference>; for the bare alias, see
  <https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name>.
- **As of**: 2026-08-10
- **Recheck trigger**: `name` stops being optional, or a declared `name` stops adding a bare alias. A `name` that *differs* from its directory is out of bounds here even though the harness
honors it: it would relocate the last command segment away from the directory that
`scripts/check-skill-leaf-names.sh` derives every leaf from, desynchronizing the cross-plugin
collision registry from the commands that actually resolve. That is why `skill-quality`'s check 1
fails a divergent `name` and only warns on a redundant one.
Never degrade a name to dodge a built-in command: plugin skills are namespaced and cannot collide
with other levels. When a name matches a built-in, the bare token still belongs to the built-in; the
namespaced form is the plugin skill's only command.

Resolution settled, **display** follows from it. We rely on a plugin skill keeping its plugin
prefix in autocomplete whether or not it declares `name`. A version-dependent display quirk for a
`name` that carries the plugin's own prefix is moot under this doctrine, because the only
sanctioned value is the bare directory name.

- **Pointer**: for the autocomplete fix, see the
  [changelog entry 2.1.216](https://code.claude.com/docs/en/changelog#2-1-216); for the prefixed-`name`
  quirk, see <https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name>.
- **As of**: 2026-08-31
- **Recheck trigger**: a fetch of the changelog or the skills page no longer matching this record.

The rest is observed in the client rather than documented
(2.1.225): the picker labels a row with the command it resolves, `/planning:plan` prefix and all,
and appends a bare alias in parentheses only when what you typed prefix-matches that alias, so a
skill declaring no `name` never renders the stuttering `/plugin:skill (skill)`. Re-observe before
relying on the parenthetical; the labeling itself follows from resolution and is the stable part.
Origin is spelled out again in the description: a plugin skill
renders as `(<plugin-name>) <description>`, a personal skill as `<description> (user)`, a project
skill as `(project)` or `(project, gitignored)` depending on whether it came from shared or local
settings, and a built-in, bundled, or MCP entry carries no marker at all. So a leaf name shared
across plugins is unambiguous to *invoke* and to *read*: its prefix distinguishes it in both
columns. Never rename to buy display uniqueness; spend the effort on the description's first clause
carrying the distinguishing object, since that column is what a reader actually scans.

## Skills are processes

A skill is a process: what to do, in what order, and when to stop. It is named for its verb
([naming](#naming)). The artifacts it writes and the external tools it drives sit behind
ports and adapters: the skill body names the step (render the frames, encode the film), and an
adapter does the work. Every port has a native default adapter, one the plugin ships, so the skill
works with nothing else installed; any other adapter is optional collaboration, presence-gated per
the [design boundary](#design-boundary).

An interface, a contract several adapters implement, exists only where two adapters exist or are
named. Until then the port is one function with one home and one signature, which is enough to add
the interface later without a rewrite.

Worked example: in `animation`, render is the one port with an interface (`render.py --backend`,
`native` by default, the adapter recorded in `render.json`), because HyperFrames and Remotion are
named second adapters. Decode and encode each have one home and one signature, and no interface.

## Native-first

Prefer a built-in native mechanism over any custom extensibility point: `userConfig`, a native
component type, a native lifecycle event. Build custom only on genuine misfit, and document the
misfit where the custom mechanism lives.

Built-in-first is a gate on every customization surface, not a preference. Before building
any custom config surface, a YAML concern file or a bespoke interface, first verify against the *current*
official Claude Code plugin documentation that no native mechanism (`userConfig`, a built-in
per-repo config surface) can host the need; the platform moves, so re-fetch
the documentation rather than trusting memory or an old summary. A custom extensibility point is the
fallback only where the built-in surface genuinely cannot support the need.

Adoption gate, applied per mechanism: adopt a native mechanism when it

1. fills a real existing gap, never adopted for novelty;
2. is stable and works cleanly, so experimental or immature features wait for maturity and are
   re-verified against current docs before each fleet audit; and
3. meets repository standards.

Never custom-build what a fitting native mechanism already covers; retire the custom channel when a
native one matures into fitness.

### Recorded gate runs

Platform surfaces the gate has been run against, recorded in the
[upstream-drift](conventions/upstream-drift/README.md#required-parts) record shape: each row holds
our verdict and reason in our words, the surface link (to the section the reason rests on) as the
pointer, the as-of date, and the recheck trigger. No row restates the page. Defer and decline are
results, not omissions; the trigger, never the date, is what obliges re-deriving a row.

| Surface (pointer) | Verdict | Decision and reason | Recheck trigger | As of |
|---|---|---|---|---|
| [Run agents in parallel](https://code.claude.com/docs/en/agents#choose-an-approach) | Adopt, as a citation | The upstream comparison of every way Claude Code runs multiple agents: subagents, agent view, agent teams, dynamic workflows. Adopted as the [dispatch ladder](#dispatch-ladder)'s canonical index and cited there, never restated, so the menu an author chooses from cannot go stale inside this file. | The page adds or drops a parallelism surface. | 2026-08-10 |
| [Feature availability](https://code.claude.com/docs/en/feature-availability) | Adopt, as a citation | Per-feature availability by model provider and subscription plan, the canonical input to the [cross-platform contract](#cross-platform-contract), cited there. We read its "platform" sense as the *provider* platform, never the host surface a consumer runs in; that axis is [Platforms and integrations](https://code.claude.com/docs/en/platforms), a separate row below. Copying it is barred by [evidence and validation](#evidence-and-validation): a provider matrix is exactly the volatile table that rule names. | A plugin proposes narrowing its platform support. Re-fetch the matrix then, never trust a restatement. | 2026-08-10 |
| [Agent teams](https://code.claude.com/docs/en/agent-teams#limitations) | Defer | Fails gate 2 and stops there: the feature is marked experimental and is off unless `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set, and its stated limitations cover nesting and resume. Defer rather than decline: the gap question stays open while the surface is opt-in and churning, and no plugin may depend on a team meanwhile. | The page drops the experimental warning or the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` requirement. | 2026-08-10 |
| [Cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging#when-to-use-cross-session-messaging), [availability](https://code.claude.com/docs/en/cross-session-messaging#availability) | Decline | Fails gate 1: we read the channel as one between sessions a person starts and steers, not a worker a skill dispatches. Re-derived 2026-10-01 after the provider leg of the prior trigger fired: same-machine messaging now reaches every provider, so portability no longer bars a same-machine rung, but gate 1 holds the verdict on its own. | The page stops scoping the channel to sessions you steer yourself, or a plugin surface (a manifest field, skill frontmatter, or a tool a skill may call) gains a way to start and address a session. | 2026-10-01 |
| [Sessions](https://code.claude.com/docs/en/sessions#what-a-resumed-session-restores) | Decline | Fails gate 1. Resume restores the prior conversation in full, which is the authoring story the [inline-template conventions](#inline-template-conventions) exist to withhold, so it is the opposite of a fresh-eyes rung rather than a missing one. A human session-management surface with no plugin-authoring interface. | `sessions` grows a plugin-facing interface: a manifest field, a tool, or skill frontmatter. | 2026-08-10 |
| [Platforms and integrations](https://code.claude.com/docs/en/platforms) | Adopt, as a citation | The upstream index of every host Claude Code runs in, covering CLI, Desktop, VS Code, JetBrains, web, and mobile, plus the integrations beside them. Adopted as the [cross-platform contract](#cross-platform-contract)'s canonical input for the host axis, which the already-adopted [feature availability](https://code.claude.com/docs/en/feature-availability) does not carry: that page's axes are provider and plan, scoped to what runs locally. The host axis matters because a host can withhold the plugin system outright rather than one capability: Desktop sessions in WSL 2, the mobile app, Desktop's Cowork tab, and the VS Code extension each limit plugins, terminal-only commands, or skills relative to the CLI, so a skill this fleet ships may simply not be reachable there (read each host's page from the index for the specifics). None of those four is restated in the contract. Only the rule they establish is. | `platforms` adds or drops a host, or `feature-availability` grows a host-surface axis, which would make this citation redundant. | 2026-08-10 |
| [GitHub Enterprise Server](https://code.claude.com/docs/en/github-enterprise-server#plugin-marketplaces-on-ghes) | Decline | Does not fail gate 1 by subject: it is a real plugin-distribution surface, and the only page in this run that names one. It fails on need. Nothing in this repo documents a GHES-hosted mirror or fork of this marketplace, and no README anywhere ships a full-git-URL install path, the form GHES requires. Census of the 65 plugin READMEs: 54 carry the literal `/plugin marketplace add melodic-software/claude-code-plugins`; 9 carry no install block; `dometrain` points at another github.com marketplace; and `github`, being marketplace-agnostic, uses the placeholder `<marketplace-owner>/<marketplace-repo>`. All of those are the same `owner/repo` shorthand, which we treat as resolving to github.com, correct for this marketplace, and the one place the finding could bite: a consumer redistributing the `github` plugin from a GHES-hosted marketplace would follow that README and silently resolve to github.com instead of their own host. Otherwise the GHES-specific obligations land on a consumer running their own instance, not on this marketplace: full git URL, `extraKnownMarketplaces` pre-registration, `hostPattern` allowlisting. | This repo documents a GHES-hosted mirror or fork, or any README gains an install path that is not `owner/repo` shorthand, a full git URL being the form that means a non-github.com host is in play. Also fires if `plugins/github/README.md` starts naming a concrete GHES-hosted marketplace. | 2026-08-10 |
| [Ultrareview](https://code.claude.com/docs/en/ultrareview#run-ultrareview-non-interactively), [pricing](https://code.claude.com/docs/en/ultrareview#pricing-and-free-runs) | Decline | Fails gate 1 for automated dispatch. Re-derived 2026-10-01 after the prior trigger fired (a non-interactive entry point now exists): each run is metered, and we read the page as treating the person who starts a run as the one consenting to its billing, so no skill may launch one on its own, and a person stays free to run it. Nor is `review:fanout` a custom rebuild of it that Native-first would retire: fanout normalizes many in-session finding producers into one ranked report, where this is one consented cloud run. | The page lets a run that Claude starts count as consent to its billing, or runs stop being metered. | 2026-10-01 |
| [Chrome](https://code.claude.com/docs/en/chrome) | Decline | Fails gate 1: a consumer-installed browser integration the platform ships itself, so a plugin has nothing to declare here and must not rebuild automation the platform already ships. Recorded rather than dismissed because the page only *looked* cited: the repo's sole reference is a `docs/en/browser` URL that now returns 404, inside `plugins/playbooks/skills/boris/vendor/SKILL.md`, a verbatim upstream baseline kept for drift detection, which is why it is deliberately not hand-edited here. | A plugin proposes shipping browser automation, or `/playbooks:update` refreshes the boris baseline and the stale slug persists. | 2026-08-10 |
| [Mods (hooks modules)](https://github.com/anthropics/claude-code/tree/main/mods) | Defer | Fails gate 2 and stops there. A mod is a plugin whose behavior lives in one `register(on, options)` hooks module running in-process. Anthropic's own `mods/README.md` marks the interface as unstable between releases; a mod you write is off by default behind the rollout gate `tengu_plugin_hooks_modules`, whose default is `false` and which `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` only overrides per process; and the feature has zero mentions in the official docs (all 197 pages via `llms-full.txt`) or in `CHANGELOG.md`, checked at Claude Code 2.1.278. Defer rather than decline: the surface is real and shipping, so the gap question stays open, and no plugin may depend on it meanwhile. Recorded in [ADR 0035](adr/0035-defer-claude-code-mods-with-five-go-criteria.md). | All five go criteria hold: a test mod loads with the enable flag unset, the official docs mention the feature, [#92533](https://github.com/anthropics/claude-code/issues/92533) is closed, the official docs state the throw and timeout semantics and the engine default on an uncaught throw is settled upstream (the generated `.d.ts` JSDoc already states the mechanism, so a JSDoc hit does not meet this), and the early-access warning is gone from `mods/README.md`. Commands and expected outputs: [go-no-go.md](upstream/claude-code-mods/go-no-go.md). Any one failing is no-go. | 2026-09-19 |
| [Checkpointing: bash changes](https://code.claude.com/docs/en/checkpointing#bash-command-changes-not-tracked), [subagent edits](https://code.claude.com/docs/en/checkpointing#subagent-edits-not-restored) | Decline | Nothing to adopt, and the reason is the outcome: `/rewind` cannot be a mutating skill's undo story, because checkpoints do not cover bash-command changes or the edits of most subagents. The restored carve-out is narrow, covering only a `context: fork` skill running in the foreground, so a skill that mutates through a shell script or a background worker states a git-based rollback and never leans on `/rewind`. | The limitations section drops either the bash-command or the subagent exclusion. | 2026-08-10 |

## Component stances

> **Staleness disclaimer.** The platform changes constantly. Each row states our stance in our
> words; its component link is the pointer, and its as-of date is when the stance was last derived
> from that page. Always re-fetch the current page before acting on a row; never trust this table
> alone. A fetch that diverges from a row is that row's recheck trigger: re-derive the row and
> refresh its as-of date with the outcome. The
> [upstream-drift convention](conventions/upstream-drift/README.md) owns this record discipline.

| Component (pointer) | Stance | Rationale and constraints | As of |
|---|---|---|---|
| [Skills](https://code.claude.com/docs/en/skills) | Primary surface | The default unit of capability. Newer frontmatter is adopted case-by-case through the adoption gate: `paths`, `context: fork` (+ `agent`), `arguments`, skill-scoped `hooks` with `once`, and `model`, which we use only as a per-turn override, including for a forked subagent. Pointer for `model`: the [frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). Recheck trigger: that row changes what `model` accepts, or auto mode stops keeping the session model. | 2026-09-29 |
| [`commands/`](https://code.claude.com/docs/en/plugins/components#commands) | Prohibited | Superseded by skills upstream; every new capability goes in `skills/`. Existing flat commands migrate to skill directories. | 2026-07-17 |
| [Agents](https://code.claude.com/docs/en/plugins/components#frontmatter-fields-in-plugin-agents) | Adopt on need | Plugin agents do not support `hooks`, `mcpServers`, or `permissionMode` (security restriction). Design within that limit rather than working around it. | 2026-07-17 |
| [Workflows](https://code.claude.com/docs/en/workflows#distribute-a-workflow-in-a-plugin) | Adopt on need | Native and not experimental: a script in `workflows/`, or wherever the `workflows` manifest field points (that field replaces the default scan), runs as a plugin-namespaced `/plugin:name` command. Availability, not maturity, is the constraint: workflows are paid-plan-gated, a consumer can switch them off (`disableWorkflows`, `CLAUDE_CODE_DISABLE_WORKFLOWS`), and an org can disable them fleet-wide in managed settings; so, as with `bin/`, never make a workflow the only path to a capability. Not "Wait": the [deferred workflow engines](adr/0020-defer-three-medley-surfaces-with-explicit-recheck-triggers.md) are a named candidate carrying a live trigger, so the gap is identified rather than hypothetical. None ship in this fleet today. | 2026-07-27 |
| [Hooks](https://code.claude.com/docs/en/hooks) | Adopt on need | Exec form (`args`) is mandatory wherever `${user_config.*}` appears, because shell form errors since v2.1.207; otherwise read the `CLAUDE_PLUGIN_OPTION_<KEY>` mirror. On Windows, exec form launches an executable file (a `.exe`, for example) directly with the `args` array and no shell, so a shebang script or a `.cmd`/`.bat` shim is not a `command`, and neither is a bare `bash`, `sh`, `python`, or `python3` (a failed launch is non-blocking, so a guard then enforces nothing). Shell form with `"shell": "bash"` stays legal where no `${user_config.*}` appears; every plugin hook row uses exec form, `"command": "node"` with the script path in `args`, except the guardrails and disk-hygiene SessionStart node notice rows and the harness-ops hook-failure-audit Stop row, which run in shell form with `"shell": "bash"` because they must work when `node` is missing. `node` must be on `PATH`, and we do not assume a Claude Code install brings it (pointers: [Exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form), [Install with npm](https://code.claude.com/docs/en/setup#install-with-npm)). We treat a hook that cannot start as a guard that enforced nothing, with the transcript notice as the only signal (pointer: [Other exit codes](https://code.claude.com/docs/en/hooks#other-exit-codes)). `scripts/check-hook-exec-form.sh` rejects a bare name other than `node`. `scripts/check-exec-form-windows-probe.sh` rejects a script path used as `command`; its non-Windows skip does not authorize converting `.sh` rows. The record is [Windows exec-form probe](#windows-exec-form-probe). Hooks modules ("mods"), the in-process TypeScript hook form, are deferred: see the mods row under [Recorded gate runs](#recorded-gate-runs) and [ADR 0035](adr/0035-defer-claude-code-mods-with-five-go-criteria.md). | 2026-09-29 |
| [MCP servers](https://code.claude.com/docs/en/mcp) | Adopt on need | Clears the plugin-acceptance security review for egress and trust delegation. Also the only component type that can cost a consumer their prompt cache: every other kind only appends to the request, while enabling or disabling a plugin that provides an MCP server forces a full re-read whenever the server's tools load into the prefix instead of being deferred by tool search (pointer: [actions that invalidate the cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache)). | 2026-08-10 |
| [LSP servers](https://code.claude.com/docs/en/plugins/components#lsp-servers) | Adopt on need | Consumer must have the language-server binary; declare the prerequisite per the failure-behavior rules. | 2026-07-17 |
| [Output styles](https://code.claude.com/docs/en/plugins/components#themes-and-output-styles) | Adopt on need | No additional constraints. | 2026-07-17 |
| [`bin/`](https://code.claude.com/docs/en/plugins/components#executables) | Decline | claude.ai organization plugin sync rejects a plugin with a top-level `bin/` (#5850), and `scripts/check-plugin-manifest-presence.sh` fails any plugin that adds one. Put executables under `scripts/` and invoke them via `${CLAUDE_PLUGIN_ROOT}/scripts/`. Bare-name invocation was never dependable either: `PATH` delivery is per-session and can silently fail ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066)), and a `bash "…/x"` invocation does not match a `Bash(x:*)` allow rule. | 2026-07-17 |
| [Plugin `settings.json`](https://code.claude.com/docs/en/plugins/components#default-settings) | `agent` prohibited by default | Supports only `agent` and `subagentStatusLine`. `agent` takes over the main thread, a consumer-hostile default for a marketplace plugin; any exception requires documented justification in the plugin README. | 2026-07-17 |
| [Monitors](https://code.claude.com/docs/en/plugins/components#monitors) | Wait | Experimental (`experimental.monitors`); interactive-CLI-only, unsandboxed at hook trust level, no `${user_config.*}` and no `CLAUDE_PLUGIN_OPTION_*` in monitor processes; keep running after mid-session disable. Re-verify before each audit. | 2026-07-17 |
| [Themes](https://code.claude.com/docs/en/plugins/components#themes-and-output-styles) | Wait | Experimental (`experimental.themes`); schema may change between releases. Re-verify before each audit. | 2026-07-17 |
| [Channels](https://code.claude.com/docs/en/plugins/components#channels) | Wait | No longer carries an official experimental label, but fails the adoption gate today: no fleet gap it fills. Re-verify before each audit. | 2026-07-17 |
| [Dependencies](https://code.claude.com/docs/en/plugins/dependencies) | Adopt on need (hard requires only) | See the design boundary: hard requires only, semver-constrained, released via `{name}--v{version}` tags. None exist in this fleet today. | 2026-07-17 |

### Windows exec-form probe

`scripts/check-exec-form-windows-probe.sh` rejects an exec-form `command` that is not a real Windows executable ([#3686](https://github.com/melodic-software/claude-code-plugins/issues/3686)). It does not rewrite rows. A `.sh` path, a `.cmd`/`.bat` shim, or bare `bash` as `command` stays illegal. `scripts/check-hook-exec-form.sh` keeps rejecting bare `bash` with the script in `args`. Every shipped hook row is exec form, except the three shell-form rows named in the Hooks row above: `"command": "node"` with `hooks/exec-bash.mjs` (canonical `lib/exec-bash.mjs`, copied by `scripts/sync-exec-bash.sh`) and then the script. The launcher finds Git Bash and never `System32\bash.exe`. A default-off option is `--require-true NAME` (exit 0 unless `CLAUDE_PLUGIN_OPTION_NAME` is `true`). A default-on option is `--run-if-unset-or-true NAME` (exit 0 only when that variable is set to something other than `true`). Skill-frontmatter `args` is a YAML sequence, one element per argument.

- **Decision:** every exec-form `command` is a real Windows executable (`node`), never a shebang script, a `.cmd`/`.bat` shim, or bare `bash`, and no row relies on a shell or on the `shell` field while `args` is set. If a Windows spawn of that shape drops `args` or the process image is `bash.exe`, the fleet sweep stops.
- **Pointer:** for exec form on Windows, see <https://code.claude.com/docs/en/hooks#exec-form-and-shell-form> (read from the raw `.md`, 330,813 bytes, SHA-256 `57e3b47d55acfbae3dcdc112866c8c0f75528d8b5c4fca9bfcdaa904d4728218`); for the args drop, see [anthropics/claude-code#90495](https://github.com/anthropics/claude-code/issues/90495), open as of this date.
- **As of:** 2026-09-28.
- **Recheck trigger:** the hooks page changes what exec form requires of `command` on Windows, stops ignoring `shell` when `args` is set, or #90495 closes.

On a non-Windows host the spawn half prints a `SKIP` line and exits 0 when the row spellings are clean. That skip is fail-soft: it does not show that #90495 is absent, and it does not authorize converting `.sh` rows. On Windows the script spawns `node.exe` (a PE image, not a `.cmd`) with an args array and a stdin payload. A missing sentinel or a `bash.exe` image exits 1 with `ARGS-DROP` and the sweep stays stopped. `EXEC_FORM_WINDOWS_PROBE_LIVE=1` adds an opt-in `claude` hook run; without `claude` on `PATH` that half also skips fail-soft.

## Two-lane convention posture

A plugin must not arrive at an arbitrary consuming repo carrying pre-prescribed conventions. A
convention baked in as a fixed default, whether a branch-naming grammar, a commit structure, or a
directory layout, is a hardcoded assumption that the consumer's practice will never differ from the plugin's;
that is the definition of a dependency, and dependencies are externalized and abstracted, not shipped
as defaults. This governs every plugin and every convention, not one class. Two lanes hold:

1. **Non-conflicting good-practice defaults.** A shipped default is legitimate only when it is a
   good-practice value that cannot conflict in *any* repo the plugin drops into. This lane is narrow:
   most conventions a consumer already holds an opinion on (Conventional Commits in a repo that does
   not use them, for instance) do not qualify, because dropping the plugin in would then impose the
   wrong convention.
2. **Discover via setup, externalize as configuration.** In the general case the plugin's setup
   action or skill discovers the consuming repo's conventions, such as branch naming, commit
   structure, and patterns, and externalizes them as configuration extensibility points rather than coming to the
   table assuming them. A convention a consumer could reasonably do differently belongs in lane 2, as
   a discovered-and-externalized extensibility point, never as a lane-1 default.

A bare lane-1 hardcode in a skill declared agnostic is a defect, mechanically caught rather than
asserted only in prose: a fixed default branch, forge, ecosystem, or tracker where the consuming
repo could reasonably differ. A detection-first or presence-gated use is compliant. A capability
genuinely and inherently locked to one branch, forge, ecosystem, or tracker declares that narrower,
inherent scope at the coupling site, the same declared-narrower-boundary allowance the
cross-platform contract makes for OS platform, rather than shipping the assumption bare under a
neutral name.

Two reviewer-visible comment tokens carry that declaration, and they differ in REACH rather than in
strength. `portability-ok: <reason>` records one site: the coupling on that line (or the line below
a comment block carrying it) is excused and nothing else in the file is. `portability-scope:
<reason>` declares the whole file inherently locked, the case a forge-locked capability under a
forge-neutral name actually needs. Reach is the entire distinction, so the choice is a claim about
what is true: a per-site annotation on a file that is genuinely scope-locked buries the boundary,
and a whole-file declaration used to silence one awkward line exempts every future coupling added to
that file, including ones nobody reviewed. Neither is a frontmatter field; both are ordinary
comments a reviewer reads in the diff. `scripts/check-skill-portability.sh` enforces this, with the
coupling tokens it matches held as data in `scripts/skill-portability-tokens.txt`.

Detection evidence is scoped to the coupling class that authored it. A command proving which
*branch* was resolved says nothing about which *remote* holds it, so it cannot excuse a hardcoded
remote name that happens to share the line. A guard that generalizes across classes turns one
legitimate resolution into a blanket exemption for couplings it never examined.

## Configuration ownership and scope

Choose one authoritative owner for each value:

| Concern | Owner and mechanism |
|---|---|
| Invocation-specific choice | Explicit skill argument |
| Personal or administrator-provided scalar | Manifest `userConfig` |
| Tracked repository convention or rich team policy (structured, policy-floor, per-operator-keyed, or state) | A documented file under the consumer project |
| Team-shared prose convention with no per-operator axis | A natural-language convention doc at the consumer's convention home, bound by the root instruction file's pointer line (config-cascade § Expression doctrine, ADR 0018) |
| Personal project instruction | A documented, gitignored local overlay where the convention supports one |
| Installed dependencies, cache, or generated machine state | `${CLAUDE_PLUGIN_DATA}` |
| Bundled plugin code and assets | `${CLAUDE_PLUGIN_ROOT}` |

`userConfig` is not repository configuration. Claude Code reads its stored `pluginConfigs` values only
from user settings, `--settings`, and managed settings. It ignores project and local settings for this
key. Claude Code owns the configuration prompt and storage; plugin skills must not hand-edit
`pluginConfigs` or invent a marketplace-qualified plugin ID.

Use `userConfig` to its full native extent. Every personal or administrator scalar that flows
through a custom channel, whether an environment-variable toggle, a gitignored personal file, or a
documented hand-edit, migrates to `userConfig` with the schema used honestly:

- correct `type` (`string`, `number`, `boolean`, `directory`, `file`);
- a `default` that preserves zero-config behavior;
- `required: true` only where the plugin is genuinely unusable without the value;
- `sensitive: true` for secrets, noting that on platforms without a supported keychain the value
  lands in `~/.claude/.credentials.json`, so verify storage on the target platform before migrating
  a secret; and
- `claude plugin install --config` documented in the plugin's setup skill for headless use,
  following the short form in the
  [plugin-reconfiguration convention](conventions/plugin-reconfiguration/README.md), which owns
  the rerun behavior, its caveats, and the verified-version record; and
- for any `sensitive: true` option, the plugin's README documents `/plugin configure
  <plugin>@<marketplace>` as the rotation/clear path (see
  [`docs/extensibility-contract-smoke-tests.md`](extensibility-contract-smoke-tests.md) Test E:
  plugin identity is always marketplace-qualified; the bare name alone is not a documented command
  under a same-name, two-marketplace install). This is the only way to change or blank a sensitive
  value after initial enable. The `/mcp` server menu's "Clear authentication" is OAuth-only and
  silently no-ops for a plugin using static `userConfig`-substituted headers, and `/plugin`'s own
  detail view carries no reconfigure entry once a required value is already set. Targetless prose
  ("use `/plugin configure`") names the surface, not an install identity, and stays unqualified.
  `/plugin configure` is undocumented on the official docs site as of this writing; do not assume it
  will stay that way without re-verifying, but do not omit the guidance merely because upstream
  hasn't written it down.

Hook processes read the native `CLAUDE_PLUGIN_OPTION_<KEY>` mirror, a hook-only export: a Bash
call made by a skill and monitor processes do not receive it. A non-hook consumer (a script,
a skill-invoked shell script) takes the value through non-sensitive `${user_config.*}` substitution
in skill or agent content, an explicit argument, or a component field that substitutes it. The
custom environment variable is retired when the migration lands.

A hook kill switch is such a scalar: per-hook selectivity ships as a `userConfig` boolean with a
`default` of `true`, read through the hook mirror. Per-project control stays whole-plugin via
scope-level `enabledPlugins`; a genuinely project-scoped per-hook behavior graduates to the tracked
consumer-project file on demonstrated need, never a custom env channel.

`version` lives in `plugin.json` only, never in a marketplace entry. The platform resolves
plugin.json first, but a marketplace-entry copy is dead metadata that silently becomes live if the
manifest field is ever removed. One home, no shadow.

For project configuration, use neutral repository-relative paths anchored at
`${CLAUDE_PROJECT_DIR}`. Validate configured paths at the boundary, reject absolute paths and traversal
when the contract requires containment, and document precedence. Do not add an environment variable
merely to create a second configuration channel.

Apply the same anchoring rule to bundled assets: one skill citing another skill's supporting file
writes the full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form, optionally paired with a
relative markdown link target for browsing on GitHub, for example
``[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md)``.
A bare `context/…`-style path is reserved for a skill's OWN supporting files; it resolves against
the citing skill's directory, so a cross-skill citation written that way points at a file that is
not there.

This permission stops at the plugin boundary. It exists because a plugin is the unit that ships:
one `plugin.json`, one version, one marketplace entry, and skills that always travel together, so
a citation between two skills in the same plugin cannot arrive at an absent file. **Do not path-cite
into a skill in a different plugin.** Plugins install independently, so that path can genuinely be
missing at runtime; cite the other plugin's skill by its `/plugin:skill` invocation instead, or
promote the shared content to a convention doc both plugins can cite. The same limit applies to
anything outside `plugins/`: `docs/**` and `.claude/rules/**` cite skills by slash invocation, never
by path.

Heading anchors are never a citation target, in either direction. A heading is body structure, and
renaming one is exactly the refactor a skill must stay free to make.

The full public-surface contract this narrows is
`/docs-hygiene:audit-encapsulation`'s, which audits against it.

## One owner per value

Inside a plugin, code reads each value (a threshold, a default, a path, a frame rate, a package pin)
from one owner. [Configuration ownership](#configuration-ownership-and-scope) settles which surface
a consumer sets a value through; this rule settles where the plugin's own values live.

- Code reads the owner and never repeats the literal.
- Docs cite the owner and do not restate the number. A copy generated from the owner is not a second
  owner.
- Measurement records keep their numbers: a recorded result is data about one run, not a restatement.
- A skill body never restates a volatile external specific. It states our decision and carries the
  pointer, as-of date, and recheck trigger of the
  [upstream-drift convention](conventions/upstream-drift/README.md#required-parts).
- A value read from two languages lives in a JSON file both read.

Worked example: `animation`'s brush defaults live in `skills/rotoscope/scripts/brush.json`, read by
both `roto.js` and `measure.py`.

## Setup is explicit and repeatable

A plugin requires a `setup` skill iff it has (a) a consumer-project configuration surface, (b) an
external prerequisite such as a CLI, service, or credential, or (c) non-trivial `userConfig`. Apply the
criteria through the modular, configurable, repo-, machine-, and user-agnostic lens; zero-config
zero-prerequisite plugins are exempt, because setup is never blanket ceremony. For formatter and linter
plugins the requirement is a thin check-centric setup; where one is not yet shipped, the fleet
conformance audit tracks the gap.

`userConfig` is **non-trivial** when at least one option has a correct value that Claude Code's
native configuration prompt alone cannot establish. An option is non-trivial when it

- names an external referent whose existence, writability, validity, or identity must be verified
  before the plugin behaves as advertised: a path, file, credential, token, account, or model
  identifier;
- carries no default preserving documented zero-config behavior, so the plugin is degraded or blocked
  until the consumer supplies a value; or
- is coupled, meaning its correct value depends on another option's value, or on state outside the
  manifest (wiring, a tracked file, a repository convention), so the set cannot be settled option by option.

Every other option is trivial: a self-contained scalar, boolean, number, or closed enum, with a
default preserving zero-config behavior and no illegal value to get wrong, including one whose
out-of-set values are documented as falling back to that default. A manifest is trivial when all its
options are, however many it holds: count is not the test and neither is declared `type`.

The line follows from what the native prompt is: a collector, not a verifier. It stores what the
consumer typed; it never confirms the path exists, the token authenticates, or two options agree. A
`setup` skill's `check` is the only surface that can, which is why a non-trivial option requires one.
A trivial option requires none: every legal value is valid by construction and the default already
works, so a `setup` skill would have nothing to verify and nothing to advise. Criterion (c) is the
only criterion this definition governs. A plugin whose `userConfig` is trivial still requires setup
whenever (a) or (b) holds, which is the ordinary case for a plugin whose real surface is a project
config file or an external tool and whose manifest carries only a kill switch.

**Stated as fleet coverage:** a plugin declaring `userConfig` ships a `setup` skill **unless every
declared option is trivial** by the test above *and* neither (a) nor (b) holds. Declaring
`userConfig` at all is not the trigger, and neither is the option count. The blunter rule
"declares `userConfig` ⇒ ships a setup skill" reads as a coverage gap wherever a plugin's whole
manifest is one kill switch, and closing that "gap" ships the ceremony this section forbids. Applied
to a real case (#3111): `context-budget` and `repo-hygiene` each earn one on (b), for a `node`-launched
hook and a `git`-dependent tier set whose absence the native prompt cannot see, while
`visualization`, whose lone `medium` option is a self-contained scalar whose out-of-set values fall
back to its default and which has no external prerequisite, correctly ships none. A setup skill was
written for it and deliberately dropped rather than kept for symmetry.

The uniform contract: the skill is named `setup`, sets `disable-model-invocation: true`, because
setup has side effects a person should trigger by hand (Pointer:
<https://code.claude.com/docs/en/best-practices#create-skills>. As of: 2026-08-10. Recheck trigger:
that section stops tying the flag to manually triggered side effects), and offers `check` (read-only inspect and verify) and `apply` (idempotent configure) actions. This
contract is exception class (ii) of the fleet's invocation-mode rubric
([`docs/conventions/invocation-mode/`](conventions/invocation-mode/README.md)), which owns the
default and the other reasons a skill may set the flag. The
rest of the shape is house doctrine, and says so: upstream documents native *initialization*
surfaces (below) but takes no position on a consumer-facing `setup` skill, so the `check`/`apply`
split and the criteria above rest on the reasoning given here rather than on upstream backing. This
is a normative target: setup skills that predate this contract are nonconforming until brought into
conformance, and the fleet conformance audit tracks the gap rather than the doctrine pretending it
is closed. Setup must be:

- idempotent and safe to rerun;
- transparent about what it inferred, changed, skipped, or could not verify;
- limited to configuration the plugin owns;
- safe for existing files, preserving unrelated user content;
- runtime-grounded: `check` probes the artifact it is checking, never the setup skill's own account
  of it;
- evidence-bearing: after making or routing a change, it reports the stored value it *observed*,
  and says plainly where it could not observe one, never an unobserved change; and
- non-interactive when complete arguments are supplied, so automation and headless use remain possible.

The runtime artifact is the single source of truth for what it requires and how it resolves things:
the hook script and the libraries it sources, the bundled scripts, or the skill and reference files
the plugin ships. A `setup` skill's prose is a second copy of that account and goes stale without
saying so, which is why `check` reads the artifact first, probes what it actually does, and reports a
PASS/FAIL/INFO table with one remediation line per FAIL, modifying nothing. Where the artifact names
several files, the check reads all of them: an entry script that sources a library will not by itself
tell the reader what runs.

The readback is a property of the `setup` skill, not of the `apply` verb: it belongs to whichever
action made or routed the change, so a check-only skill (below) carries it in `check`. Where the
change was routed to a surface setup may not write, such as Claude Code's native configuration flow
or an edit left to the operator, the rule is unchanged.

**Keep two claims apart:** that the write was issued and stored, and how the *running* session
behaves. They can legitimately disagree, so a naive readback reports false failures, and reporting
one as a failed write is the specific error this clause exists to prevent. Verify the effective value
by re-checking in a **fresh session**, and never claim an unobserved change. A same-session `check`
therefore satisfies the bullet above by reporting the stored value it observed *and* naming the
running session's behavior as not yet established, not by pretending that session already reflects
the write. The stored value read in-session is current; it is the behavior that lags.

Two mechanisms are offered across the fleet as the reason the two diverge: that a `${user_config.*}`
value is substituted into skill content at load, and that a hook's `CLAUDE_PLUGIN_OPTION_*` mirror
comes from an environment fixed at session start. Both timings are **untested here**.
[Smoke-test D](extensibility-contract-smoke-tests.md) records the rendered *result* in skill content
on Claude Code 2.1.212, not when substitution happens; smoke-test B records only a negative on
2.1.207, that a skill-spawned Bash subprocess receives no mirror at all, and sources the
agent-content half of that substitution to upstream spec rather than to an observation. The rule does not
rest on either: a fresh-session re-check is correct whichever way they resolve, which is why it is
the prescription and they are only the explanation.

Setup is one **plugin-level** `setup` skill, never a per-skill setup action. Setup granularity
follows install granularity: a plugin installs and is configured as a unit, and its configuration
surface, covering tracked project files, external prerequisites, and `userConfig`, is plugin-scoped and
routinely shared across skills, so one `setup` skill is the single discoverable entry point
(`/<plugin>:setup`) and the one place `disable-model-invocation` is set for configuration, not a
flag fragmented across per-skill actions. Where distinct skills carry distinct readiness, the one
setup skill aggregates and reports it per skill.

`disable-model-invocation` is a whole-skill flag, so `setup` cannot hide `apply` from Claude and
leave `check` reachable. A plugin whose hook or probe names a read-only check therefore also ships
a separate `<plugin>:check` skill with `disable-model-invocation: false`. It reads `setup` and
follows only its `check` section, so `setup` stays the one account of what is checked, and it
installs and writes nothing. `setup` keeps `true`, and `apply` stays manual. A hook or probe names
`/<plugin>:check`, never `/<plugin>:setup check`, which the flag hides from Claude.
`plugins/context7/skills/check/SKILL.md` is the shape to copy. Record. Decision: we set the flag
per skill and split `check` into its own skill, because we found no per-action invocation flag.
Pointer: for `disable-model-invocation`, see
<https://code.claude.com/docs/en/skills#frontmatter-reference> and
<https://code.claude.com/docs/en/skills#control-who-invokes-a-skill>. As of: 2026-09-29. Recheck
trigger: a Claude Code release adds a per-action invocation flag, or that field stops applying to
the whole skill.

The verb set is deliberately closed at `check` and `apply`: no standalone `remove`, `reset`, or
`migrate` verb joins the mandatory contract (teardown, where genuinely needed, rides as a `remove`
argument to `apply`, per the teardown rule below). `apply` is *state-assessing*: it reads current
state and converges, which the idempotency and preserve-unrelated-content requirements above already
demand, named as a verb contract rather than a new bar. It reconciles conservatively: fill absent
keys at current defaults, preserve keys it does not recognize, and report (never silently rewrite)
values it cannot reconcile, so an obsolete or renamed key surfaces on re-run instead of sitting
silently inert. Schema evolution is handled this way, without a separate `migrate` verb: a plugin
that versions its own config contract may carry a forward, directional, user-confirmed upgrade of a
recognized older version, still under `apply`, never a separate verb and never a silent write (the
versioned standards index is the fleet example), while a plugin that instead takes a
clean-break path relocates by hand with no compatibility tooling. What the clean-break stance rules
out for either is *silent* backward-compatibility shims and dual-read windows that translate a
changed shape behind the user's back. The one sanctioned dual-read is the declared, WARN-visible
deprecation window config-cascade § Expression doctrine defines for a surface re-expressed as a
convention doc: the retired file is read as authority while present, every run says so, and the
window is bounded by that surface's retirement record. `reset` decomposes to teardown plus `apply`.

**Retirement declaration is mandatory.** A plugin that retires a consumer-facing convention, whether
a file it no longer reads, a gitignore line it no longer recommends, or a directory it renamed, appends
a record to its `retirements.yaml` in the same PR, so setup `check` detects the leftover in every
consumer repo and `apply` offers the gated cleanup (owner:
`docs/conventions/retired-conventions/README.md`; the migration playbook names the contract).
Bespoke detection prose in a setup skill is the drift this replaces; a retirement without a record
is a defect.

Setup may inspect the repository and create or update the plugin's tracked project configuration. It
must not write into the installed plugin cache, mutate Claude Code user settings, or write
`pluginConfigs`. Personal scalar configuration is collected through Claude Code's native plugin
configuration surface.

`apply` is owed wherever the plugin owns a **writable artifact**, and only there. The test is
ownership plus permission, not location: an artifact whose schema this plugin defines and documents
*and* which this contract permits setup to write, either its tracked project config or a machine-scope
file the plugin owns and the operator may edit, is reachable through `apply`, scoped to exactly that
artifact and nothing adjacent to it.

**Check-only carve-out.** Where a plugin's configuration surface contains no writable artifact, a
check-only setup is conforming: `check` verifies and reports, and no `apply` is offered because there
is nothing it could conformingly write. Three kinds of surface qualify, in any combination:

- **Native `userConfig`.** Reconfiguration routes through the native flow (`/plugin configure
  <plugin>@<marketplace>`, see above); the only thing an `apply` could write is the `pluginConfigs`
  this contract forbids.
- **Claude Code settings this contract forbids setup to mutate**: statusline wiring, a settings-level
  key, anything in the user's own `settings.json`. This surface is neither `userConfig` nor tracked
  project config; the prohibition two paragraphs above is what makes it unwritable, and a plugin
  whose behavior is delivered through it is a normal shape, not an exception. Silence is not the
  conforming response: `check` prints the exact edit, fully resolved and ready to paste, states that
  it is the operator's to apply, and names what re-invalidates it (a plugin update moving
  `${CLAUDE_PLUGIN_ROOT}`, say).
- **External prerequisites setup can only verify**: a system tool, service, or credential, per the
  prerequisites section. `check` probes and reports the remediation; installing is the operator's.

Check-only is therefore a consequence of having nothing conforming to write, never a preference and
never a shortcut. A plugin with even one writable owned artifact takes the narrow-write shape
instead, with `apply` bounded to that artifact, while every unwritable surface is still handled the
check-only way above. Which shape a plugin takes is settled by its surface, not by its author, and
both are conforming when the surface is what selected them. Two plugins with the same unwritable
settings surface can therefore differ legitimately: the one that also owns a documented machine-scope
file must offer the narrow `apply`; the one that owns nothing writable must not invent one. A
no-op `apply`, one that runs `check` and routes guidance but writes nothing, is that invented
verb and is non-conforming: the guidance belongs in `check`'s output (ratified 2026-09 when the
five remaining holdouts converged; the fleet now has zero no-op `apply` actions).

Bare `apply` converges to the configured state and never removes. Genuine teardown, converging to
the *absence* of the plugin's own tracked project config, is the one thing `apply` will not do
unasked. A plugin that genuinely needs it exposes it as an optional apply-scoped operation (an
`apply remove`, under the same never-blind, preserve-unrelated discipline), bounded to the tracked
project config the plugin owns and never to `pluginConfigs`, whose reconfigure-or-clear path stays
the `/plugin configure` flow the check-only carve-out above routes to. Teardown stays off the
mandatory contract because it is destructive and, across the fleet today, unexercised. That is grounds to
defer it with a trigger, not proof it is never needed: a second plugin needing teardown graduates a
shared teardown shape into an owner doc before that second adopter, a step the fleet conformance
audit checks, the same enforcement every convention-registry row rides. The distinction is config versus
data: removing the plugin's own tracked setup config is teardown, whereas an apply-scoped operation
that mutates a managed inventory the plugin maintains (a status change over existing entries, say)
is ordinary `apply` surface, not teardown, and does not trip that trigger.

Two native idioms are the sanctioned initialization surfaces: the `Setup` hook event for headless
and CI preparation, and a `SessionStart` hook comparing a bundled manifest against its
`${CLAUDE_PLUGIN_DATA}` copy for runtime-dependency installation. Pointer: for the `Setup` event and
the flags that fire it, see <https://code.claude.com/docs/en/hooks#setup>; for the data-directory
install idiom, see
<https://code.claude.com/docs/en/plugins/components#install-dependencies-into-the-data-directory>.
As of: 2026-08-10. Recheck trigger: either section moves, or the `Setup` event or the data-directory
idiom is removed.

These native idioms complement the `setup` skill; they do not compete with it, and native-first is
honored either way. The skill is the interactive, discoverable consumer-configuration face
(check/apply over tracked project config), a need no native hook exposes, so the skill is not a
redundant custom mechanism. The `Setup` hook event and `SessionStart` install hook are the
unattended faces the same plugin may also carry, and unattended init routes to them rather than a
custom channel. Where both exist they converge to one idempotent state. The `setup` skill fulfills
the `setup`-skill requirement above; these native idioms may complement the headless dimension, and
never replace it.

### Install subactions and refusal

The `apply` verb stays closed. A write that installs something is an optional subaction of `apply`,
never a new verb and never implied by bare `apply`. Subaction **names** stay locally informative;
the fleet does not converge onto one spelling (#3574).

Four sanctioned shapes, picked by what the write installs and where it lands. The name follows the
write and stays locally informative; the shape does not follow the name.

| Shape | When | Live subactions: command and scope |
|---|---|---|
| Consumer-repo dependency | the write adds one named tool to the consumer's own repo through the repo's package manager, so the manifest or lockfile records it | `install-ruff` (dev-dependency add through the repo's Python manager, for example `uv add --dev ruff`, into an environment the repo already has), `install-biome` (`@biomejs/biome` dev dependency: `pnpm add -D`, `yarn add -D`, `bun add -d` or `npm install --save-dev`), `install-lint` (`markdownlint-cli2` dev dependency, same managers) |
| Machine-global CLI | the write installs the one CLI the plugin exists to drive, into the machine's global package prefix | `install-cli`: context7 `npm install -g ctx7@latest`, playwright `npm install -g @playwright/cli` |
| Plugin-owned dependencies | the write provisions the plugin's own runtime: node dependencies under `${CLAUDE_PLUGIN_DATA}` plus a Playwright Chromium build, and touches nothing in the consumer's repo or the global npm prefix; where the browser and any OS packages land is stated per subaction | `install-deps` (knowledge: `setup-deps.mjs` for video-digest and course-digest, node dependencies plus Chromium, the browser in `${CLAUDE_PLUGIN_DATA}/ms-playwright` unless `PLAYWRIGHT_BROWSERS_PATH` is set), `install-build-deps` (ai-briefing: `npm ci` in a staged `runtime/build` under the data dir, then `npx playwright install --only-shell chromium`, which on Linux is `npx playwright install --with-deps --only-shell chromium`; the skill sets no `PLAYWRIGHT_BROWSERS_PATH`, so the browser goes to Playwright's default per-user cache, and `--with-deps` installs OS packages machine-wide) |
| Hook file | the write copies a named hook script into the operator's personal `.git/hooks/` | `install-commit-msg` (`hooks/commit-msg` and `hooks/guardrails-resolve-convention.sh`), `install-pre-commit-content` (`hooks/pre-commit` and `hooks/guardrails-content-lib/`) |

A new install subaction fits one of those four by what it writes. It does not invent a fifth, and it
does not rename a sibling to match. Names are not one grammar: `install-cli` and `install-lint` each
install one named tool, while `install-deps` and `install-build-deps` name a class.

**Refusal template.** A setup whose hook only calls a tool on the consumer's files, and which has no
install path recorded in the consumer's repo, declines to install. It uses this shape, not a
plugin-specific rationale: print the consumer-run command; do not invent `apply install-<tool>` to
paper over the gap; name every reason that applies; at least one always does.

1. The hook resolves the tool on `PATH`, so the install it can use is machine-level (a global bin
   directory such as `$GOPATH/bin`, cargo, Homebrew, a pre-built binary); a dependency recorded
   through the repo's package manager, such as a `go.mod` tool line, is not one the hook finds.
2. The tool publishes several official install methods, so choosing one is the consumer's call.

The discriminator is the preamble, not the install command. A plugin that exists to drive a CLI
(context7's `ctx7`, playwright's `@playwright/cli`) installs it machine-globally under the
Machine-global CLI shape. A plugin whose hook only runs a tool over the consumer's files
(go-format's `goimports`, typos-format's `typos`) refuses under the list above, though that tool is
also its subject. A machine-global or `@latest` install is not itself a reason to refuse.

`go-format` (no `install-goimports`: the hook resolves `PATH` only, reason 1) and `typos-format` (no
`install-typos`: cargo, Homebrew, Conda, pacman or a pre-built binary, reasons 1 and 2) are the
current refusals. They stay; they are not defects against a missing subaction.

- **Decision:** install subactions fall into four shapes by what they install (consumer-repo
  dependency, machine-global CLI, plugin-owned dependencies, hook file); names are not converged;
  a refusal names the reasons that apply from the list and never excludes a sanctioned subaction.
- **Pointer:** #3574. What each live subaction installs: `plugins/ruff-format/skills/setup/SKILL.md`
  (`install-ruff`), `plugins/biome-format/skills/setup/SKILL.md` (`install-biome`),
  `plugins/markdown-format/skills/setup/SKILL.md` (`install-lint`),
  `plugins/context7/skills/setup/SKILL.md` and `plugins/playwright/skills/setup/SKILL.md`
  (`install-cli`, the two `npm install -g` commands above),
  `plugins/knowledge/skills/setup/SKILL.md` (`install-deps`),
  `plugins/ai-briefing/skills/setup/SKILL.md` (`install-build-deps`: the Linux `--with-deps`
  branch and the absence of `PLAYWRIGHT_BROWSERS_PATH`),
  `plugins/guardrails/skills/setup/context/install-commit-msg.md` and
  `plugins/guardrails/skills/setup/context/install-pre-commit-content.md` (hook files). The
  refusals: `plugins/go-format/skills/setup/SKILL.md` and
  `plugins/typos-format/skills/setup/SKILL.md`. Tokens such as `install-hint` and
  `install-browser` are not setup subactions.
- **As of:** 2026-09-29.
- **Recheck trigger:** a setup skill adds an install subaction that fits none of the four shapes, a live
  subaction changes what or where it installs, or a maintainer converges the fleet onto one
  spelling.

## Prerequisites and failure behavior

Declare every required runtime, shell, CLI, service, credential, and platform constraint at the point
of use and in the plugin README. Never download or execute an undeclared tool as an incidental fallback.

Classify absence deliberately:

- **Required for correctness:** stop at the entry point with a concise remediation message.
- **Required for an optional feature:** warn visibly, skip only that feature, and continue with the
  documented reduced result.
- **Not applicable:** exit quietly and successfully.

Count as a dependency anything the plugin assumes about the machine: an external binary and the
version it needs, a network port, a fixed size or resolution, another plugin's file layout, an
installed browser, and a lookup on `PATH`. Each gets one verdict: behind a port
([Skills are processes](#skills-are-processes)), a `userConfig` value, presence-gated with the
absence class above, documented as a prerequisite, or fixed.

Anything with a runtime prerequisite (for example `jq` on `PATH`) degrades gracefully, never a hard
crash. Absence is surfaced to both the agent and the user; a candidate channel for durable
visibility is the hook-telemetry convention's OTel surface. No black boxes: a silently skipped
feature is a defect. The broader false-green class, healthy-while-dead and green-with-hidden-
findings on health, status, advisory, and gate surfaces, is owned by the
[liveness-assertion convention](conventions/liveness-assertion/README.md); this section's
prerequisite-absence rules are one slice of that contract, specialized here for runtime absence.

Hooks follow the event's official control contract. Use a blocking result only when the event can still
be blocked and the hook is enforcing a policy. Advisory hooks surface a visible non-blocking diagnostic.
Surface every error, and report the result the run actually produced.

## Convention registry

One owner doc per shared concern. This registry names and points, never restates; each owner doc
carries the rules, versioning, and adoption story. A new cross-plugin convention lands in an owner
doc before a second plugin adopts it. Fleet audits check conformance per row.

| Shared concern | Owner |
|---|---|
| Lifecycle artifact protocol | [`docs/plugin-artifact-protocol.md`](plugin-artifact-protocol.md) |
| Shared hook utility library | `lib/hook-utils.sh`, synced by `scripts/sync-hook-utils.sh` |
| Cross-plugin shared-source clusters | `scripts/cross-plugin-source-registry.txt` |
| Config cascade: consumer-config layering, precedence, overlay naming, and expression form | [`docs/conventions/config-cascade/`](conventions/config-cascade/README.md) |
| Worktree placement root (`worktreeroot.path` git config vendor section) | [`plugins/source-control/reference/worktree-root-convention.md`](../plugins/source-control/reference/worktree-root-convention.md) |
| Plugin reconfiguration: native `/plugin configure` and headless `--config` routes, plus the verified-version record | [`docs/conventions/plugin-reconfiguration/`](conventions/plugin-reconfiguration/README.md) |
| Commit-convention enforcement seam | [`docs/conventions/commit-convention/`](conventions/commit-convention/README.md) |
| PR-body required-sections convention | [`docs/conventions/pr-body-convention/`](conventions/pr-body-convention/README.md) |
| Ecosystem command resolution | [`docs/conventions/ecosystem-commands/`](conventions/ecosystem-commands/README.md) |
| Hook telemetry | [`docs/conventions/hook-telemetry/`](conventions/hook-telemetry/README.md) |
| Hook observability (status/failure surfaces) | [`docs/conventions/hook-observability/`](conventions/hook-observability/README.md) |
| Hook precision (false-positive discipline) | [`docs/conventions/hook-precision/`](conventions/hook-precision/README.md) |
| Hook input rewriting (deny-or-ask, never a silent `updatedInput`) | [`docs/conventions/hook-input-rewriting/`](conventions/hook-input-rewriting/README.md) |
| Hook config delivery (userConfig→hook channel matrix) | [`docs/conventions/hook-config-delivery/`](conventions/hook-config-delivery/README.md) |
| Permission-rule hygiene | [`docs/conventions/permission-rule-hygiene/`](conventions/permission-rule-hygiene/README.md) |
| Plugin-data report keying, retention, and overwrite | [`docs/conventions/plugin-data-report-keying/`](conventions/plugin-data-report-keying/README.md) |
| On-demand dependencies (pinned lockfile, `npm ci` into the plugin data directory, no vendored bundles) | [`docs/conventions/on-demand-dependencies/`](conventions/on-demand-dependencies/README.md) |
| Repository standards index | [`docs/conventions/standards/`](conventions/standards/README.md) |
| Skill layout contract and evals schema | `skill-quality` plugin (contract gate + bundled schema) |
| Review severity vocabulary | `review` plugin (`context/severity.md`) |
| Dynamic-context (`!`) precompute: when to inject, fallback binding, `shell:` declaration | `/playbooks:skill-authoring`, which owns and states the precompute contract |
| Skill invocation-mode rubric | [`docs/conventions/invocation-mode/`](conventions/invocation-mode/README.md) |
| Skill invocation-context rubric (`context: fork`, background posture) | [`docs/conventions/invocation-context/`](conventions/invocation-context/README.md) |
| Skill argument shape: action, earned `--flag` modifiers, and subject | [`docs/conventions/skill-argument-shape/`](conventions/skill-argument-shape/README.md) |
| Skill `argument-hint` string style | [`docs/conventions/argument-hint/`](conventions/argument-hint/README.md) |
| Plugin names and `userConfig` option text (titles, descriptions, types) | [`docs/conventions/plugin-option-naming/`](conventions/plugin-option-naming/README.md) |
| Seam phrasing (presence-gated fallbacks) | [`docs/conventions/seam-phrasing/`](conventions/seam-phrasing/README.md) |
| Native-surface reference phrasing (presence-gated native routing) | [`docs/conventions/native-references/`](conventions/native-references/README.md) |
| Loop-lane topology, escalation, capability tiers, loop invariants | [`docs/conventions/loop-lane/`](conventions/loop-lane/README.md) |
| Shell test-helper duplication and exit-code divergence | [`docs/conventions/shell-test-helpers/`](conventions/shell-test-helpers/README.md) |
| Finding suppression (deliberately-kept audit findings) | [`docs/conventions/finding-suppression/`](conventions/finding-suppression/README.md) |
| Liveness assertion (false-green / healthy-while-dead surfaces) | [`docs/conventions/liveness-assertion/`](conventions/liveness-assertion/README.md) |
| Detector findings (non-fanout producers reaching the apply relay) | [`docs/conventions/detector-findings/`](conventions/detector-findings/README.md) |
| Fresh-eyes declaration pattern contract | `/skill-quality:check`, which owns and enforces the declaration spec |
| Upstream-drift verification stamps and recheck triggers | [`docs/conventions/upstream-drift/`](conventions/upstream-drift/README.md) |
| Windows path emission across the Git Bash → native boundary | [`docs/conventions/windows-path-emit/`](conventions/windows-path-emit/README.md) |
| Pre-PR step order (where outcome verification sits) | [`docs/conventions/pre-pr-ordering/`](conventions/pre-pr-ordering/README.md) |
| Mod authoring once ADR 0035's go criteria pass: hooks modules in marketplace plugins, mod versus settings hook, version floor | [`docs/conventions/mod-authoring/`](conventions/mod-authoring/README.md) |
| Always-on hook cost ceiling | [`docs/conventions/hook-budget/`](conventions/hook-budget/README.md) |
| Tracker reference form inside a code comment | [`docs/conventions/tracker-reference-form/`](conventions/tracker-reference-form/README.md) |
| Untrusted-content framing contract | [`docs/conventions/untrusted-content/`](conventions/untrusted-content/README.md) |
| Record bundle: a markdown record with its diagrams and media, views kept outside | [`docs/conventions/record-bundle/`](conventions/record-bundle/README.md) |
| Reply affordance on decision-collecting artifacts | [`docs/finding-your-unknowns.md`](finding-your-unknowns.md#reply-affordance-convention) |
| Export button on interactive HTML artifacts | [`docs/finding-your-unknowns.md`](finding-your-unknowns.md#export-button-rule) |
| Retired-convention detection and cleanup (manifest + shared helper) | [`docs/conventions/retired-conventions/`](conventions/retired-conventions/README.md) |
| Recommendation basis: grounding bar, `Basis:` label, and old → new → why re-statement | [`docs/conventions/recommendation-basis/`](conventions/recommendation-basis/README.md) |
| Authoring formats: acceptance-criteria format and diagram dialect by artifact kind, read by `/planning:interview`, `/planning:prd`, and `/planning:design` | [`docs/conventions/authoring-formats/`](conventions/authoring-formats/README.md) |

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
none of it here (as of 2026-08-10; trigger in [recorded gate runs](#recorded-gate-runs)). A capability the
platform itself does not ship on a supported OS is the platform's gap, never the "narrower, inherent
platform boundary" a plugin may declare. The plugin still owes a portable path.

That input carries two axes, model provider and subscription plan. The *host surface* a consumer
runs in, whether CLI, Desktop, an IDE extension, web, or mobile, is a third, read separately from
[Platforms and integrations](https://code.claude.com/docs/en/platforms) and the per-host pages it
indexes, cited and never restated (as of 2026-08-10; trigger in [recorded gate runs](#recorded-gate-runs)).
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

Every standing instruction this marketplace ships is a per-session tax on every consumer, paid
whether or not the instruction ever fires: a CLAUDE.md line, a hook that corrects model behavior, a
skill's always-loaded listing text. (Whether a skill's description enters that
always-loaded listing at all is the invocation-mode choice, owned by the rubric at
[`docs/conventions/invocation-mode/`](conventions/invocation-mode/README.md).) We keep a standing
line only if removing it would cause a mistake, and we delete or convert to a hook any instruction
the model already follows unaided. Pointer: for pruning standing instructions, see
<https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md> and
<https://code.claude.com/docs/en/best-practices#avoid-common-failure-patterns>. As of: 2026-08-10.
Recheck trigger: either section moves or stops recommending pruning. Anthropic reports applying
the same doctrine to Claude Code's own system prompt for the Claude 5 generation; no docs page
covers that as of 2026-08-08
(correlate with <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>).
Context load is not the only budget: the human maintainer's cognitive load
is its sibling constraint, and the write-time doctrine budgeting both lives in
`docs-hygiene:write-for-agents`. Four rules follow:

- **Evidence-gated additions.** A new standing instruction requires observed, repeated stumble
  evidence against the current model, the same failure seen more than once, never anticipation
  of a failure a past model had. Name the evidence where the instruction is added (PR body or an
  adjacent comment). Anticipatory instructions are the veteran-engineer failure mode: they encode
  the last model's weaknesses as the next model's ceiling.
- **Generation-triggered ablation.** Instructions are disposable per model generation. At each
  frontier model release, re-audit standing instruction surfaces against the new model
  (`harness-config:audit-instructions` for the static text-vs-doctrine pass;
  `harness-config:unhobble` for the empirical bare-baseline experiment) and delete what the model no
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

- **Mechanism**: what the hook does structurally, either deny-gate (blocks a tool call), context-injection
  (adds text to the model's context), deterministic-transform (edits an artifact, model not in the
  loop), or notification/infra (output goes to a human or a log, not the model).
- **Class**: why the hook exists. **Policy** (an invariant you would keep with a perfect model:
  security, team convention, irreversibility protection); **behavioral** (corrects model behavior a
  better model gets right unaided); or **hybrid** (both, and name the split explicitly, because the
  remediation is a trim or a narrowing, never whole-hook deletion).

Mechanism never implies class. A context-injection can be pure policy (relaying a linter's measured
findings), and a deny-gate can be behavioral (a block whose predicate is a guess about model
competence rather than a checkable invariant).

One nuance does the most work: a hook with a *behavioral purpose* but a *non-derivable ground-truth
oracle*, such as diffing written flags against a binary's live `--help`, globbing the live plugin tree
after a rename, or querying git history for a path's disappearance, is a keep, not an ablation
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

The complementary task-design doctrine, describe the task, guardrails, and exit criteria, give the
model a way to verify its own work, and skip step-by-step procedure, is already this marketplace's
encoded practice: the `verification`, `planning` (goal conditions), `tdd`, and `testing` plugins are
its implementation, and need no new mechanism on its account.

Two further axes are settled elsewhere, and neither is implied by the rubric above:

| Question about a hook | Where it is decided |
|---|---|
| Does it fire by default? | [ADR 0003](adr/0003-verification-guards-earn-default-on-by-measured-precision.md): a default-on guard earns its place by measured precision, and loses it to observed false positives with no true positive |
| Does it belong in this plugin, or its own? | [ADR 0028](adr/0028-classify-a-plugin-s-hooks-by-packaging-before-proposing-a-split.md): Class A (the hooks ARE the plugin) and Class B (the hook IS the feature mechanism) never split; only Class C (hooks adjunct to a skill surface) is a candidate, and a candidate still argues its own case |

## Fresh-eyes checkpoints

A context that produced work is structurally the weakest place to judge that work: the reasoning that
made a mistake plausible is still active, so a self-check inherits the bias. A fresh-context (non-fork)
subagent, generic or named, removes it: it starts in its own fresh context window, blind to the
reasoning under review. A fork does not: it inherits the parent session's full conversation history, so
it carries the same bias forward. Upstream recommends fresh-context review as well as describing
the mechanism, and this section is the authoring-time form of that guidance, applied where an
invoker cannot be relied on to remember it.

- **Pointer**: for what a fork inherits, see
  <https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>; for
  fresh-context review, see
  <https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step>,
  <https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work>, and
  <https://code.claude.com/docs/en/best-practices#run-multiple-claude-sessions>.
- **As of**: 2026-08-10
- **Recheck trigger**: a fork stops inheriting the parent conversation, or those sections stop
  recommending a fresh-context reviewer.

The rule: **a skill step whose output judges work produced in the same context delegates that judgment
to a fresh-context (non-fork) subagent**, generic or named; what the rule requires is the fresh
context window, not a fork. Mandatory in the skill's design, not left to the invoker to remember.
Three bias classes name the trigger:

- **author-verifier**: verifying a change the same context authored (a verification skill confirming
  its own session's implementation, a pre-PR self-review);
- **plan-attacker**: adversarially attacking a plan the same context helped shape (a devil's-advocate
  pass run in the authoring session);
- **self-grade**: scoring the same context's output against criteria (a quality gate in self mode, a
  synthesis step grading its own lock).

The delegation target has an independence ladder: a same-vendor fresh context removes the session's
reasoning but can still share the model's blind spots; a different-vendor advisor removes both. Where
the verdict is high-stakes and correlated blind spots are the risk, a checkpoint site prefers a
cross-vendor advisor **when one is installed and set up**, for example the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the
stated fallback, never a route to a command that may not resolve. That reference is optional
collaboration, so it carries the presence-gate-plus-fallback shape
([seam phrasing](conventions/seam-phrasing/README.md)) at each site that instructs it; an advisor
plugin external to this marketplace is never a manifest dependency. Invocation mechanics such as
synchronous waiting, diff-base selection, and which artifacts a surface can judge are the advisor
plugin's own documentation's concern: a checkpoint site names the capability and the fallback,
never the advisor's command flags, which drift against the surface their owner evolves.

What does not need it: deterministic gates (a script's pass/fail cannot be biased by context, so prefer
one wherever the judgment is mechanical), and judgment over external input the context did not produce
(triage of another author's issue or PR). Delegation cost is real; the rule buys unbiased judgment
exactly where bias is structural, and nothing elsewhere.

The deterministic-gate exemption is narrow: it reaches the mechanical judgment itself, where the gate's
pass/fail *is* the verdict, and not a subjective self-review that merely runs ahead of a gate. A build/test/lint
pass gates behavior and the conventions its linters encode, not scope creep or the conventions it leaves
unchecked; self-judging those stays the same-context judgment the rule targets even when a deterministic gate
sits downstream. A step that self-reviews both is exempt only for the gated part. The rest is still owed a
fresh-context pass.

## Delegation mechanics

How a fresh-eyes checkpoint dispatches. The mechanics live here once; a checkpoint site states its
judgment and its target, never re-derives these rules.

### Dispatch ladder

The default worker is a **generic fresh-context subagent carrying rich inline instructions**: the
task, the artifact, the criteria, and the output shape all travel in the dispatch prompt. A non-fork
subagent starts without the parent conversation (Pointer:
<https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>. As of:
2026-08-10. Recheck trigger: a non-fork subagent starts receiving the parent conversation), which
is exactly the independence the checkpoint buys. A skill may prefer an installed **named agent** on the next rung,
but only when the named-agent bar below is met, and the site always states the generic fallback
(presence-gate-plus-fallback, [seam phrasing](conventions/seam-phrasing/README.md)). The top rung, for
high-stakes verdicts where correlated model blind spots are the risk, is a **cross-vendor advisor**
when one is installed, on the same presence-gate shape with the same generic fallback.

Those rungs are one choice among the platform's parallelism surfaces;
[run agents in parallel](https://code.claude.com/docs/en/agents#choose-an-approach) is the
canonical upstream comparison of all of them (as of 2026-08-10; trigger in
[recorded gate runs](#recorded-gate-runs)). Why the fleet takes the subagent rung today rather than agent
teams or cross-session messaging is recorded once in the [gate runs](#recorded-gate-runs). Re-derive
from that table's triggers instead of re-arguing it at a checkpoint site.

### Inline-template conventions

A dispatch prompt at any rung:

- says **fresh-context** work is expected: the worker judges the artifact it is handed, with no
  access to the reasoning that produced it;
- hands over the **artifact, not the story**, meaning the diff, file, or plan itself, never the authoring
  session's rationale, which would re-import the bias being removed;
- **degrades when absent**: a preferred named agent or advisor that is not installed routes to the
  generic fresh-context subagent, never to a command that may not resolve; and
- **bounds what counts as a finding**: correctness and the stated requirements, everything else
  optional. An unbounded adversarial prompt buys noise at the same price as judgment, and chasing
  every reported gap over-engineers the work. Pointer:
  <https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step>. As of:
  2026-08-10. Recheck trigger: that section stops recommending a bounded review.

### Named-agent bar

A named agent is earned, not default: **the same worker with the same instructions dispatches from
multiple sites (or repeats via description-triggered direct invocation) AND a model pin, an effort
pin, or an enforced tool restriction is required.** Otherwise the generic subagent with inline instructions
is the simpler, equally independent form. On tool cages: an allowlist that includes Bash bars
Edit/Write and recursive spawning but is **not read-only**, because Bash can write. State what the cage
actually enforces, never "read-only" (Pointer: for plugin agent frontmatter, see
<https://code.claude.com/docs/en/plugins/components#frontmatter-fields-in-plugin-agents>. As of:
2026-08-10. Recheck trigger: plugin agents stop supporting `tools`).

**Exception: `planning:plan-reviewer`.**

- **Decision:** this agent departs from three defaults on purpose. Bar: it has one dispatch site,
  `/planning:plan` Step 3, and its description says not to invoke it directly, so the
  multiple-sites clause is unmet; the pin clause carries it, because a definition is the only way to bound
  this one review's effort (a generic Agent-tool dispatch has no per-invocation `effort`). For the same
  reason the Step 3 site names no generic fallback: the plugin ships the agent, so there is
  nothing to presence-gate. Effort: it pins `effort: medium`, not the `high` that a
  consequential-verdict lane pins, because its pin bounds cost; the brevity line and `maxTurns`
  bound it further. Model: it pins `model: opus`; under the fleet's pinned default session, `opus`
  is the tier the plan was written at, so it meets the [Model tiers](#model-tiers) rule that a
  judgment verdict is never on a weaker model than the work it checks.
- **Pointer:** the frontmatter of `plugins/planning/agents/plan-reviewer.md` (`model: opus`,
  `effort: medium`, `maxTurns: 25`) and `plugins/planning/skills/plan/SKILL.md` Step 3;
  [#4256](https://github.com/melodic-software/claude-code-plugins/issues/4256), which measured a
  nested plan review at 31.6 minutes and 277k tokens at session effort; the closing comment on
  [#4849](https://github.com/melodic-software/claude-code-plugins/pull/4849), which kept
  `opus`.
- **As of:** 2026-09-29.
- **Recheck trigger:** a second dispatch site or direct use appears (the exception then ends), the Agent
  tool gains a per-invocation `effort` parameter, or the agent's `model` or `effort` changes.

### Model tiers

Four rules decide a lane's model, applied in this order:

1. **Tune effort on the current model before adding a second model.** A lane that falls short moves
   its effort level first; a second model enters only when effort cannot close the gap.
2. **Use one model at lower effort unless the work is bulk and independent.** A dependent chain, or
   work that fits one context, stays on the coordinating model. Only a fan-out of independent items
   delegates to a cheaper worker model.
3. **A judgment verdict is never on a weaker model than the work it checks.** An equal model is
   valid.
4. **A cheaper checker is acceptable only when an objective failure signal backs it**, because a
   checker that passes bad work lets those failures through unseen.

- **Pointer:** for rule 1, see
  [optimizing for cost and intelligence: compare models on cost per task](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#compare-models-on-cost-per-task)
  and [tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort);
  for rule 2,
  [orchestrator strategy: delegate bulk work](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#orchestrator-strategy-delegate-bulk-work);
  for rule 3, the advisor capability rule in
  [advisor tool: model compatibility](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#model-compatibility);
  for rule 4,
  [re-run failures at higher effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#re-run-failures-at-higher-effort).
- **As of:** 2026-10-02.
- **Recheck trigger:** next model release, which the cost page itself asks for, or any cited
  section changes.
- **Judgment:** the advisor rule constrains an API advisor and executor pairing; applying it to a
  subagent verdict and the work it checks is our reading, not a source statement. What counts as an
  objective failure signal under rule 4 (a build, a test run, a schema or exit-code check) is also
  our judgment.

An implementation phase the plan routes `sonnet` as well-scoped drops one tier, to
`implementation:scoped-implementer` at `medium` effort, the [effort floor](#effort-floor); unrouted
or complex phases stay on `implementation:implementer` at the strong tier.

The heavy default must be explicit: every agent definition in this repository pins `model`, because an agent that omits it
falls through the harness's resolution order and, on a machine with no consumer default, runs on
the main conversation's model. Consumers hold one global fallback knob, `CLAUDE_CODE_SUBAGENT_MODEL`,
set through the settings `env` map. We rely on it ranking below both the per-invocation `model`
parameter and frontmatter, so it decides only for a subagent neither binds: a structural
frontmatter binding holds against it, and the knob is a default for unbound subagents rather than
an override.

- **Pointer:** for the resolution order and the values frontmatter `model` accepts, see
  [subagents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model); for the
  `env` key, see [settings reference: `env`](https://code.claude.com/docs/en/settings-reference#env).
- **As of:** 2026-10-01.
- **Recheck trigger:** a release note touches subagent model selection, or the variable stops
  ranking below frontmatter.

**Decline `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`.** We do not set it, and a consumer who sets it gives
up the tier ladder above, because it puts one model on every subagent regardless of its pin or a
per-spawn `model`.

- **Pointer:** for the force switch, see
  [subagents: run every subagent on one model](https://code.claude.com/docs/en/sub-agents#run-every-subagent-on-one-model)
  and its row on [environment variables](https://code.claude.com/docs/en/env-vars#variables).
- **As of:** 2026-10-01.
- **Recheck trigger:** the switch stops overriding definition and per-spawn `model` values, or the
  subagents page stops describing it.

There is no per-plugin model surface: we read plugin `userConfig` as typed options with no model
semantics, so doctrine travels by authoring-time conformance in each skill, not runtime
configuration (Pointer:
[plugins reference: user configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration).
As of: 2026-08-10. Recheck trigger: a `userConfig` option can select the model a plugin's subagent
runs on).

The tier table names Claude Code aliases, never model versions, so a release that moves an alias
needs no edit here. Which model each alias resolves to is read live from the model page, and it
differs by provider: the same alias can name an older model on a cloud provider's platform than on
the Anthropic API.

| Tier | Alias |
|---|---|
| Judgment verdict (never weaker than the work it checks) | `opus`, or the tier of the checked work when that is higher, with `fable` the rung above |
| Mechanical work an objective failure signal backs | `sonnet` |
| Bulk mechanical sweeps | `haiku` |

- **Pointer:** for what each alias resolves to on each provider, see
  [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases). For
  where the `sonnet` row's model fits against `opus`, see the
  [models overview: latest models comparison](https://platform.claude.com/docs/en/about-claude/models/overview#latest-models-comparison)
  and [model config: available models](https://code.claude.com/docs/en/model-config#available-models)
  (correlate with <https://claude.dev/blog/building-with-claude-sonnet-5-5>;
  recheck when those docs pages cover what the post adds).
- **As of:** 2026-10-01.
- **Recheck trigger:** any new model on Claude Code's model page.

Row 1 is relative to the checked work by construction: a verdict on work done at the top tier runs
at that tier, since there is no rung above it. The cost ordering behind the rows is
upstream-owned and is not restated here (Pointer:
[pricing: model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing).
As of: 2026-08-10. Recheck
trigger: any new model on Claude Code's model page). No row binds a model that is not generally
available to the fleet.

**Override points.** The rows are repository defaults; a personal routing preference belongs in the
operator's own user-scope settings, never in this table. From narrowest to widest reach: a dispatch
site passes the per-invocation `model` (upward only for a verdict, per the rule above); an agent
definition's `model` frontmatter sets that agent's default; `CLAUDE_CODE_SUBAGENT_MODEL` sets the
default for subagents nothing else binds; `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL` and
`ANTHROPIC_DEFAULT_FABLE_MODEL` pin which model an alias resolves to; and an `availableModels`
allowlist bounds every one of them (below).

- **Pointer:** for the alias-pinning variables, see
  [model config: environment variables](https://code.claude.com/docs/en/model-config#environment-variables);
  for the allowlist, see
  [model config: restrict model selection](https://code.claude.com/docs/en/model-config#restrict-model-selection).
- **As of:** 2026-10-01.
- **Recheck trigger:** the model page adds or removes an alias or an alias-pinning variable.

That ladder is a cost ordering, and one capability does not travel down it: **interleaved thinking,
a thinking block between tool calls rather than only before the first and after the last.** We treat
it as a per-model capability that the bottom tier's alias may lack, and resolve which models have it
from the live roster, never from this file.

- **Pointer:** for which models interleave, see
  [thinking: interleaved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#interleaved-thinking);
  for how Claude Code records the capability for a pinned model, see
  [model config: customize pinned model display and capabilities](https://code.claude.com/docs/en/model-config#customize-pinned-model-display-and-capabilities).
- **As of:** 2026-10-01.
- **Recheck trigger:** any new model on Claude Code's model page, or that section's per-model
  statement changes.

The dispatch consequence, phrased as capability rather than family name so it survives an alias
moving under it: **require interleaving only where extended reasoning between tool results decides
the next call, meaning a mid-sweep judgment that has to change what gets called next. A task that chains
calls, or that reasons over its results at the end, does not need it.** We read the capability as
adding deliberation at that point, not as a condition for chaining tool calls or for acting on a
tool result (same pointer). So the bottom tier row stands for bulk mechanical sweeps and for
straightforward triage or research passes that decide at the end; the case it does not cover is a
fan-out whose worth is deliberating partway through, where the next call must change because of
what the last one returned.

The **dispatch-site** tier enforcement is structural at two binding sites:
`plugins/implementation/agents/implementer.md` and
`plugins/implementation/agents/phase-verifier.md` (both bind the loop-lane convention's strong-tier
current alias; raise the pair together, and note frontmatter binds a floor, since the session-relative
raise above it stays a per-invocation override at the dispatch site). That pair is the binding, not the
recheck list: the trigger above re-audits **every** agent-frontmatter `model` value in this
repository, which `git grep -n '^model:' -- 'plugins/*/agents/*.md'` enumerates rather than any
list restated here. Outside the pair, `plugins/implementation/agents/scoped-implementer.md` binds
the fast tier at `medium` effort, the [effort floor](#effort-floor), and runs only plan-routed
well-scoped phases, dispatched with an explicit per-invocation `model`.

That floor is the consumer's to lose. An enterprise `availableModels` allowlist reaches frontmatter
pins too, and Claude Code handles a blocked pin differently for a subagent than for a skill or
command. Our conclusion, with the per-surface rules left at the pointer: a subagent lane's tier is
not self-enforcing, because a blocked pin can land below the session (an `opus` pin under an
allowlist that permits only an older Opus) or on the inherited session model (a blocked cheap pin,
which is then not cheap), with no error either way. A skill or command lane with a blocked pin stays
on the session model, never below it. A design whose correctness needs a tier therefore needs a
mechanism that is not a frontmatter pin.

- **Pointer:** for how a blocked override is handled on each surface, see
  [model config: restrict model selection](https://code.claude.com/docs/en/model-config#restrict-model-selection)
  and [subagents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model).
- **As of:** 2026-08-10.
- **Recheck trigger:** either page's blocked-override behavior for a subagent, skill, or command
  changes.

### Effort tiers

Effort routes per lane the way model does: a skill or agent pins `effort` in its frontmatter where
its work needs a level other than the session's, knowing the `CLAUDE_CODE_EFFORT_LEVEL` environment
variable and an effort cap still win over the pin. The ladder itself, meaning level names, which
models support effort, each model's default, and what happens to a level a model lacks, is
upstream-owned: resolve it from the model page at decision time, never from this document.

- **Pointer:** for the levels each model supports and its default, see
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level);
  for how a frontmatter pin ranks against the session, the variable and a cap, see
  [model config: set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level);
  for the field itself, see
  [skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference).
- **As of:** 2026-10-01.
- **Recheck trigger:** any new model on Claude Code's model page, or the effort section changes how
  a frontmatter pin ranks.

We treat a lane pin as a posture, never a switch: thinking is adaptive, so a lane pinned `low` still
thinks where the model judges it worth the cost, and a turn with no thinking is not a pin
misfiring. Authoring conformance follows: pin the lane, then let allocation vary per request
instead of writing prose that tries to force it uniform (Pointer: for how the model decides when to
think, see
[steering thinking: how Claude decides when to think](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#how-claude-decides-when-to-think).
As of: 2026-08-03. Recheck trigger: that page stops describing thinking as decided per request).

Lane rules (recheck trigger: any new model on Claude Code's model page, or a model change on any
pinned lane, because each model maps level names to its own depth, so one name does not mean the
same depth on two models):

- **Consequential-output lanes with a frontmatter surface pin `high`**: verdicts, and research
  that feeds decisions, wherever the lane is a named agent or a skill doing that work in its own
  context. The pin exists so the lane does not silently degrade inside a session tuned down for
  cost (the environment variable still wins, per above). The pin is not relative: on a model
  whose own default sits above `high`, it caps the lane below that model's default, and the recheck
  trigger above exists exactly for this. The reach is the mechanism's, not the rule's: a generic
  Agent-tool dispatch carries no effort control: we read the live Agent tool schema, which has a
  per-invocation `model` parameter and no effort counterpart, and that probe has no stored
  artifact (Pointer: for the per-call parameters the docs name, see
  [subagents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model).
  As of: 2026-07-29. Recheck trigger: the Agent tool gains an effort parameter), so it
  structurally inherits the session level and its floor is the
  session baseline; promoting such a lane to a named agent is how it gains the pin (a required
  effort pin satisfies the named-agent bar's pin clause). The named agents that pin `medium`
  instead, and why, are listed under [pinned agents](#effort-tiers). An orchestrator skill
  whose consequential work executes in generic dispatches reaches them through its own pin: a
  skill-level pin governs the orchestrating conversation and, by our probe, the subagents it
  dispatches (the skill-pin record under [override levers](#effort-tiers)); no docs page covers
  that reach, so the cache caveat below still applies.
- **Read-only bulk mechanical sweeps may pin `low`.** We allow it where speed and cost matter more
  than depth, subagent sweeps included, and never for a lane that changes code or verifies a change
  (the [effort floor](#effort-floor)). Not at the model ladder's own bottom rung either, because the
  two ladders do not compose there: we read the model the `haiku` alias resolves to as having no
  effort support, so a pin there has no level to land on. What the harness does with such a pin,
  whether ignore it, warn, or fail, is **unverified here**, and no page we read settles it. The rule
  does not rest on that gap: a lane wanting the cheapest tier takes it by model alone and omits the
  pin, because the dial it would be reaching for only exists one rung up (Pointer: for which models
  support effort, see
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level);
  for what a lower level trades away, see
  [effort: how effort works](https://platform.claude.com/docs/en/build-with-claude/effort#how-effort-works).
  As of: 2026-10-01. Recheck trigger: a Haiku model appears among the models that support effort).
- **Every other named agent pins the level its work's task row gives it**, never below `medium`
  for code-changing or verifying work (the [effort floor](#effort-floor); the per-pin rows under
  pinned agents name each row). Only a skill with no consequential output omits the pin and
  inherits the session level. A pin is a design-time choice made once for that lane; the session
  level belongs to the user, who overrides a pin through the [override levers](#effort-tiers).
  - **Pointer:** for which level fits which kind of work, see
    [model config: choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level);
    the two posts under the source conflict below are correlate notes only.
  - **As of:** 2026-10-01.
  - **Recheck trigger:** that section stops matching levels to kinds of work, or starts naming one
    level for every task.
  - **Source conflict:** the older effort post,
    <https://claude.com/blog/claude-model-and-effort-level-in-claude-code> (correlate only), and
    model config's choose-an-effort-level section, joined by the newer effort post,
    <https://claude.dev/blog/spending-your-effort/> (correlate only), disagree on whether effort is
    a general preference or a per-task choice. As of: 2026-10-01. Recheck trigger: either post or
    that section is revised on that point.
- **No lane pins `max` without eval evidence.** We treat it as the costliest level, whose gain a
  lane must measure before using it. A pin above `high` (e.g. `xhigh`) is a deliberate per-lane
  choice grounded in the target model's own recommended levels, never a reflex. We watch for
  miscalibration in both directions: set too high, a lane keeps spending after the evidence runs
  out; set too low, it stops early and skips checks, and its answer looks finished on partial
  information (Pointer: for each level's trade-off, see
  [effort: effort levels](https://platform.claude.com/docs/en/build-with-claude/effort#effort-levels);
  for miscalibration, see
  [cut spend without losing quality](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#cut-spend-without-losing-quality).
  As of: 2026-09-09. Recheck trigger: either section changes what it says a level above `high`
  buys).
- **Sweep model and effort together before raising either.** A lane outgrowing its level tests the
  newer model at lower effort before pinning the old one higher, on its own evals. Cross-model
  economics and the flat-curve reading live in the fable-5 pack's model-adaptation chapter for the
  newer model (`plugins/playbooks/reference/model-adaptation/fable-5-1.md`, "Cross-model effort
  economics"); current prices resolve through the `claude-api` skill at decision time.
- **Effort is the first lever in either direction; steering prose is the second.** We set the
  level to fit the lane's work and add prose only where that level still falls short (Pointer:
  for why, see
  [steering thinking: effort levels](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#effort-levels).
  As of: 2026-08-03. Recheck trigger: that section stops ranking effort ahead of prompt
  steering). Both directions: shallow output from a pinned-`low` lane raises the lane's
  effort instead of adding prompt text, and a lane thinking more than the work needs lowers the
  pin before any prose telling the model to think less. A lane that must hold its level for latency
  is the one case that reaches for steering prose first, and it keeps that prose only after
  comparing a sample of runs with and without it, because wording moves the result less
  predictably than a level does. Authoring a lane's prose against its own pin, in either
  direction, is the inversion this rule exists to catch.
- **Cache caveat.** For whether an effort change keeps the cache on a given model and route, read
  [prompt caching: changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level)
  first. Where that section says the cache is lost, we pick a lane's level once and keep it, steer
  per message when one turn needs more or less, and move configuration only between tasks. Where
  it says the cache is kept, that rule does not apply, but we design no lane that depends on that
  path. Two expectations hold either way: a skill pin firing mid-session counts as cache-costly
  for the main conversation, since how the harness assembles that request is unconfirmed, while a
  subagent pin touches only the subagent's own requests; and a pin equal to the model's own
  default changes nothing, so a pin that only documents the default costs nothing.
  - **Pointer:** for Claude Code's handling, see the section above; for the API side, see
    [steering thinking: prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#prompt-caching).
  - **As of:** 2026-10-01.
  - **Recheck trigger:** either section changes what an effort change does to the cache, or which
    models, providers or versions keep the cache across one.

**Pinned agents.** Every named agent in this repository pins its effort, so a session tuned down for
cost does not silently cheapen a worker. Each pins the level that model config's task rows give its
kind of work, and never below `medium` for work that changes code or verifies a change (the
[effort floor](#effort-floor)). Ten pin `effort: high`: `implementation` `phase-verifier`;
`discovery` `researcher`, `intent-tracer`, and `research-verifier`; `review` `code-reviewer`,
`architecture-guardian`, `security-reviewer`, `ci-log-auditor`, and `doc-drift-detector`;
`plugin-quality` `auditor`. Six pin `effort: medium`: `planning` `plan-reviewer` by its
[recorded exception](#named-agent-bar); `implementation` `implementer`, because a phase brief is
scoped feature work and its verifier runs at `high`; `implementation` `scoped-implementer`, because
a plan routes only well-scoped work to it; `songwriting` `object-writer`, because creative
generation is not verification; and `review` `ecosystem-specialist` and `discovery` `explorer`,
because their work is clearly scoped tool use, running a repository's declared commands and reading
and indexing a scope. No pin goes below `medium`, because a low-effort executor stops detecting
that it is stuck. A frontmatter pin is what holds a named agent's lane, since an Agent-tool dispatch
passes no effort.

- **Pointer:** the agent definitions themselves, listed by
  `git grep -n '^effort:' -- 'plugins/*/agents/*.md'`;
  [#4253](https://github.com/melodic-software/claude-code-plugins/issues/4253) for the filed pin
  list; for the task rows, see
  [model config: choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level);
  for how a frontmatter pin ranks against the session, see
  [model config: set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level)
  and the `effort` field in
  [subagents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields).
- **As of:** 2026-10-02.
- **Recheck trigger:** any new model on Claude Code's model page, or a pinned agent's `model`
  changes, since a level name means a different depth on each model; the task rows change; a
  checker pinned `medium` misses a defect a `high` pin caught; or a maintainer changes or drops a
  named pin.
- **Sources agree:** the newer effort post,
  <https://claude.dev/blog/spending-your-effort/> (correlate only), and model config's
  choose-an-effort-level section now put scoped implementation work on the `medium` row and
  verification work on the `high` row, so the implementer pins `medium` and its verifier `high`.
  Model config stays the source we follow if they diverge again, because a docs section outranks a
  blog post under the
  [upstream-drift convention](conventions/upstream-drift/README.md#required-parts). As of:
  2026-10-02. Recheck trigger: next model release, or either page is revised on that point.

**Per-pin rows.** Each pinned agent outside `plugins/implementation` follows one row of model
config's effort-level table, read for the model its `model` alias resolves to. Review, verification
and verdict lanes follow the `high` row; well-specified mechanical work follows the `medium` row.

| Agent | Model | Pin | Row | Why that row |
|---|---|---|---|---|
| `discovery` `explorer` | `sonnet` | `medium` | `medium` | Reads and indexes a scope it is handed |
| `discovery` `intent-tracer` | `opus` | `high` | `high` | Reconstructed rationale feeds decisions |
| `discovery` `research-verifier` | `opus` | `high` | `high` | Verdict on a research artifact |
| `discovery` `researcher` | `opus` | `high` | `high` | Research that feeds decisions |
| `planning` `plan-reviewer` | `opus` | `medium` | `medium` | A review lane held to `medium` by its [recorded exception](#named-agent-bar), not by the review rule |
| `plugin-quality` `auditor` | `opus` | `high` | `high` | Audit verdict |
| `review` `architecture-guardian` | `opus` | `high` | `high` | Review verdict |
| `review` `ci-log-auditor` | `opus` | `high` | `high` | Audit verdict on a CI run |
| `review` `code-reviewer` | `opus` | `high` | `high` | Review verdict |
| `review` `doc-drift-detector` | `opus` | `high` | `high` | Drift verdict |
| `review` `ecosystem-specialist` | `sonnet` | `medium` | `medium` | Runs a repository's declared build, test and lint commands |
| `review` `security-reviewer` | `opus` | `high` | `high` | Security verdict |
| `songwriting` `object-writer` | `opus` | `medium` | `medium` | Creative generation, which no row names; the `medium` choice, the model's default, is our judgment |

- **Pointer:** for the rows, see
  [model config: choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level);
  for the model each alias resolves to, see
  [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases); for
  each model's default level, see
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level).
- **As of:** 2026-10-02.
- **Recheck trigger:** a row named in the table changes, the default effort of the model an agent's
  alias resolves to changes, or an agent's `model` or `effort` changes.

**Override levers.** We name two levers for a user who wants a pinned agent at another level.
`CLAUDE_CODE_EFFORT_LEVEL` sets one level for a whole session and replaces every pin. A Workflow
script's `agent()` call passes `opts.effort`, and `opts.model`, for that call alone. A
`maxEffortLevel` setting or an organization effort cap also limits every pin.

- **Pointer:** for the variable, see
  [environment variables](https://code.claude.com/docs/en/env-vars#variables); for how a pin ranks
  against the variable and a cap, see
  [model config: set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level).
- **As of:** 2026-10-01.
- **Recheck trigger:** the variable stops replacing a frontmatter pin, or the Agent tool gains a
  per-invocation `effort` parameter.

Our Workflow probe: an explicit `opts.effort` or `opts.model` on an `agent()` call overrode the
named agent's frontmatter pin for that call, and omitting them kept the pin. No docs section
covers per-call effort for `agent()`; for the call itself, see
[workflows: what the saved script looks like](https://code.claude.com/docs/en/workflows#what-the-saved-script-looks-like).

- **Pointer:** probes `wf_1a471686-8a2` and `wf_5196f26b-e1f`, run on Claude Code 2.1.284 and
  2.1.285; no artifact is stored in this repository.
- **As of:** 2026-10-01.
- **Recheck trigger:** a docs page starts covering per-call effort for a workflow `agent()` call or
  for the Agent tool.

**Where per-task effort is set.** We set a task's effort through Workflow's per-call effort
option. An Agent-tool dispatch of a named agent runs at that agent's pin, and a generic one at the
session level. A lane's `--effort` sets the session level, so it covers the orchestrator's own
turns and its generic dispatches; it does not move a named agent's pin. Workflow scripts this
repository ships never pass an effort below a named agent's pin, and omit effort on a call to a
named agent to keep the pin. A call that names no agent passes an explicit level.

- **Pointer:** for the `--effort` flag, see
  [CLI reference: CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags); for a
  subagent's `effort` field and its rank over the session level, see
  [subagents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields).
  No docs page covers per-call effort for a Workflow `agent()` call as of 2026-10-02; our Workflow
  probe above is the record.
- **As of:** 2026-10-02.
- **Recheck trigger:** a docs page starts covering it, the Agent tool gains an effort parameter, or
  either section above changes how the flag or the field ranks.

**A skill's pin reaches the subagents it dispatches.** We treat a skill's frontmatter `effort` pin
as applying to the main turns while that skill is active and to the subagents it dispatches.

- **Pointer:** our probe, two headless sessions on Claude Code 2.1.285. Session
  `ec6654fe-076a-4c3d-970c-363339cb63b3` ran a throwaway plugin skill pinned `effort: high` under
  `--effort low` and ran at `high` on three main turns and two subagent turns; control session
  `908560cb-3f30-4157-a672-5e00112bba0a` ran without the pin and stayed at `low` throughout. The
  throwaway plugin no longer exists, so the session ids are the artifact. For the skill field, see
  [skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference);
  no docs page covers the pin's reach into dispatched subagents.
- **As of:** 2026-09-29.
- **Recheck trigger:** the Claude Code CLI version moves past 2.1.285, or a docs page starts
  covering pin propagation to subagents.

**Configurability gap.** No per-agent user setting exists: a user cannot move one named agent's pin
without editing its definition, and we have not confirmed that a plugin `userConfig` value can
reach an agent's `effort` field. We record this as a gap against
[configuration ownership](#configuration-ownership-and-scope), not as a design choice.

- **Pointer:** for plugin options, see
  [plugins reference: user configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration);
  for the agent field, see
  [subagents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields).
- **As of:** 2026-10-01.
- **Recheck trigger:** Claude Code adds a per-agent effort setting, or a docs page or a probe shows
  a `userConfig` value reaching a subagent's `effort`.

**Effort is one dial of two, and the other is not an effort value.** We keep the `thinking` mode and
the `effort` level apart: `adaptive` is a thinking mode, never an `effort` value, and a frontmatter
`effort` field is where that mix-up is reachable, because the two share vocabulary. A pin also
promises less than a spend ceiling. We treat effort as guidance and the request's `max_tokens` as
the hard ceiling, and that ceiling binds one response, not input, cache reads, or the further
requests an agentic lane makes. No documented skill or subagent frontmatter field reaches it:
`maxTurns` bounds agentic turns, not tokens, and has no skill counterpart. So a lane wanting to
spend less lowers `effort` knowing it is guidance, and a hard cap is imposed by whoever builds the
request.

- **Pointer:** for how thinking and effort relate, see
  [thinking and effort](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-effort);
  for the frontmatter fields, see
  [subagent frontmatter](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)
  and [skill frontmatter](https://code.claude.com/docs/en/skills#frontmatter-reference).
- **As of:** 2026-08-03.
- **Recheck trigger:** the accepted `effort` value set changes on the model-config or effort page,
  or either frontmatter field list gains a token cap.

Checking the value set mechanically stays deferred: a lint rule's source of truth is the harness's
own accepted-value list, which this section deliberately does not restate.

Session-level effort is the consumer's own knob, out of plugin scope: plugins never set session
effort. A plugin may advise a session level for a phase of work, but it never changes the user's
session level or saved level (Pointer: for how a level is set and saved, see
[model config: set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level);
for the ultracode setting, see
[model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level).
As of: 2026-10-01. Recheck trigger: any new model on Claude Code's model page, or a new way to set
or save a level).

One exception, scoped to frontmatter: a skill or agent may pin `effort`, because the pin holds only
while that skill or agent is active and never changes the user's session or saved level.

- **Pointer:** for the skill field, see
  [skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference);
  for the agent field, see
  [subagents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields).
- **As of:** 2026-10-02.
- **Recheck trigger:** either field starts persisting a level past the active skill or agent, or
  stops overriding the session level.

### Effort floor

Code-changing or verifying work runs at `medium` effort or above, on every model that supports
effort. Where this repository sets effort, in an agent's or a skill's frontmatter, a lane that
changes code or verifies a change never pins below `medium`; `low` is only for chat-like exchanges
and read-only mechanical work. The floor is stated as a level, not a model, because an alias can
resolve to a model with a different default, or with no effort support, depending on the provider
and the release.

- **Pointer:** for which models support effort and each one's default, see
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level);
  for what each level fits, see
  [model config: choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level);
  for what each alias resolves to per provider, see
  [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases).
- **As of:** 2026-10-01.
- **Recheck trigger:** any new model on Claude Code's model page, or the effort section changes
  which models support effort.

### Declared patterns

Conformance is declared in the skill text itself, in one of two greppable forms: **delegation
wording** (the POSIX ERE `fresh[- ]context` on a line that also names the worker or dispatch,
plus the ladder conventions above) or an **exemption directive** (`<!-- fresh-eyes-exempt: <class> -- <reason> -->`, closed class set
`deterministic-gate` | `external-input` | `deferred`). The mechanical contract, covering grammar,
classes, canonical wording, and check semantics, is owned by `/skill-quality:check`, whose conformance check
points third-party authors at that spec; this section carries the rationale and defers the spec
there (convention-registry row above). The declaration anchors in each skill's own scanned files
even when the judgment mechanics live in a plugin-level shared spoke, because the generic checker
cannot assume a plugin layout.

## Authoritative references

The complete categorized index of plugin-relevant official pages is
[`docs/official-docs.md`](official-docs.md); `https://code.claude.com/docs/llms.txt` is the
authoritative self-updating master list. Each list below names the pages this document rests on
and the topics we read each one for. Recheck trigger for both lists: a page moves, or stops
covering a topic named beside it. The first list is as of 2026-08-10 (the
`melodic-software/standards` entries are not Claude Code pages and carry no date):

- [Create plugins](https://code.claude.com/docs/en/plugins): plugin structure incl. `bin/` and
  plugin `settings.json`, namespaces, testing, and migration.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference): component schemas,
  `userConfig`, experimental components, version management, cache isolation, persistent data.
- [Skills](https://code.claude.com/docs/en/skills): frontmatter reference and skill lifecycle.
- [Hooks reference](https://code.claude.com/docs/en/hooks): exec form vs shell form, event list,
  `Setup` event, skill-scoped hooks.
- [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies): constraints, release
  tags, bundles.
- [Claude Code settings](https://code.claude.com/docs/en/settings): settings scopes, precedence, and
  the special storage and read scopes of `pluginConfigs`.
- `melodic-software/standards` `conventions/engineering/shareable-artifact-design.md`: the
  artifact-agnostic consumer-facing design doctrine the design boundary, configuration ownership,
  and setup contract above specialize for plugins.
- `melodic-software/standards` engineering philosophy and cross-platform review criteria: repository
  design and verification policy.

As of 2026-07-17:

- [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies): the `dependencies`
  array, automatic installation, and version constraints.
- [Skills](https://code.claude.com/docs/en/skills): command-name derivation and the plugin skill
  namespace.
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):
  naming-convention guidance this document deviates from deliberately.
- [Agent Skills specification](https://agentskills.io/specification): `name` field constraints and
  directory matching.
