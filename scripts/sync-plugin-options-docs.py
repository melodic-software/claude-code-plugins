#!/usr/bin/env python3
"""Generate the options reference block in each plugin README from its manifest.

    scripts/sync-plugin-options-docs.py           rewrite every plugin README
    scripts/sync-plugin-options-docs.py --check   fail if any README is stale

SINGLE SOURCE OF TRUTH: `plugins/<name>/.claude-plugin/plugin.json` -> `userConfig`.
The block between the markers below is GENERATED. Never hand-edit it: add or change
the option in the manifest and re-run this script. CI runs `--check` and rejects drift,
the same contract `scripts/sync-hook-utils.sh` uses for the shared hook library.

Why a generated block rather than prose alone: a hand-written Configuration section
carries nuance a generator cannot (see plugins/actionlint/README.md, which explains the
stdin timeout's slicing behavior). That prose is preserved untouched. What it cannot
guarantee is COMPLETENESS and FRESHNESS -- an option added to the manifest six months
from now is silently undocumented. The generated block guarantees both; the prose keeps
the nuance. They sit next to each other in the plugin's own folder so they change together.
"""

from __future__ import annotations

import json
import pathlib
import sys

BEGIN = "<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->"
END = "<!-- END GENERATED: plugin options -->"

REPO = pathlib.Path(__file__).resolve().parent.parent
PLUGINS = REPO / "plugins"

# A placeholder, deliberately, not this repository's marketplace name. Plugin-facing docs are
# marketplace-agnostic: a plugin can be installed from a fork, a mirror, or a private catalog
# under a different name, and `plugins/github/github.test.sh` enforces that its docs never
# hardcode one. The reader substitutes whatever they installed from.
MARKETPLACE = "<marketplace>"


def env_var(key: str) -> str:
    """Claude Code exports each declared option as CLAUDE_PLUGIN_OPTION_<KEY>, uppercased."""
    return f"CLAUDE_PLUGIN_OPTION_{key.upper()}"


def render(plugin: str, marketplace: str, options: dict) -> str:
    lines = [
        BEGIN,
        "",
        "### Options reference",
        "",
        "Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code",
        "will prompt for when the plugin is enabled, with the environment variable each hook",
        "reads it from.",
        "",
        "| Option | Type | Default | Environment variable | Description |",
        "| --- | --- | --- | --- | --- |",
    ]
    for key, spec in options.items():
        typ = spec.get("type", "string")
        # `multiple: true` means the option takes an array of that type, and the
        # constraint keys bound it. Rendering only `type` made a repeated option
        # indistinguishable from a scalar one -- source-control declares 10 such options
        # whose hand-written prose already says "string (multiple)", so the generated
        # table contradicted the prose beside it.
        if spec.get("multiple"):
            typ = f"{typ} (multiple)"
        bounds = [f"{k} {spec[k]}" for k in ("min", "max") if k in spec]
        if spec.get("required"):
            bounds.insert(0, "required")
        if bounds:
            typ = f"{typ}<br>*{', '.join(str(b) for b in bounds)}*"
        default = spec.get("default", "")
        # MD049: this repo's markdownlint requires asterisk emphasis, not underscore.
        default = "*(none)*" if default == "" else f"`{json.dumps(default)}`"
        desc = " ".join(str(spec.get("description", spec.get("title", ""))).split())
        # A description is arbitrary prose from the manifest and lands inside a table
        # cell. Escape the characters that would otherwise be read as markdown: a pipe
        # ends the cell, and a bracketed run such as `[a-z0-9-]` in a regex reads as an
        # undefined reference link (MD052).
        desc = desc.replace("|", "\\|").replace("[", "\\[").replace("]", "\\]")
        if spec.get("sensitive"):
            desc = "**Sensitive** — stored in the OS keychain or protected credentials file. " + desc
        lines.append(f"| `{key}` | {typ} | {default} | `{env_var(key)}` | {desc} |")

    first = next(iter(options))
    lines += [
        "",
        "### How to set these",
        "",
        "Three supported routes, in the order most people want them:",
        "",
        "1. **Interactively** — Claude Code prompts for declared options when you enable the",
        f"   plugin. To change them later: `/plugin configure {plugin}@{marketplace}`.",
        f"2. **Headless, at install time** — repeat `--config` for each option. Replace",
        f"   `{marketplace}` with the marketplace you installed this plugin from:",
        "",
        "   ```shell",
        f"   claude plugin install {plugin}@{marketplace} --config {first}=<value>",
        "   ```",
        "",
        "3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**",
        "   settings (`~/.claude/settings.json`):",
        "",
        "   ```json",
        "   {",
        '     "pluginConfigs": {',
        f'       "{plugin}@{marketplace}": {{',
        '         "options": {',
        f'           "{first}": <value>',
        "         }",
        "       }",
        "     }",
        "   }",
        "   ```",
        "",
        "   Plugin option values are read from **user**, `--settings`, and managed settings",
        "   only — **not** from a project's `.claude/settings.json`. To vary behavior per",
        "   repository, enable or disable the plugin in that project's `enabledPlugins`",
        "   instead of setting an option there.",
        "",
        "Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code",
        "hands a configured value to a hook process; the value comes from the routes above.",
        "",
        "### Upstream documentation",
        "",
        "- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export",
        "- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`",
        "- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence",
        "- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`",
        "",
        END,
    ]
    return "\n".join(lines)


