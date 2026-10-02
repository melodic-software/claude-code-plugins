# Is the shim droppable here?

`cutover-check` grades the build and the fleet. Whether this repository's users lose instructions
without the `@AGENTS.md` shim depends on the built-in `agents-md` loader and on settings no
repository can see, so removal is recommended only when **every** condition below holds.

Report each condition as held, failed or unknown, with its evidence. **Unknown is failed**: one
failed or unknown condition keeps the recommendation at "keep the shim" and names the condition.
This recommends, never removes: `remove-shims` and its `--confirm` gate stay the only path.

The quotes, dates and recheck triggers behind every condition are in [`sources.md`](sources.md),
"The built-in agents-md plugin".

## The user roots

Never read user settings or plugins at a hard-coded `~/.claude`. Resolve the two roots first, with
the expression the performance plugin's verify skill already uses:

- **Config root** `<config>`: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. User settings are
  `<config>/settings.json` and `<config>/settings.local.json`; personal-skill plugins are
  `<config>/skills/*/`.
- **Plugins root** `<plugins>`: `CLAUDE_CODE_PLUGIN_CACHE_DIR` when set, else `<config>/plugins`.

`CLAUDE_CONFIG_DIR` can come from the shell, user settings or managed settings `env`, so check all
three. A root that cannot be resolved here is unknown, and fails every condition that reads it.

## The conditions

