---
description: "List every Claude Code surface this machine can invoke: built-in commands, subagents, and tools, bundled skills and workflows, and installed plugin components. Use when: 'what slash commands do I have', 'list all my skills', 'what agents are available', 'show me every plugin component', 'what does Claude Code ship built-in', 'is /foo a real command', 'is /foo documented', 'what changed after the update', 'show me only the plugin ones', 'what does marketplace X give me'. On-disk audit: /claude-ops:audit-install-state."
argument-hint: "[--builtin|--plugins|--bundled|--agents|--tools|--hooks|--docs] [--marketplace <m>] [--diff <f>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Enumerate every command, skill, agent, and plugin component this machine can invoke
  cadence: weekly
---

**Arguments.** `[--builtin|--plugins|--bundled|--agents|--tools|--hooks|--docs] [--marketplace <m>] [--diff <f>]`. Full form: [--builtin|--plugins|--bundled|--agents|--tools|--hooks|--docs] [--marketplace <name>] [--diff <file>], or just ask in words

## Purpose

Answers one question completely: **what can this machine actually invoke, and where did each thing come from?**

That question has no single documented answer. The commands page publishes a table of built-in
commands, but the shipped executable registers names the table omits, so the executable is the
only complete source for the built-in surface and the page is a cross-check (`--docs`). Plugin
components, by contrast, are on disk and enumerable directly. This skill reads both and keeps them
clearly separated, because they are evidence of different quality.

The report is an inventory, not a judgment. Nothing here says a component is stale, misconfigured,
or wrong; the neighbors below own those verdicts.

## Scope boundary

| Question | Owner |
|---|---|
| What can I invoke, and where did it come from? | **this skill** |
| Is my install directory healthy. What is stale, what does the product manage? | `/claude-ops:audit-install-state` |
| Is the plugin fleet current, and at what scope? | `/claude-ops:plugins audit` |
| Are settings, hooks, permissions, and MCP config correct? | `/claude-config:audit` |
| Which permission scopes hold which rules? | `/claude-config:audit-permission-state` |

The distinction that matters most: `audit-install-state` inventories **files on disk**, this skill
inventories **capabilities that resolve**. A plugin can be present on disk and contribute nothing
because it is disabled, and a built-in command can be fully live while existing nowhere on disk.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" --out ./claude-inventory.json
```

Python 3.11+ is the only requirement. No `strings`, no `jq`, no PowerShell, no third-party
packages. The run takes about fifteen seconds, dominated by reading and tokenizing the executable
once.

Useful flags: `--binary <path>` (else auto-detected) · `--config-dir <path>` (else
`$CLAUDE_CONFIG_DIR`, else `~/.claude`) · `--binary-only` / `--disk-only` to skip a source ·
`--docs` to add the `docs_crosscheck` block, fetching the commands page, the changelog, and the
tools reference · `--docs-file <path>` / `--changelog-file <path>` / `--tools-docs-file <path>` to
read one from a file instead (each implies `--docs`). A failed fetch marks that block `unavailable`
or `degraded` and never fails the run.

**Extract once, filter at presentation.** The script always emits the whole inventory; the user's
filter selects what you *show*. Filtering in the script would mean a different extraction per
question and a cache that disagrees with itself. One JSON, many views.

## Resolving what the user asked for

Both spellings reach the same place. Treat a flag and its sentence as identical requests.

| Flag | Sentences that mean it | Show |
|---|---|---|
| `--builtin` | "built-in commands", "what ships with Claude Code", "is /foo real" | `builtin_commands` |
| `--bundled` | "bundled skills", "Anthropic's skills", "bundled workflows" | `bundled_skills`, `bundled_workflows` |
| `--docs` | "is /foo documented", "what's undocumented", "was /foo removed" | `docs_crosscheck` |
| `--plugins` | "only the plugin ones", "what did my plugins add" | `disk.marketplaces` |
| `--marketplace <name>` | "what does melodic-software give me" | that marketplace only |
| `--agents` | "what agents do I have", "what subagent types ship built-in" | `builtin_agents`, then agents across every other source |
| `--tools` | "what tools does Claude Code have", "is Monitor a real tool" | `builtin_tools` |
| `--hooks` | "what hooks are wired", "what's hooked" | hooks across every source |
| `--diff <file>` | "what changed after the update" | this run against a saved one |

With no argument, report every section at summary depth and offer to expand one. A full unfiltered
listing runs to several hundred rows, which buries the answer to whatever prompted the question.

Two habits worth keeping. When a name the user asked about does not appear, say which sources were
searched. Absence from a filtered view is not absence from the machine. And when they ask about one
name, answer it directly first, then offer the surrounding list.

## Report structure

Lead with the shape of the answer, then the rows.

```
# Claude Code inventory — <host>, <date>

