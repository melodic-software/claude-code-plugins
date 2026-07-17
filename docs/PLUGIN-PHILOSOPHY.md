# Plugin philosophy

This is the durable design policy for plugins in this marketplace. The
[migration playbook](MIGRATION-PLAYBOOK.md) applies it to migration and release work; the
[plugin artifact protocol](PLUGIN-ARTIFACT-PROTOCOL.md) defines the shared artifact seam used by
lifecycle plugins.

## Design boundary

A plugin is a reusable, independently useful vertical slice of one cohesive capability. It must work
outside the repository and organization that produced it. Publisher metadata may identify its source;
runtime behavior must not depend on publisher names, organization-specific environment variables,
repository names, absolute machine paths, or an undocumented consumer layout.

Keep plugins horizontally decoupled:

- A plugin owns its skills, hooks, agents, scripts, dependencies, and state.
- It never imports files from a sibling plugin or discovers another plugin's installation directory.
- Cooperation uses a documented public seam: an artifact contract, an explicit invocation argument,
  or an optional namespaced skill invocation.
- Every plugin remains useful alone. If an optional collaborator is absent, use a documented fallback
  or report the missing optional capability clearly.
- A reference to another plugin is either declared or guarded. A collaborator the plugin's contract
  requires is listed in the manifest `dependencies` array, and Claude Code installs it automatically;
  an optional collaborator is invoked behind an "if installed" guard with the documented fallback
  above. A bare unguarded cross-plugin reference is a defect.

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

Nouns are reserved for knowledge routers (`principles`, `methodology`) and lifecycle-object routers
(`worktree`, `pull-request`). Two further documented exceptions: a single-skill vendor-CLI wrapper
repeats its tool name (`firecrawl:firecrawl`), and a `-deep` suffix marks the heavier
isolated-execution tier of a sibling skill (`explore`/`explore-deep`).

The frontmatter `name` always matches the skill directory name, in the character set the Agent
Skills specification allows. Never degrade a name to dodge a built-in command: plugin skills are
namespaced and cannot collide with other levels. When a name matches a built-in, the bare token
still belongs to the built-in; the namespaced form is the plugin skill's only command.

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

For project configuration, use neutral repository-relative paths anchored at
`${CLAUDE_PROJECT_DIR}`. Validate configured paths at the boundary, reject absolute paths and traversal
when the contract requires containment, and document precedence. Do not add an environment variable
merely to create a second configuration channel.

## Setup is explicit and repeatable

A configurable plugin provides an explicit `setup` or `configure` skill with
`disable-model-invocation: true`. Setup must be:

- idempotent and safe to rerun;
- transparent about what it inferred, changed, skipped, or could not verify;
- limited to configuration the plugin owns;
- safe for existing files, preserving unrelated user content; and
- non-interactive when complete arguments are supplied, so automation and headless use remain possible.

Setup may inspect the repository and create or update the plugin's tracked project configuration. It
must not write into the installed plugin cache, mutate Claude Code user settings, or write
`pluginConfigs`. Personal scalar configuration is collected through Claude Code's native plugin
configuration surface.

## Prerequisites and failure behavior

Declare every required runtime, shell, CLI, service, credential, and platform constraint at the point
of use and in the plugin README. Never download or execute an undeclared tool as an incidental fallback.

Classify absence deliberately:

- **Required for correctness:** stop at the entry point with a concise remediation message.
- **Required for an optional feature:** warn visibly, skip only that feature, and continue with the
  documented reduced result.
- **Not applicable:** exit quietly and successfully.

Hooks follow the event's official control contract. Use a blocking result only when the event can still
be blocked and the hook is enforcing a policy. Advisory hooks surface a visible non-blocking diagnostic.
Do not swallow errors or claim success when the promised result was not produced.

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

## Authoritative references

Verified 2026-07-14:

- [Create plugins](https://code.claude.com/docs/en/plugins) — reusable plugins versus project-specific
  standalone configuration, namespaces, structure, testing, and migration.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — `userConfig`, plugin paths,
  cache isolation, and persistent plugin data.
- [Claude Code settings](https://code.claude.com/docs/en/settings) — settings scopes, precedence, and
  the special storage and read scopes of `pluginConfigs`.
- [Hooks reference](https://code.claude.com/docs/en/hooks) — exit-code visibility and blocking behavior.
- [Claude Code memory](https://code.claude.com/docs/en/memory) — project, user, and local instruction
  scopes.
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
