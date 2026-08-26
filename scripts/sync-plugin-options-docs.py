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
            typ = f"{typ}<br>*{', '.join(bounds)}*"
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
            desc = (
                "**Sensitive** — stored in the OS keychain or protected credentials file. "
                + desc
            )
        lines.append(f"| `{key}` | {typ} | {default} | `{env_var(key)}` | {desc} |")

    # The 2.1.240 reconfiguration observation covers a NON-SENSITIVE option only. Emitting it
    # for a plugin whose every option is `sensitive` would prescribe an unverified credential
    # rotation — and contradict that plugin's own hand-written rotation section, which routes
    # to `/plugin configure` precisely because it masks input. So `first` is drawn from the
    # non-sensitive options when there are any, and the claim is withheld when there are none.
    non_sensitive = [k for k, s in options.items() if not s.get("sensitive")]
    sensitive = [k for k, s in options.items() if s.get("sensitive")]
    first = non_sensitive[0] if non_sensitive else next(iter(options))

    if non_sensitive:
        reconfigure = [
            "   The same command reconfigures a plugin that is **already installed**: it prints",
            "   `already installed` and still writes the value — verified on Claude Code 2.1.240,",
            "   for a non-sensitive option at `user` scope, by writing a non-default value to an",
            "   installed plugin and restoring it. The short-circuit message is about the install,",
            "   not the config write. That has not been verified for a `sensitive` option or for",
            "   `project`/`local` scope. Do **not** `claude plugin uninstall` to",
            "   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,",
            "   resetting every option in the table above to its default. `-s` defaults to `user`,",
            "   so pass the scope `claude plugin list` reports for this plugin.",
            "",
            "   The value is stored immediately; the session you are in does not change. Hooks are",
            "   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh",
            "   Claude Code session before expecting new behavior — a check run in the old session",
            "   still reports the old value, and that is not a failed write.",
        ]
        if sensitive:
            reconfigure += [
                "",
                "   That observation does **not** extend to this plugin's `sensitive` option(s)"
                f" ({', '.join(f'`{k}`' for k in sensitive)}).",
                "   Rotate those through route 1 instead: `/plugin configure` masks input, where a",
                "   secret passed on the command line lands in shell history and the process table.",
            ]
    else:
        # Sensitive-only plugin: `--config` still seeds a value, but nothing here may present a
        # post-install `--config` as a verified rotation path for a credential.
        reconfigure = [
            "   Route 1 is the rotation path for this plugin, not this one. Every option here is",
            "   `sensitive`, and `/plugin configure` masks input — a secret passed on the command",
            "   line lands in shell history and the process table. Whether `--config` writes a",
            "   `sensitive` value on an already-installed plugin has not been verified (the",
            "   Claude Code 2.1.240 observation behind that claim covered a non-sensitive option at",
            "   `user` scope), so do not rely on this command to rotate a credential. Do **not**",
            "   `claude plugin uninstall` to reconfigure either: uninstalling drops this",
            "   plugin's whole stored `pluginConfigs` entry, resetting every option in the table",
            "   above to its default.",
        ]

    lines += [
        "",
        "### How to set these",
        "",
        "Three supported routes, in the order most people want them:",
        "",
        "1. **Interactively** — Claude Code prompts for declared options when you enable the",
        f"   plugin. To change them later: `/plugin configure {plugin}@{marketplace}`.",
        "2. **Headless** — repeat `--config` for each option. Replace",
        f"   `{marketplace}` with the marketplace you installed this plugin from:",
        "",
        "   ```shell",
        f"   claude plugin install {plugin}@{marketplace} -s <scope> --config {first}=<value>",
        "   ```",
        "",
        *reconfigure,
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
        # Anchors re-verified 2026-08-22. Two of the four previously pointed at bare
        # backward-compatibility `<span id=…>` stubs on the settings page: `#plugin-settings`
        # and `#configuration-scopes` both still exist as ids, so lychee's fragment check
        # passed them, but a reader following either landed on blank space — the content had
        # moved to the headings below. A link CI accepts is not the same as a link that works.
        "- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export",
        "- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry",
        "- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`",
        "- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence",
        "- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`",
        "",
        END,
    ]
    return "\n".join(lines)


def split_block(readme: str) -> tuple[str, str] | None:
    """Text before and after the generated block, or None when there is none."""
    if BEGIN not in readme or END not in readme:
        return None
    return readme[: readme.index(BEGIN)], readme[readme.index(END) + len(END) :]


def splice(readme: str, block: str) -> str:
    halves = split_block(readme)
    if halves is not None:
        head, tail = halves
        return head + block + tail
    # First insertion: before the License heading when there is one, else at the end.
    marker = "\n## License"
    if marker in readme:
        i = readme.index(marker)
        return readme[:i] + "\n" + block + "\n" + readme[i:]
    return readme.rstrip("\n") + "\n\n" + block + "\n"


def strip_stale_block(readme: pathlib.Path, check: bool) -> str | None:
    """Drop the generated block from a plugin that declares no options any more.

    Returns "stale" when --check found a block to remove, "wrote" when one was
    removed, and None when there was nothing to remove -- no README, or a README
    that never carried a block.
    """
    if not readme.exists():
        return None
    halves = split_block(readme.read_text(encoding="utf-8"))
    if halves is None:
        return None
    head, tail = halves
    stripped = (head.rstrip("\n") + "\n" + tail.lstrip("\n")).rstrip("\n") + "\n"
    if check:
        return "stale"
    readme.write_text(stripped, encoding="utf-8", newline="\n")
    print(f"  removed stale block: plugins/{readme.parent.name}/README.md (0 options)")
    return "wrote"


def main() -> int:
    check = "--check" in sys.argv
    stale, wrote, skipped = [], 0, 0
    for d in sorted(PLUGINS.iterdir()):
        manifest = d / ".claude-plugin" / "plugin.json"
        readme = d / "README.md"
        if not manifest.exists():
            continue
        try:
            options = (
                json.loads(manifest.read_text(encoding="utf-8")).get("userConfig") or {}
            )
        except json.JSONDecodeError as exc:
            print(f"  MANIFEST UNPARSABLE: {d.name}: {exc}", file=sys.stderr)
            return 2
        if not options:
            # A plugin that removed its LAST option must lose its generated block too.
            # Skipping here left a stale block documenting options that no longer exist,
            # and --check never read the README on this branch, so the gate reported it
            # as up to date -- the one path where the gate silently fails at its own job.
            removal = strip_stale_block(readme, check)
            if removal is None:
                skipped += 1
            elif removal == "stale":
                stale.append(d.name)
            else:
                wrote += 1
            continue
        if not readme.exists():
            print(
                f"  MISSING README: {d.name} declares {len(options)} option(s)",
                file=sys.stderr,
            )
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
            print(
                f"\nSTALE options docs in {len(stale)} plugin(s): {', '.join(stale)}",
                file=sys.stderr,
            )
            print("Run: python scripts/sync-plugin-options-docs.py", file=sys.stderr)
            return 1
        print("plugin options docs: up to date")
        return 0
    print(f"\nsynced {wrote} README(s); {skipped} plugin(s) declare no options")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
