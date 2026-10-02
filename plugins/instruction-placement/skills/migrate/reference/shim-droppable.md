# Is the shim droppable here?

`cutover-check` grades the build and the fleet. Whether this repository's users lose instructions
without the `@AGENTS.md` shim depends on the built-in `agents-md` loader and on settings no
repository can see, so removal is recommended only when **every** condition below holds.

Report each condition as held, failed or unknown, with its evidence. **Unknown is failed**: one
failed or unknown condition keeps the recommendation at "keep the shim" and names the condition.
This recommends, never removes: `remove-shims` and its `--confirm` gate stay the only path.

The quotes, dates and recheck triggers behind every condition are in [`sources.md`](sources.md),
"The built-in agents-md plugin".

## The conditions

| # | Holds when | Read it from |
|---|---|---|
| A | Nothing takes precedence over an `AGENTS.md`: no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` at or above the working directory other than the shims going, **and** no directory holding a nested `AGENTS.md` keeps a `.claude/CLAUDE.md` or a non-shim `CLAUDE.md` or `CLAUDE.local.md` of its own | The ancestor walk below, run from each directory contributors start sessions in; a Glob for the three names at every level inside the repository, tracked or not; and the operator for the other machines, whose ancestors (a `~/work/CLAUDE.md`) and uncommitted `CLAUDE.local.md` files this machine cannot see |
| B | **Project instructions** on this machine reads `AGENTS.md` with no `CLAUDE.md`: `claude-md-or-agents-md` (the default) or `claude-md-and-agents-md` | `pluginConfigs["agents-md@builtin"].options.instructionFiles` in user, managed and any `--settings` file; absent everywhere is the default. Project and local settings are ignored for it, so never read them as the answer. `claude-md` or `managed-only` fails |
| C | The loader is present and not disabled on this machine | `/harness-ops:inventory --bundled`, `builtin_plugins.cc-plugin-agents-md` (`in_loader`, `load`, `gated`, `gate_flags`), and no `enabledPlugins` entry set `false` in any scope for `agents-md@builtin` or the `id` the lane prints. Inventory absent, the lane `broken`, or the entry missing is unknown |
| D | Every user, machine and organization the repository serves reads `AGENTS.md` directly | Ask the operator, with the list below. Any yes, and any "don't know", fails |
| E | Nothing reachable through the `@` import graph of any `AGENTS.md`, root or nested, lies outside the working directory | The import-graph walk below, from every `AGENTS.md` and from each session start directory. Any `EXTERNAL`, `UNRESOLVED` or `DEPTH` row fails |
| F | No hook depends on `InstructionsLoaded` reporting the `AGENTS.md` load, or the operator accepts losing that | Every hook source, inside the repository and out: grep for `InstructionsLoaded` in the repository's `.claude/settings*.json`, hook scripts and CI; `~/.claude/settings.json` and `~/.claude/settings.local.json`; the managed settings file and any `managed-settings.d/` beside it; every `--settings` file contributors pass; each installed plugin's `hooks/hooks.json` and `plugin.json` `hooks` under `~/.claude/plugins/`; and the plugins loaded per session or outside an install: ask the operator whether contributors use `--plugin-dir`, `--plugin-url` or `CLAUDE_CODE_PLUGIN_DIRS`, and grep each directory or archive they name, plus every `~/.claude/skills/*/` that holds a `.claude-plugin/plugin.json`. A source that cannot be read here, and every other machine, is the operator's to answer. A hit the operator has not accepted, or a source nobody can answer for, fails |

B and C read this machine only. The setting is per user and no repository can ship it, so D is
where the operator answers for every other machine.

## The ancestor walk for condition A

Every directory from the working directory up to the filesystem root, not only the repository's
tracked files and `~/`: an ancestor such as `~/work/CLAUDE.md` is read instead of the `AGENTS.md`
below it. From each session start directory:

```bash
d=$(cd <start-dir> && pwd -P)
while :; do
  { [ -r "$d" ] && [ -x "$d" ]; } || printf 'UNREADABLE\t%s\n' "$d"
  for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
    [ -e "$d/$f" ] && printf 'FOUND\t%s\n' "$d/$f"
  done
  [ "$d" = / ] && break
  d=$(dirname "$d")
done
```

On Windows, walk to the drive root (`C:\`) the same way. Every `FOUND` row that is not one of the
shims `remove-shims` would remove fails A. `~/.claude/CLAUDE.md` is not on the list: the memory page
says it does not count, so its `FOUND` row is the one exemption. An `UNREADABLE` row is unknown,
and fails A.

## The import-graph walk for condition E

The walk reuses this plugin's own import model in `<plugin-root>/scripts/lib/discover.sh`, the
one `ip_index_target_loaded` runs on: `_ip_imports_of` parses a file's `@` imports (fenced code and
inline code spans skipped, `~/` and relative targets resolved) and `_ip_reaches` bounds the walk at
four hops, the loader's limit. Run it once per session start directory, over every `AGENTS.md`
in the repository:

```bash
. <plugin-root>/scripts/lib/discover.sh
base=$(cd <start-dir> && pwd -P)
e_walk() { # <file> <its hop>; its imports are hop + 1, and the loader follows hops 1 to 4
  local f="$1" hop="$2" imp real
  while IFS= read -r imp; do
    [ -n "$imp" ] || continue
    if [ "$hop" -ge 4 ]; then printf 'DEPTH\t%s\t%s\n' "$f" "$imp"; continue; fi
    real=$(ip_realpath "$imp")
    if [ ! -f "$real" ]; then printf 'UNRESOLVED\t%s\t%s\n' "$f" "$imp"; continue; fi
    case "$real" in "$base"/*) ;; *) printf 'EXTERNAL\t%s\t%s\n' "$f" "$real"; continue ;; esac
    e_walk "$real" $((hop + 1))
  done < <(_ip_imports_of "$f")
}
for a in <every AGENTS.md>; do e_walk "$(ip_realpath "$a")" 0; done
```

`EXTERNAL` is a reachable target outside the start directory, which loads only where external
imports were already approved. `UNRESOLVED` is a target that is not a file. `DEPTH` is an import
past the fourth hop, which the loader drops, so the chain is not what it reads. Each fails E.

## What D asks the operator

Ask each, and record the answer beside the condition:

1. **Does any user, machine or organization set Project instructions to `claude-md` or
   `managed-only`?** The memory page says to keep the `@AGENTS.md` import "when you've set
   **Project instructions** to `claude-md`"; under `managed-only` no `AGENTS.md` loads at all.
2. **Does anyone run a session the memory page lists as unable to read `AGENTS.md`?** In these
   three, "Claude reads `CLAUDE.md` files only, and **Project instructions** doesn't appear in the
   `/config` settings panel":
   - a Claude Code version before v2.1.277;
   - the built-in `agents-md` plugin disabled in `/plugin`;
   - in some cases, the first session after upgrading from v2.1.276 or earlier.
3. **Does anyone run a CLI before v2.1.281 on Amazon Bedrock, Google Vertex AI, Microsoft
   Foundry, an LLM gateway, or with telemetry disabled?** The memory page names Bedrock and
   telemetry-disabled sessions; the 2.1.281 changelog entry names the full list as the sessions
   that release extended support to.
4. **Does anyone add this repository with `--add-dir` while
   `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` is set?** There "Their `AGENTS.md` doesn't
   load".
5. **Does anyone reach this repository through the Agent SDK, a cloud or web session, or
   `claude-code-action`?** The memory page does not say whether those surfaces read `AGENTS.md`
   directly. The CI canary in `sources.md` covers one `claude-code-action` pin and CLI, not every
   one, so the operator confirms each surface in use or the shim stays.
6. **Is there any other way instructions reach Claude for this repository, or anything else that
   consumes `InstructionsLoaded`, beyond what conditions A to F and questions 1 to 5 cover?** This
   question catches every case not listed here, so a gap found later keeps the shim without a
   change to this file. "Don't know" fails D.

## Nested `AGENTS.md`, per mode

What the memory page states, and the verdict that follows:

- `claude-md-or-agents-md`: a subdirectory's `AGENTS.md` loads "when Claude opens a file there
  with the Read tool and that subdirectory has none of the three `CLAUDE.md` files of its own".
  Nested shims leave with the root only when condition A holds for every such subdirectory;
  a subdirectory with its own `.claude/CLAUDE.md` or `CLAUDE.local.md` keeps its shim, and since
  `remove-shims` takes root and nested together, the repository keeps all of them.
- `claude-md-and-agents-md`: "each directory's `CLAUDE.md` files first and its `AGENTS.md` after
  them"; the page does not say when a subdirectory's file loads. A repository with nested
  `AGENTS.md` keeps every shim under this mode.
- `claude-md`: no `AGENTS.md` loads. Keep every shim.
- `managed-only`: every `AGENTS.md` is left out; a subdirectory's `CLAUDE.md` still loads on Read,
  and the page does not say whether its import expands. Keep every shim.