def splice(readme: str, block: str) -> str:
    if BEGIN in readme and END in readme:
        head = readme[: readme.index(BEGIN)]
        tail = readme[readme.index(END) + len(END) :]
        return head + block + tail
    # First insertion: before the License heading when there is one, else at the end.
    marker = "\n## License"
    if marker in readme:
        i = readme.index(marker)
        return readme[:i] + "\n" + block + "\n" + readme[i:]
    return readme.rstrip("\n") + "\n\n" + block + "\n"


def main() -> int:
    check = "--check" in sys.argv
    stale, wrote, skipped = [], 0, 0
    for d in sorted(PLUGINS.iterdir()):
        manifest = d / ".claude-plugin" / "plugin.json"
        readme = d / "README.md"
        if not manifest.exists():
            continue
        try:
            options = json.loads(manifest.read_text(encoding="utf-8")).get("userConfig") or {}
        except json.JSONDecodeError as exc:
            print(f"  MANIFEST UNPARSABLE: {d.name}: {exc}", file=sys.stderr)
            return 2
        if not options:
            # A plugin that removed its LAST option must lose its generated block too.
            # Skipping here left a stale block documenting options that no longer exist,
            # and --check never read the README on this branch, so the gate reported it
            # as up to date -- the one path where the gate silently fails at its own job.
            if readme.exists():
                current = readme.read_text(encoding="utf-8")
                if BEGIN in current and END in current:
                    head = current[: current.index(BEGIN)]
                    tail = current[current.index(END) + len(END) :]
                    stripped = (head.rstrip("\n") + "\n" + tail.lstrip("\n")).rstrip("\n") + "\n"
                    if check:
                        stale.append(d.name)
                    else:
                        readme.write_text(stripped, encoding="utf-8", newline="\n")
                        wrote += 1
                        print(f"  removed stale block: plugins/{d.name}/README.md (0 options)")
                    continue
            skipped += 1
            continue
        if not readme.exists():
            print(f"  MISSING README: {d.name} declares {len(options)} option(s)", file=sys.stderr)
            stale.append(d.name)
            continue
        current = readme.read_text(encoding="utf-8")
        updated = splice(current, render(d.name, MARKETPLACE, options))
        if updated != current:
            if check:
                stale.append(d.name)
            else:
                readme.write_text(updated, encoding="utf-8", newline="\n")
                wrote += 1
                print(f"  synced: plugins/{d.name}/README.md ({len(options)} options)")

    if check:
        if stale:
            print(f"\nSTALE options docs in {len(stale)} plugin(s): {', '.join(stale)}", file=sys.stderr)
            print("Run: python scripts/sync-plugin-options-docs.py", file=sys.stderr)
            return 1
        print("plugin options docs: up to date")
        return 0
    print(f"\nsynced {wrote} README(s); {skipped} plugin(s) declare no options")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