## Summary
<n> built-in commands · <n> bundled skills · <n> plugins across <n> marketplaces · <n> enabled

## Built-in CLI commands (<n>)
One per line, alphabetical: name, argument hint, description, aliases, hidden/gated markers, and
the Invocable-by marker.

## Bundled skills (<n>)
One per line, alphabetical, in the same shape.

## Bundled workflows (<n>)
One per line: name, description, phases, Invocable-by marker.

## Built-in subagents (<n>)
One per line: name, description (`whenToUse`), roster (`default`, `conditional`, `absent`), model,
tools or disallowed tools with their `_source`, Invocable-by marker.

## Built-in tools (<n>, plus <n> factory-built)
One per line: name, description or search hint, `deferred` / `always_load` (null means decided
per session), gated marker, aliases. Name the factory count from `builtin_tool_notes`.

## Docs cross-check
Only with --docs. Counts per status, then the names in every status except `documented` and
`alias`, each with its docs text; kind mismatches and alias disagreements after. Say that the
changelog columns are a heuristic. Then the nested `tools` block the same way, with its own status.

## Plugin components
Installed plugins grouped by marketplace, then plugin, with a component-type breakdown.
Catalog-only entries — offered by a cached marketplace but not installed — are listed separately.

## Project scope
Skills, agents, and wired hook events from the current project's `.claude` tree, when present.

## Provenance
Which source produced which section, and anything the run could not resolve.
```

One per line, alphabetical, is the default for every list. The point of this report is scanning for
a name; a prose paragraph or a multi-column grid defeats that.

Never merge the sections into one list. A built-in command, a bundled skill, and a plugin skill
behave differently, different namespacing, different update path, different removal story, and a
merged list is unusable for deciding what to do about any of them.

**Invocable by** comes from `user_invocable` and `model_invocable`, present on every command,
bundled-skill, and bundled-workflow record:

| `user_invocable` | `model_invocable` | Marker |
|---|---|---|
| true | true | model+user |
| true | false | user-only |
| false | true | model-only |
| any | null | runtime (say which flag decides it, from `flag_driven`) |

`model_invocable` is true only for what the Skill tool admits: a `type:"prompt"` command declaring
`source:"builtin"`, or a bundled skill, in each case without `disableModelInvocation`. `local` and
`local-jsx` commands are false. A per-machine skill override in settings can still turn one off;
that is config, and the inventory does not read it. A built-in subagent in the default or
conditional roster is model+user; one outside the roster (`absent`, spawned only by a feature) is
runtime. A built-in tool is model-only.

## Reading the evidence honestly

**Extraction proves a command exists in the build, not that you can type it.** `hidden` and `gated`
mean a runtime predicate decides visibility from plan, platform, session type, or config. Report the
marker; never promote "present in the binary" to "available to you". `/skills` and `/help` are the
authority on what resolves right now.

**`enabledPlugins: false` does not settle enablement.** It spans several scopes, and a plugin's
hooks live in its own manifest. Report the map as read and tell the user to run
`/claude-ops:plugins audit` for the verdict.

**Counts that disagree are data, not noise.** `bundled_skill_notes` carries `registrations_seen`
alongside `resolved`, and `dynamic_roster` when a registration builds its names at runtime (a loop
over a table, or a template literal). When seen exceeds resolved, say so rather than reporting the
smaller number as complete.

**A description or hint can depend on the session.** `description` and `argument_hint` each
carry a `_source` (`literal`, `template`, `constant`, `call`, `getter`, `arrow`, `roster`,
`unresolved`, `absent`). A getter or ternary yields `_variants`; the value shown is the
fallthrough branch, which is what a default session displays. An ellipsis marks a runtime
substitution. `unresolved` means the text is computed at runtime: say so rather than leave the
line blank. `integrity.undetermined` lists every name with a null invocability field or an
unresolved description or hint.

**The docs classify; the binary decides what exists.** `docs_crosscheck.names.<name>.status` is one
of `documented`, `undocumented`, `alias`, `docs_alias_but_registered`, `removed_in_docs`,
`removed_in_docs_but_registered`, `docs_only`. An `undocumented` name can be internal plumbing or a
gated feature, and a `docs_only` name can be one this build dropped; neither is a defect by
itself. `kind_mismatch` means the page and the binary disagree on command versus skill versus
workflow. The `changelog` field is a heuristic: the earliest version mentioning `/name`, and lines
using an add, rename, remove, deprecate, or alias word.

**One name can be two registrations.** When two distinct bundled registrations share a name, the
extraction keeps both as a list under that name with `collision: true`, and
`bundled_skill_notes.collisions` names them. Report each registration on its own line with its
description and invocation fields; never pick one and present it as the name's single meaning.

**A roster status is not availability, and a tool definition is not a loaded tool.** An agent's
`roster` says whether the default roster function registers it unconditionally (`default`), under a
runtime condition (`conditional`), or not at all (`absent`: a feature such as fork, coordinator
mode, or a workflow spawns it). A tool's `deferred` says whether it loads behind tool search; null
means a getter decides per session. Tools built by a factory at runtime (connector listings,
artifact family members) have no static name: `builtin_tool_notes.factory_definitions` counts them,
so say the named list excludes them rather than reporting it as every tool.

**A marketplace checkout is not an installation, and neither is enablement.** Three different sets:
a cached marketplace is a catalog of what is *available*, `disk.installed_plugins` is what is
*present locally*, and `enabledPlugins` governs what *loads*. They routinely disagree. Report the
one the question is actually about, and say which you used.

**A hook script on disk is not a wired hook.** Project scope reports hook *events* declared in
settings, not files sitting in a `.claude/hooks/` directory. A script nothing references is dead
weight, and listing it as a hook repeats the same present-versus-active error.

## How the binary read works

The extraction is in `scripts/inventory.py`, and [reference/extraction.md](reference/extraction.md)
explains every choice in it. Read that before changing the script or when a run reports a layout
error. The one thing worth knowing at the call site: the script resolves minified registrar names,
the bundle location, and each command's field boundaries **at runtime**, because all three change
between releases. A regex-only pass over this bundle produces a list that is wrong in ways that look
complete, which is what the runtime resolution and the integrity block exist to prevent.

The script opens the binary read-only. It never writes to it and never executes it.

## Verifying an upstream claim

Any claim about what Claude Code itself ships must come from the raw markdown endpoint. `curl -sSL`
`https://code.claude.com/docs/en/plugins-reference.md` to a file, then read the file. A summarizing
fetch returns a small model's answer *about* the page, so absence from that answer is not evidence
of absence.

