---
description: "Enumerate the complete Claude Code ECOSYSTEM this machine can invoke — every built-in CLI command with its aliases and hidden/gated status, every bundled skill, and every component of every installed plugin (skills, agents, commands, hooks, MCP servers, LSP servers, workflows, output styles, themes, monitors, bin) across all marketplaces. Reads the shipped binary because the official docs publish no built-in command list. Reports; never changes anything. Use when: 'what slash commands do I have', 'list all my skills', 'what agents are available', 'show me every plugin component', 'what does Claude Code ship built-in', 'is /foo a real command', 'what changed after the update', 'show me only the plugin ones', 'what does marketplace X give me'. Not for: auditing the install DIRECTORY on disk (use /claude-ops:audit-install-state), updating or converging the plugin fleet (use /claude-ops:plugins), or checking settings and permission drift (use /claude-config:audit)."
argument-hint: "[--builtin|--plugins|--bundled|--agents|--hooks] [--marketplace <name>] [--diff <file>] — or just ask in words"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Enumerate every command, skill, agent, and plugin component this machine can invoke
  cadence: weekly
---

## Purpose

Answers one question completely: **what can this machine actually invoke, and where did each thing come from?**

That question has no single documented answer. Claude Code's own documentation does not publish a
list of its built-in slash commands — `docs/en/slash-commands` now serves the skills page, because
commands were merged into skills — so the only complete source for the built-in surface is the
shipped executable. Plugin components, by contrast, are on disk and enumerable directly. This skill
reads both and keeps them clearly separated, because they are evidence of different quality.

The report is an inventory, not a judgement. Nothing here says a component is stale, misconfigured,
or wrong; the neighbours below own those verdicts.

## Scope boundary

| Question | Owner |
|---|---|
| What can I invoke, and where did it come from? | **this skill** |
| Is my install directory healthy — what is stale, what does the product manage? | `/claude-ops:audit-install-state` |
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

Python 3.11+ is the only requirement — no `strings`, no `jq`, no PowerShell, no third-party
packages. The run takes a few seconds, dominated by reading the executable once.

Useful flags: `--binary <path>` (else auto-detected) · `--config-dir <path>` (else
`$CLAUDE_CONFIG_DIR`, else `~/.claude`) · `--binary-only` / `--disk-only` to skip a source.

**Extract once, filter at presentation.** The script always emits the whole inventory; the user's
filter selects what you *show*. Filtering in the script would mean a different extraction per
question and a cache that disagrees with itself. One JSON, many views.

## Resolving what the user asked for

Both spellings reach the same place — treat a flag and its sentence as identical requests.

| Flag | Sentences that mean it | Show |
|---|---|---|
| `--builtin` | "built-in commands", "what ships with Claude Code", "is /foo real" | `builtin_commands` |
| `--bundled` | "bundled skills", "Anthropic's skills" | `bundled_skills` |
| `--plugins` | "only the plugin ones", "what did my plugins add" | `disk.marketplaces` |
| `--marketplace <name>` | "what does melodic-software give me" | that marketplace only |
| `--agents` | "what agents do I have" | agents across every source |
| `--hooks` | "what hooks are wired", "what's hooked" | hooks across every source |
| `--diff <file>` | "what changed after the update" | this run against a saved one |

With no argument, report every section at summary depth and offer to expand one. A full unfiltered
listing runs to several hundred rows, which buries the answer to whatever prompted the question.

Two habits worth keeping. When a name the user asked about does not appear, say which sources were
searched — absence from a filtered view is not absence from the machine. And when they ask about one
name, answer it directly first, then offer the surrounding list.

## Report structure

Lead with the shape of the answer, then the rows.

```
# Claude Code inventory — <host>, <date>

## Summary
<n> built-in commands · <n> bundled skills · <n> plugins across <n> marketplaces · <n> enabled

## Built-in CLI commands (<n>)
One per line, alphabetical, with aliases and hidden/gated markers.

## Bundled skills (<n>)
One per line, alphabetical.

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
behave differently — different namespacing, different update path, different removal story — and a
merged list is unusable for deciding what to do about any of them.

## Reading the evidence honestly

**Extraction proves a command exists in the build, not that you can type it.** `hidden` and `gated`
mean a runtime predicate decides visibility from plan, platform, session type, or config. Report the
marker; never promote "present in the binary" to "available to you". `/skills` and `/help` are the
authority on what resolves right now.

**`enabledPlugins: false` does not settle enablement.** It spans several scopes, and a plugin's
hooks live in its own manifest. Report the map as read and route the verdict to
`/claude-ops:plugins audit`.

**Counts that disagree are data, not noise.** `bundled_skill_notes` carries `registrations_seen`
alongside `resolved`. When they differ, some registration used a dynamically computed name; say so
rather than reporting the smaller number as complete.

**A marketplace checkout is not an installation, and neither is enablement.** Three different sets:
a cached marketplace is a catalog of what is *available*, `disk.installed_plugins` is what is
*present locally*, and `enabledPlugins` governs what *loads*. They routinely disagree — report the
one the question is actually about, and say which you used.

**A hook script on disk is not a wired hook.** Project scope reports hook *events* declared in
settings, not files sitting in a `.claude/hooks/` directory. A script nothing references is dead
weight, and listing it as a hook repeats the same present-versus-active error.

## How the binary read works

The extraction is in `scripts/inventory.py`, and [reference/extraction.md](reference/extraction.md)
explains every choice in it — read that before changing the script or when a run reports a layout
error. The one thing worth knowing at the call site: the script resolves minified registrar names,
the bundle location, and each command's field boundaries **at runtime**, because all three change
between releases. Two earlier regex-only passes over this bundle produced lists that were wrong in
different ways, which is what the runtime resolution and the integrity block exist to prevent.

The script opens the binary read-only. It never writes to it and never executes it.

## Verifying an upstream claim

Any claim about what Claude Code itself ships must come from the raw markdown endpoint — `curl -sSL`
`https://code.claude.com/docs/en/plugins-reference.md` to a file, then read the file. A summarizing
fetch returns a small model's answer *about* the page, so absence from that answer is not evidence
of absence.