| # | Holds when | Read it from |
|---|---|---|
| A | Nothing takes precedence over an `AGENTS.md`: no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` at or above the working directory other than the shims going, **and** no directory on the path from the repository root to a nested `AGENTS.md`, that directory included, holds a `.claude/CLAUDE.md` or a non-shim `CLAUDE.md` or `CLAUDE.local.md` | The ancestor walk below, run from each directory contributors start sessions in; the nested path walk below, over every `AGENTS.md` inside the repository, tracked or not; and the operator for the other machines, whose ancestors (a `~/work/CLAUDE.md`) and uncommitted `CLAUDE.local.md` files this machine cannot see |
| B | **Project instructions** on this machine reads `AGENTS.md` with no `CLAUDE.md`: `claude-md-or-agents-md` (the default) or `claude-md-and-agents-md` | `pluginConfigs["agents-md@builtin"].options.instructionFiles` in `<config>/settings.json`, managed settings and any `--settings` file; absent everywhere is the default. Project and local settings are ignored for it, so never read them as the answer. `claude-md` or `managed-only` fails |
| C | The loader is present and not disabled on this machine | `/harness-ops:inventory --bundled`, `builtin_plugins.cc-plugin-agents-md` (`in_loader`, `load`, `gated`, `gate_flags`), and no `enabledPlugins` entry set `false` in any scope (`<config>` user settings, managed, project, local, `--settings`) for `agents-md@builtin` or the `id` the lane prints. Inventory absent, the lane `broken`, or the entry missing is unknown. With `disableAllHooks` or `allowManagedHooksOnly` set `true` in any scope, C holds only on v2.1.287 or later, the build on which built-in mods are verified to keep running under both; an older or unknown version is unknown |
| D | Every user, machine and organization the repository serves reads `AGENTS.md` directly | Ask the operator, with the list below. Any yes, and any "don't know", fails |
| E | Nothing reachable through the `@` import graph of any `AGENTS.md`, root or nested, lies outside the working directory | The import-graph walk below, from every `AGENTS.md` and from each session start directory. Any `EXTERNAL`, `UNRESOLVED` or `DEPTH` row fails |
| F | No hook depends on `InstructionsLoaded` reporting the `AGENTS.md` load, or the operator accepts losing that | Every hook source, inside the repository and out: grep for `InstructionsLoaded` in the repository's `.claude/settings*.json`, hook scripts and CI; `<config>/settings.json` and `<config>/settings.local.json`; the managed settings file and any `managed-settings.d/` beside it; every `--settings` file contributors pass; each installed plugin's `hooks/hooks.json` and `plugin.json` `hooks` under `<plugins>`; the `hooks:` frontmatter of every skill, command and agent file in the repository, under `<config>`, under `<plugins>` and in the managed settings directory, by the frontmatter scan below; and the plugins loaded per session or outside an install: ask the operator whether contributors use `--plugin-dir`, `--plugin-url`, `CLAUDE_CODE_PLUGIN_DIRS` or `--add-dir`, and scan each directory or archive they name, plus every `<config>/skills/*/` that holds a `.claude-plugin/plugin.json`. A source that cannot be read here, and every other machine, is the operator's to answer. A hit the operator has not accepted, or a source nobody can answer for, fails |

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
shims `remove-shims` would remove fails A. The user `CLAUDE.md` is not on the list: the memory page
says "your `~/.claude/CLAUDE.md`" does not count, so a `FOUND $HOME/.claude/CLAUDE.md` row is the
one exemption, and only while `<config>` resolves to `$HOME/.claude`. With `CLAUDE_CONFIG_DIR`
pointing elsewhere, the page does not say whether that file still counts, so the row fails A. An
`UNREADABLE` row is unknown, and fails A.

## The nested path walk for condition A

A nested `AGENTS.md` is read only where no blocker sits between it and the repository root, so
check every directory on that path, not only the one holding the file. Any of the three names in
any directory on the path fails A, whatever the memory page's nested-load rule says about that
directory; the pointer is in [`sources.md`](sources.md), "Blockers between the root and a nested
`AGENTS.md`". The walk is this plugin's own `ip_entry_points_on_path` in
`<plugin-root>/scripts/lib/discover.sh`, which emits the three names in a directory and in every
directory above it up to the root; the readability check is added here because that function skips
an unreadable directory silently:

```bash
. <plugin-root>/scripts/lib/discover.sh
root=$(cd <repo> && pwd -P)
find "$root" -name AGENTS.md -not -path '*/.git/*' -print 2>/dev/null || printf 'UNREADABLE\tfind %s\n' "$root"
# then, for each nested AGENTS.md found (the root one is the ancestor walk's):
rel=<its directory, relative to $root>
d=$rel
while :; do
  { [ -r "$root/$d" ] && [ -x "$root/$d" ]; } || printf 'UNREADABLE\t%s\n' "$root/$d"
  [ "$d" = . ] && break
  d=$(dirname "$d")
done
ip_entry_points_on_path "$root" "$rel" | sed 's/^/FOUND\t/'
```

Every `FOUND` row that is not a shim `remove-shims` would remove fails A, and so does every
`UNREADABLE` row, the `find` one included: a directory `find` cannot enter may hold an `AGENTS.md`
nobody checked. Worked example: with `svc/deep/AGENTS.md` and a `svc/CLAUDE.local.md`, the walk for
`svc/deep` prints `FOUND <root>/svc/CLAUDE.local.md`. That file is no shim, so A fails and every
shim stays, the root's included.

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

## The frontmatter scan for condition F

Condition F counts every skill, command-file and subagent frontmatter that names
`InstructionsLoaded` as a hook source, whenever and wherever that component might run. Which
components can declare hooks, which events they accept, when those hooks are active and where each
component loads from are read live at the pointers in [`sources.md`](sources.md), "Frontmatter
hooks and `InstructionsLoaded`"; a pointer that comes to say something narrower does not loosen
the scan until that record changes.

Every root is resolved to its canonical directory first, and `find -L` follows symlinks inside it,
so a linked root or a linked skill is scanned at its target. A root that cannot be resolved,
including a dangling link, prints `UNREADABLE`, and so does a tree `find` cannot finish, a
symlink loop included, because `find` then exits non-zero.

```bash
fm_gone() { # true only when <path> provably does not exist: the nearest ancestor that does is searchable
  local p=$1 up
  while ! [ -e "$p" ]; do
    [ -L "$p" ] && return 1 # a dangling link is not absence
    up=$(dirname "$p")
    if [ -d "$up" ]; then [ -x "$up" ]; return; fi
    [ "$up" = "$p" ] && return 1
    p=$up
  done
  return 1
}
fm_scan() { # <root>...: frontmatter naming InstructionsLoaded, and every root not fully read.
  # A root written ?<dir> is optional: skipped when provably absent, UNREADABLE when it cannot be
  # stat'd. Any other root is expected, and UNREADABLE whenever it cannot be read.
  local a d r f
  for a; do
    d=${a#\?}
    if ! [ -e "$d" ]; then
      [ "$a" != "$d" ] && fm_gone "$d" && continue
      printf 'UNREADABLE\t%s\n' "$d"
      continue
    fi
    r=$(cd -P -- "$d" 2>/dev/null && pwd -P) || { printf 'UNREADABLE\t%s\n' "$d"; continue; }
    find -L "$r" -type f \( -path '*/skills/*/SKILL.md' -o -path '*/commands/*.md' \
      -o -path '*/agents/*.md' \) -not -path '*/.git/*' -print 2>/dev/null ||
      printf 'UNREADABLE\t%s\n' "$d"
  done | while IFS= read -r f; do
    case $f in UNREADABLE*) printf '%s\n' "$f"; continue ;; esac
    [ -r "$f" ] || { printf 'UNREADABLE\t%s\n' "$f"; continue; }
    awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
      /^---[[:space:]]*$/ { exit }
      /InstructionsLoaded/ { print "HIT\t" FILENAME; exit }' "$f"
  done
}
fm_scan <repo> '?<config>/skills' '?<config>/commands' '?<config>/agents' '?<plugins>' \
  '?<managed-settings-dir>/.claude/skills' <each --add-dir directory> \
  <each --plugin-dir and CLAUDE_CODE_PLUGIN_DIRS entry>
```

Scanning the whole repository covers the root `.claude/` and every nested `.claude/skills/` and
`.claude/agents/`. The repository and every root the operator names are expected; the user,
plugin and managed locations may not exist on a given machine, so they are optional, but one
behind a directory that cannot be searched still prints `UNREADABLE`. Ask the operator which
directories contributors add with `--add-dir`, `/add-dir` or the Agent SDK's equivalent. Each one
named is an expected root and is scanned whole, a superset of whatever configuration the
`--add-dir` pointer in `sources.md` says it loads; any plugins it enables are already under
`<plugins>`.

A `HIT` the operator has not accepted fails F. An `UNREADABLE` row, a root that cannot be
resolved, an `--add-dir` set the operator cannot name, or a source that is not on disk here
(skills synced from a claude.ai account, subagents passed as `--agents` JSON or deployed through
managed settings, a `--plugin-url` archive, and every other machine) is unknown until the
operator answers for it, and fails F.

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

   Also ask whether anyone runs a CLI before v2.1.287 with `disableAllHooks` or
   `allowManagedHooksOnly` set: an earlier revision of the page listed both here, and no release
   note dates their removal.
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
6. **Does anyone set `CLAUDE_CONFIG_DIR` or `CLAUDE_CODE_PLUGIN_CACHE_DIR`, and to what?** Each
   moves the user settings, user `CLAUDE.md` or plugins this rule reads, so conditions A, B, C and
   F hold for that contributor only when their roots are named and read. "Don't know" fails D.
7. **Is there any other way instructions reach Claude for this repository, or anything else that
   consumes `InstructionsLoaded`, beyond what conditions A to F and questions 1 to 6 cover?** This
   question catches every case not listed here, so a gap found later keeps the shim without a
   change to this file. "Don't know" fails D.

## Nested `AGENTS.md`, per mode

What the memory page states, and the verdict that follows:

- `claude-md-or-agents-md`: a subdirectory's `AGENTS.md` loads "when Claude opens a file there
  with the Read tool and that subdirectory has none of the three `CLAUDE.md` files of its own".
  Nested shims leave with the root only when condition A holds for every such subdirectory and
  every directory between it and the root; a blocker anywhere on that path keeps its shim, and since
  `remove-shims` takes root and nested together, the repository keeps all of them.
- `claude-md-and-agents-md`: "each directory's `CLAUDE.md` files first and its `AGENTS.md` after
  them"; the page does not say when a subdirectory's file loads. A repository with nested
  `AGENTS.md` keeps every shim under this mode.
- `claude-md`: no `AGENTS.md` loads. Keep every shim.
- `managed-only`: every `AGENTS.md` is left out; a subdirectory's `CLAUDE.md` still loads on Read,
  and the page does not say whether its import expands. Keep every shim.