Upstream facts this skill depends on, each with the trigger that obliges re-deriving it:

| Claim | Basis | Recheck trigger | Verified |
|---|---|---|---|
| The commands page publishes a partial built-in table, so it is a cross-check and the binary stays the source: its "All commands" table carries rows for commands, aliases, removed commands, and **Skill**/**Workflow** markers, and the binary registers names it omits | `docs/en/commands.md` parsed by `--docs` (115 rows) against a `--binary-only --docs` run on this machine, which classed 39 registered names `undocumented` | The commands page drops or restructures its table (the docs block goes `broken`), or the undocumented count reaches zero | 2026-09-29, Claude Code 2.1.284 |
| The plugin component set is skills, commands, agents, workflows, output-styles, themes, monitors, hooks, bin, settings.json, .mcp.json, .lsp.json, dependencies; the manifest also declares `channels`, each bound to one of the plugin's MCP servers, which this skill does not scan | `docs/en/plugins-reference.md` manifest schema and standard plugin layout table | The manifest schema gains or drops a component key | 2026-09-29 |
| A user reaches a built-in or custom subagent by @-mention or `--agent`, and the model by the Agent tool; the page documents Explore, Plan, general-purpose, claude, statusline-setup, and claude-code-guide, and the binary also defines fork, web-fetch, worker, workflow-subagent, and comment-thread-analyst | `docs/en/sub-agents.md` ("Built-in subagents", "Invoke subagents explicitly") against a `--binary-only` run on this machine | The page changes its built-in list or invocation patterns, or a run's `builtin_agents` names change | 2026-09-29, Claude Code 2.1.285 |
| The tools reference table lists tools by exact name and is partial: 45 of 80 statically named tools are in it, and it keeps `TaskOutput`, which the binary only names in a retired-names list | `docs/en/tools-reference.md` parsed by `--docs` (46 rows) against a `--binary-only` run on this machine | The tools table restructures (the nested `tools` block goes `broken`) or the `undocumented` count reaches zero | 2026-09-29, Claude Code 2.1.285 |

The changelog at `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` is the
fastest way to explain a diff between two runs; `--docs` attaches its per-name history. Commands
appear and disappear between releases. Cite the changelog line that introduced or removed a
command rather than asserting it changed.

## Staying current as Claude Code ships

Claude Code updates constantly, and this skill reads its internals. The design assumption is not
that the build holds still. It is that **drift must never be silent**.

**Read the integrity block before quoting any number, lane by lane.** Every run carries one, and it
states per lane (`builtin_commands`, `bundled_skills`, `plugin_backed`, `bundled_workflows`,
`builtin_agents`, `builtin_tools`) whether that lane's counts are verified or merely believed; the top-level status is the worst lane.
`docs_crosscheck` carries its own `status` (`ok`, `degraded`, `broken`, `unavailable`) and never
changes the integrity status or the self-check exit code:

| Status | Means | Do |
|---|---|---|
| `ok` | Build matches the last validated release, every check passed | Report that lane's counts as totals |
| `degraded` | Extraction worked, but something is unaccounted for | Report that lane's counts as **floors**, and say what is unaccounted for |
| `broken` | A canary is missing or nothing resolved in that lane | Do not report that lane's counts at all; name the lane and its cause; the other lanes' counts stand |

A single broken lane makes the top level `degraded`, not `broken`, so a healthy command list is
never withheld because the bundled-skill lane failed. Top-level `broken` means every lane is broken
or the binary could not be read.

The distinction earns its keep because the dangerous failure is not a crash. A renamed export throws
and is obvious. A *new registration path* returns a clean, confident, short list, so the checks are
built to catch shortfall rather than error: canary commands, a canary workflow, canary subagents
and tools, a minimum ratio of resolved commands to registration tokens present, a sweep for
registrar-shaped exports the script does not know about, the resolved-versus-seen gap on bundled
skills, and unresolved subagent and tool names.

**Run the drift check on a schedule, not on incident:**

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" --self-check
```

It prints one verdict line and exits `0` ok, `1` broken, `3` degraded, so it works as a CI gate, a
loop-lane step, or a post-update check without parsing JSON. `2` is left to argparse for a usage
error, so a mistyped flag can never be mistaken for a degraded run. The natural trigger is a CLI release:
`/claude-ops:changelog apply` runs it after integrating one, with a `--docs` extraction it diffs
against the previous run's, and files a work item when the verdict is not `ok`.

**What a maintainer actually updates.** Most releases need no change. Registrar names are
discovered, not hardcoded, and the bundle is found by export name rather than layout. When a run
does go `degraded` or `broken`, each verdict maps to one edit in `scripts/inventory.py`; the verdict
table in [reference/extraction.md](reference/extraction.md) carries the mapping. After revalidating
against the new build, bump `VALIDATED_AGAINST` to that version. It is the one constant that turns
"believed" back into "verified".

**For downstream consumers.** A consumer on an older plugin version against a newer CLI gets a
`degraded` or `broken` verdict rather than a wrong answer, the report tells on itself, which is the
property that makes shipping this safe. Fixes reach them the ordinary way: bump the plugin version,
and `/claude-ops:plugins sync` carries it. Never quietly widen a count to make a status look better;
the stale-but-honest report is the one a consumer can act on.

## Next

/claude-ops:audit-native-overlap

It reads this inventory's invocability, argument-hint, and workflow fields to find where local
skills duplicate a native surface.

## Gotchas

- **A name in the build is not always a command.** Strings such as `alias` and `todos` match a
  naive `name:"…"` search and are not commands. The brace-depth reader plus the `type:` requirement
  is what excludes them. Verified 2026-09-29 against Claude Code 2.1.284, by running
  `inventory.py --binary-only` on this machine: neither name appears under `builtin_commands`.
  Recheck when the extractor's `type:` requirement changes or a release adds a command by either
  name.
- **An alias is not a separate command.** `/cost` and `/stats` are aliases of `/usage`, not three
  commands. Count commands once and list aliases beside them, or your total will drift from `/help`.
  Basis: <https://code.claude.com/docs/en/commands> carries the rows "`/cost` | Alias for `/usage`"
  and "`/stats` | Alias for `/usage`", and a run of `inventory.py --binary-only` on this machine
  reports `usage` with aliases `cost` and `stats`. Verified 2026-09-29 against Claude Code 2.1.284
  and that page as fetched that day. Recheck when the commands page changes either row or the
  extraction reports a different alias set for `usage`.
- **A command in the docs can be a skill in the binary.** The commands page lists `/schedule` as a
  command; the binary registers it as a bundled skill, so `docs_crosscheck` flags `kind_mismatch`.
  Report the binary's kind, since it decides namespacing and model invocability. Verified
  2026-09-29 against Claude Code 2.1.284 by a `--binary-only --docs` run on this machine. Recheck
  when the page adds a **Skill** marker to `/schedule` or the binary registers it as a command.
- **A bundled skill can also appear as a command object.** When a name registers as both, the skill
  registration wins; the script drops the duplicate so one capability is not counted twice.
- **An npm install has no embedded bundle.** The launcher script is small and loads its bundle
  elsewhere. The script reports this rather than parsing a shim, and the disk half still works.
- **The bundled-skills directory is a lazy cache.** Skills are extracted there on first use, so it
  under-reports. It is never the source for the bundled-skill list.