Two upstream facts this skill depends on, each with the trigger that obliges re-deriving it:

| Claim | Basis | Recheck trigger | Verified |
|---|---|---|---|
| The docs publish no built-in slash-command list | `docs/en/slash-commands.md` and `docs/en/skills.md` return byte-identical content | Those two stop being identical, or either grows a command table | 2026-08-11 |
| The plugin component set is skills, commands, agents, workflows, output-styles, themes, monitors, hooks, bin, settings.json, .mcp.json, .lsp.json, dependencies | `docs/en/plugins-reference.md` manifest schema and standard plugin layout | The manifest schema gains or drops a component key | 2026-08-11 |

The changelog at `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` is the
fastest way to explain a diff between two runs — commands appear and disappear between releases.
Cite the version that introduced or removed a command rather than asserting it changed.

## Staying current as Claude Code ships

Claude Code updates constantly, and this skill reads its internals. The design assumption is not
that the build holds still — it is that **drift must never be silent**.

**Read the integrity block before quoting any number.** Every run carries one, and it states whether
the counts are verified or merely believed:

| Status | Means | Do |
|---|---|---|
| `ok` | Build matches the last validated release, every check passed | Report counts as totals |
| `degraded` | Extraction worked, but something is unaccounted for | Report counts as **floors**, and say what is unaccounted for |
| `broken` | A canary command is missing or nothing resolved | Do not report counts at all; say the extractor needs updating |

The distinction earns its keep because the dangerous failure is not a crash. A renamed export throws
and is obvious. A *new registration path* returns a clean, confident, short list — so the checks are
built to catch shortfall rather than error: canary commands that have shipped in every build, a
minimum ratio of resolved commands to registration tokens present, a sweep for registrar-shaped
exports the script does not know about, and the resolved-versus-seen gap on bundled skills.

**Run the drift check on a schedule, not on incident:**

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" --self-check
```

It prints one verdict line and exits `0` ok, `1` broken, `2` degraded — so it works as a CI gate, a
loop-lane step, or a post-update check without parsing JSON. The natural trigger is a CLI release:
`/claude-ops:changelog` already ingests those, and this is the check to run when it reports one.

**What a maintainer actually updates.** Most releases need no change — registrar names are
discovered, not hardcoded, and the bundle is found by export name rather than layout. When a run
does go `degraded` or `broken`, each verdict maps to one edit in `scripts/inventory.py`; the verdict
table in [reference/extraction.md](reference/extraction.md) carries the mapping. After revalidating
against the new build, bump `VALIDATED_AGAINST` to that version — it is the one constant that turns
"believed" back into "verified".

**For downstream consumers.** A consumer on an older plugin version against a newer CLI gets a
`degraded` or `broken` verdict rather than a wrong answer — the report tells on itself, which is the
property that makes shipping this safe. Fixes reach them the ordinary way: bump the plugin version,
and `/claude-ops:plugins sync` carries it. Never quietly widen a count to make a status look better;
the stale-but-honest report is the one a consumer can act on.

## Gotchas

- **A name in the build is not always a command.** Verified cases: `alias` is a sandboxed-shell
  builtin beside `nohup` and `timeout`; `todos` is a session-cleanup hook. Both match a naive
  `name:"…"` search. The brace-depth reader plus the `type:` requirement is what excludes them.
- **An alias is not a separate command.** `/cost` and `/stats` are aliases of `/usage`, not three
  commands. Count commands once and list aliases beside them, or your total will drift from `/help`.
- **A bundled skill can also appear as a command object.** When a name registers as both, the skill
  registration wins; the script drops the duplicate so one capability is not counted twice.
- **An npm install has no embedded bundle.** The launcher script is small and loads its bundle
  elsewhere. The script reports this rather than parsing a shim, and the disk half still works.
- **The bundled-skills directory is a lazy cache.** Skills are extracted there on first use, so it
  under-reports. It is never the source for the bundled-skill list.
