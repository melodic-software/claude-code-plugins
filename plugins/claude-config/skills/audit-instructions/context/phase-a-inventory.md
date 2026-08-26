# Phase A: Inventory

The surface-discovery layer of `/claude-config:audit-instructions`
([`../SKILL.md`](../SKILL.md)). Phase A enumerates every locally-owned instruction surface and
records one entry per surface; Phase B and Phase B2 both key off those records and cannot run
against a record set built any other way.

Enumerate the locally-owned instruction surfaces in scope. All paths below are current per the
official memory and `.claude`-directory docs (cited in the report's Sources line):

- User: resolve the root as `${CLAUDE_CONFIG_DIR:-~/.claude}` (setting `CLAUDE_CONFIG_DIR`
  relocates the whole `~/.claude` tree, so never hardcode `~/.claude`), then: `CLAUDE.md`,
  `rules/`, `skills/`, `agents/`, `output-styles/` under that root.
- Project: `./CLAUDE.md` or `./.claude/CLAUDE.md`, `./CLAUDE.local.md`, and every nested
  `CLAUDE.md` / `CLAUDE.local.md` in subdirectories of the project tree (Claude loads these on
  demand when it reads files in those directories, so walk the tree and do not stop at the root);
  `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.claude/output-styles/`.
- **Hook instruction text** configured in the project or user `settings.json`, **and in
  `.claude/settings.local.json`**, since local settings are a supported hook-configuration scope and a
  hook configured there gates the session as much as one configured anywhere else, **and declared
  in the `hooks:` frontmatter of the user- and project-scope skills and agents listed above**.
  Frontmatter is a supported hook location, live "while the component is active", so a hook in a
  locally owned `.claude/skills/**/SKILL.md` or `.claude/agents/*.md` is exactly as editable as the
  body it rides on and belongs in this set, not the read-only tier below, whose counterpart
  item covers the plugin cache and whose components no proposal may touch. Anchor a frontmatter hook at
  its own component file and frontmatter line rather than at a settings file. A subagent's
  frontmatter `Stop` hook is registered as `SubagentStop`, so resolve the effective event before
  pairing. Two kinds, and the discriminator is **whether the handler's output reaches this session's
  context, never the handler's `type`**
  ([reference/conflict-criteria.md](../reference/conflict-criteria.md) owns the distinction and its
  citations):
  - **Prompt-type hook text**: extract the prompt text. **What is compared is the gate, not the
    prose:** it goes to a separate evaluator model, never into this session's context, so it enters
    the comparison set as the act it blocks under its event and `matcher`. An `agent` handler is
    treated the same way.
  - **Context-injecting handler output**: a handler that prints to stdout on `SessionStart`,
    `UserPromptSubmit`, or `UserPromptExpansion`, or returns `hookSpecificOutput.additionalContext`
    on a main-session event that accepts it, puts that text in this session's context window. It is
    live instruction text and enters the comparison set as text. `command` is not an exclusion:
    `mcp_tool` shares the stdout channel and `http` the JSON one. Two bounds the criteria file
    states and cites: `SubagentStart` / `SubagentStop` `additionalContext` lands in **that
    subagent's** context, not this session's; and type decides registrability, so resolve the
    event×type pair before admitting a surface (`SessionStart` takes only `command` and `mcp_tool`).
    Where the output is not literal in the config, as with a handler that runs a script, record the
    surface with the emitting handler's event and `matcher` and mark the text `text-unresolved`
    rather than inventing it; a run inside the session it describes can read what was injected.

  Never carry a command line, token, or other secret-bearing value out of a settings file or a
  component's frontmatter into the report. Extract only the injected text, under the same
  no-secrets handling for both kinds and both locations.

**The tree does not decide what is live.** Before the inventory is handed to any lane, resolve the
session's effective liveness controls: the launch directory, the merged `claudeMdExcludes`,
`--setting-sources`, the additional-directory inputs, **and effective hook enablement**. Then drop
what they exclude and add the memory files they contribute. A walk of the project tree alone both
invents surfaces that are dead in this session and misses live ones that are not in the tree at all.
The controls, their official sources, and the `liveness-unresolved` marking for values an
out-of-session inventory cannot read are in
[reference/conflict-criteria.md](../reference/conflict-criteria.md), which owns the gate; name the
resolved controls in the report's tier-transparency line.

**Hook enablement is a liveness control, and configuration alone does not establish it.**
`disableAllHooks` turns off hooks without removing them, so an enabled plugin's handler, or one wired
in project settings, sits on disk unable to run, and a gate that cannot run this session constrains
nothing to compare against. Its reach is all hooks with exactly one carve-out, and that carve-out is
what makes this a per-scope resolution rather than a per-file one: set in user, project, or local
settings it cannot disable **managed** hooks, so managed hook text stays live against it and must not
be dropped with the rest; only a managed-level `disableAllHooks` reaches those too. The mirror
control, `allowManagedHooksOnly`, cuts the other way and blocks user, project, and plugin hooks,
exempting plugins force-enabled in managed `enabledPlugins`. Omit every hook surface they disable,
both kinds, prompt-type and context-injecting alike, since neither reaches this session when the
handler never fires, and report both resolved values with the other controls.

Exclude from the **editable** set, and hold for the routing subsection: auto-memory
(`projects/<project>/memory/` under the resolved user root, owned by `claude-memory`), installed
plugin-cache content,
and any managed materialization per the Scope boundary. Record each surface found and each surface
skipped, so the report's tier-transparency line can name both.

Some surfaces are inventoried **read-only** rather than excluded outright, because a later phase has
to compare against them even though no proposed edit may ever touch them. Read-only inventory changes
nothing about ownership: these surfaces still produce no proposal of their own, and a finding
involving one still carries the no-change representation and its routing recommendation.

- **Auto memory, when it is on**: the `MEMORY.md` entrypoint at the effective auto-memory location
  (the highest-precedence scope that sets `autoMemoryDirectory`, otherwise
  `projects/<project>/memory/` under the **resolved** user root above, never a hardcoded
  `~/.claude`, since `CLAUDE_CONFIG_DIR` moves `projects/` with the rest of the tree and a hardcoded
  default misses the live `MEMORY.md` and compares against a store the session no longer
  writes). **Resolve the effective enabled state first, by
  precedence rather than by any single scope's value.** `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative
  wherever it is set (`=1` off, `=0` on, even against `autoMemoryEnabled: false`); with the variable
  unset, apply settings precedence (managed > local > project > user) to `autoMemoryEnabled`, which
  defaults to on. Reading a lower-scope `false` as decisive would drop a `MEMORY.md` a
  higher-precedence scope re-enabled, and inventorying unconditionally would pair live instructions
  against a file left on disk after auto memory was turned off, the same defect as reading a
  disabled plugin's cache. `/claude-memory:stateless` owns this resolver; its `status` action reports
  the effective state, including a disagreement between the variable and the setting. When auto
  memory is on it loads into every session, and
  [reference/conflict-criteria.md](../reference/conflict-criteria.md) assigns every pair involving it to
  I15 precisely because `claude-memory`'s C6 does not read it, so excluding it outright would leave
  a `MEMORY.md`-versus-`CLAUDE.md` contradiction audited by neither skill. Only the content that
  actually loads is compared (the first 200 lines or 25KB); topic files beside it are read on demand
  and are not resident. Ownership is unchanged: `claude-memory` still owns auto memory, and a finding
  here routes there rather than editing it.
- **Each enabled agent's own memory, under that same gate**: an agent definition carrying a
  `memory` field gets its **own** memory directory, separate from the main conversation's and named
  per agent, and that subagent reads and writes its own `MEMORY.md` there. The field's value is the
  scope, and each scope has its own location: `user` → `agent-memory/<name-of-agent>/` under the
  **resolved** user root above (never a hardcoded `~/.claude`, for the reason the entry above gives),
  `project` → `.claude/agent-memory/<name-of-agent>/`, `local` →
  `.claude/agent-memory-local/<name-of-agent>/`.
  [reference/conflict-criteria.md](../reference/conflict-criteria.md) keeps an agent-definition-versus-
  its-own-memory contradiction in scope precisely because those two *do* co-reside in that subagent,
  so this inventory has to reach it: enumerate that `MEMORY.md` for every inventoried agent whose
  definition enables the field, under the same loaded-portion bound. The gate is the effective state
  resolved just above: subagent memory is part of auto memory, so with auto memory off the `memory`
  field has no effect and the subagent launches without the memory instructions or the memory tool
  access; an agent memory left on disk after the switch flipped is not inventoried.
  Read-only and `claude-memory`-owned exactly as the main entrypoint is.
- **Org-managed policy**: the managed-policy `CLAUDE.md`, any `claudeMd` value in managed settings,
  and hook instruction text configured in managed settings, of **both** kinds above. All three are
  live instruction text, and a managed hook contradicting a project skill is exactly the conflict I15
  explicitly owns; that comparison is impossible if the text is never read. Extract managed hook text
  under the same two-kind, no-secrets handling as the other settings scopes.
- **Upstream-owned instruction text that is nonetheless live**: skill bodies and agent definitions
  from the cache of an **enabled** plugin, hook instruction text of both kinds in an enabled
  plugin's `hooks/hooks.json` (a plugin is a supported hook location, so that text is as live as a
  settings-configured hook, and a plugin `SessionStart` handler injecting a standing behavioral
  block is the case that motivated the two-kind split), hooks declared in the frontmatter of an
  active skill or agent **from that cache** (a supported location, live "while the component is
  active"; the user- and project-scope counterparts are locally owned and are inventoried in the
  editable set above, not here), **the active
  output style when a plugin supplies it**, and any managed materialization. The output-style case
  is easy to miss because the user- and project-scope scans cannot reach the plugin cache: plugins
  ship styles in an
  `output-styles/` directory, and a plugin style with `force-for-plugin` applies "automatically
  whenever the plugin is enabled, without requiring users to select it", overriding the user's
  `outputStyle` setting ([output-styles](https://code.claude.com/docs/en/output-styles)). Resolve
  which style is actually active, a `force-for-plugin` style from the enabled set first, else the
  `outputStyle` value, which may itself name a plugin-supplied style, and inventory that one. Only
  the active style is resident, so the others stay out of the corpus. Enablement is
  the same gate for every plugin-sourced surface here: a disabled plugin's cache stays on disk while
  none of its components load, including a `force-for-plugin` style, which applies only while its
  plugin is enabled, so resolve effective `enabledPlugins` across settings scopes first and
  inventory only the
  plugins that resolve enabled. A cached body from a disabled plugin would put text Claude cannot
  load into the comparison corpus. Enablement alone is not enough to pick a directory: the cache can
  hold several versions of one plugin, and a plugin may be installed at more than one scope, so
  resolve the install record that is actually selected for this project and read **only** that
  version's path. An unselected or superseded cache directory is as unloadable as a disabled
  plugin's, and reading it would manufacture conflict and shadowing findings from text no session
  sees. An invoked plugin skill's
  instructions are in context alongside the project's own, so they can hold one side of a conflict.
  They are read for comparison only, prompt text only and no secret-bearing values: the existing
  exclusion from the editable set and the upstream-routing behavior are unchanged, so a finding here
  routes to the owning repository's tracker and proposes no in-place edit.
- **Every I15 counterpart outside the requested scope.** A scope argument narrows which surfaces may
  *produce* findings, not which are read: a conflict is a relation between two surfaces, so a run
  scoped to `skills` still inventories `CLAUDE.md`, rules, agents, hooks, and output styles as
  comparison counterparts. Findings still name both sides; the filter decides which side the run is
  auditing, never that the counterpart goes unread.
