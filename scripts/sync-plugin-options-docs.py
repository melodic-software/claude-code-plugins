#!/usr/bin/env python3
"""Generate the options reference block in each plugin README from its manifest.

    scripts/sync-plugin-options-docs.py           rewrite every plugin README
    scripts/sync-plugin-options-docs.py --check   fail if any README is stale

SINGLE SOURCE OF TRUTH: `plugins/<name>/.claude-plugin/plugin.json` -> `userConfig`.
The block between the markers below is GENERATED. Never hand-edit it: add or change
the option in the manifest and re-run this script. CI runs `--check` and rejects drift,
the same contract `scripts/sync-shared-copies.sh` uses for the shared hook library.

Why a generated block rather than prose alone: a hand-written Configuration section
carries nuance a generator cannot (see plugins/actionlint/README.md, which explains the
stdin timeout's slicing behavior). That prose is preserved untouched. What it cannot
guarantee is COMPLETENESS and FRESHNESS -- an option added to the manifest six months
from now is silently undocumented. The generated block guarantees both; the prose keeps
the nuance. They sit next to each other in the plugin's own folder so they change together.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys

BEGIN = "<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->"
# The marker this one replaced. `split_block` accepts either, so a README still carrying the old
# text is rewritten in place rather than growing a second block: `splice` only finds the region to
# replace when it can match the marker already in the file. Drop this once no README carries it.
LEGACY_BEGIN = "<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->"
END = "<!-- END GENERATED: plugin options -->"

# CHECK_DATA_ROOT: the tree to check, when it is not the one holding this script
# (the pre-push hook runs a merge-base copy against the branch).
REPO = pathlib.Path(
    os.environ.get("CHECK_DATA_ROOT")
    or pathlib.Path(__file__).resolve().parent.parent
)
PLUGINS = REPO / "plugins"

# A placeholder, deliberately, not this repository's marketplace name. Plugin-facing docs are
# marketplace-agnostic: a plugin can be installed from a fork, a mirror, or a private catalog
# under a different name, and `plugins/github/github.test.sh` enforces that its docs never
# hardcode one. The reader substitutes whatever they installed from.
MARKETPLACE = "<marketplace>"


def env_var(key: str) -> str:
    """Claude Code exports each declared option as CLAUDE_PLUGIN_OPTION_<KEY>, uppercased."""
    return f"CLAUDE_PLUGIN_OPTION_{key.upper()}"


CONVENTION_PATH = "docs/contracts/plugin-reconfiguration/README.md"
CONVENTION_URL = (
    "https://github.com/melodic-software/claude-code-plugins/blob/main/"
    + CONVENTION_PATH
)


def convention_cite(plugin: str) -> str:
    """Where the verified-version record lives, as inline markdown.

    Installed plugins cannot read this tree, so most generated READMEs cite the
    published URL. Two plugins forbid the publisher org name in shipped
    markdown (github's agnosticism sweep; autonomy's binding-seam contract), so
    those cite the in-repo path instead.
    """
    if plugin in {"github", "autonomy"}:
        return f"this marketplace's plugin-reconfiguration convention (`{CONVENTION_PATH}`)"
    return f"the [plugin-reconfiguration convention]({CONVENTION_URL})"


UNINSTALL_DOCS = (
    "https://code.claude.com/docs/en/plugins/cli-reference"
    "#what-an-uninstall-deletes-and-keeps"
)
CONFIGURE_DOCS = "https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure"


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
        # constraint keys bound it. Rendering only `type` would make a repeated option
        # indistinguishable from a scalar one.
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
                "**Sensitive**: stored in the OS keychain or protected credentials file. "
                + desc
            )
        lines.append(f"| `{key}` | {typ} | {default} | `{env_var(key)}` | {desc} |")

    # Pointer-only: this block states no Claude Code CLI or settings behavior as
    # fact. Each upstream specific is a link to the docs section that owns it, and
    # what this repository measured (what a rerun prints and writes, which scope it
    # lands at, why the old session keeps the old value) lives only in the
    # plugin-reconfiguration convention, which carries the dated record. Do not
    # restate either here: a copy in every README is drift waiting to happen.
    # The `install --config` rerun record covers a NON-SENSITIVE option only, so
    # the fallback is drawn from the non-sensitive options and withheld when there
    # are none. `first` (the example key) prefers a non-sensitive option too.
    cite = convention_cite(plugin)
    non_sensitive = [k for k, s in options.items() if not s.get("sensitive")]
    sensitive = [k for k, s in options.items() if s.get("sensitive")]
    first = non_sensitive[0] if non_sensitive else next(iter(options))

    if non_sensitive:
        fallback = [
            "   The fallback the convention names, for a Claude Code release without",
            "   `plugin configure`, reruns the install with the new value, passing the scope",
            "   `claude plugin list` reports for this plugin:",
            "",
            "   ```shell",
            f"   claude plugin install {plugin}@{marketplace} -s <scope> --config {first}=<value>",
            "   ```",
        ]
    else:
        fallback = [
            "   Every option here is `sensitive`, so the convention's `install --config` fallback",
            "   does not apply: it puts the value on the command line, and its record covers no",
            "   sensitive value.",
        ]
    if sensitive and non_sensitive:
        fallback += [
            "",
            "   Never pass this plugin's `sensitive` option(s)"
            f" ({', '.join(f'`{k}`' for k in sensitive)}) through that fallback: it puts",
            "   a secret on the command line, and its record covers no sensitive value.",
        ]
    if sensitive:
        fallback += [
            "",
            "   For a `sensitive` option, route 1 stays the recommended route. What",
            "   `plugin configure` does with a sensitive value, and on which hosts that was",
            f"   measured, is recorded in {cite}.",
        ]

    lines += [
        "",
        "### How to set these",
        "",
        "Three supported routes:",
        "",
        "1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):",
        f"   `/plugin configure {plugin}@{marketplace}`.",
        f"2. **Headless.** Save the values with [`claude plugin configure`]({CONFIGURE_DOCS}),",
        "   run from the project the plugin is installed in. Replace",
        f"   `{marketplace}` with the marketplace you installed this plugin from:",
        "",
        "   ```shell",
        f"   claude plugin configure {plugin}@{marketplace} --values-stdin < values.json",
        "   ```",
        "",
        "   `values.json` holds a JSON object of strings, booleans included:",
        "",
        "   ```json",
        f'   {{"{first}": "<value>"}}',
        "   ```",
        "",
        f"   This is the preferred headless route in {cite}, which records its",
        "   limits: the Claude Code version it needs, which install it finds, how it rejects a bad",
        "   value, and why a session started before the change keeps the old value until a fresh",
        "   session starts. Do **not** `claude plugin uninstall` to reconfigure: see",
        f"   [What an uninstall deletes and keeps]({UNINSTALL_DOCS}).",
        "",
        *fallback,
        "",
        "3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**",
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
        "   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)",
        "   entry names the settings scopes Claude Code reads this key from.",
        "",
        "Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one",
        "of the routes above.",
        "",
        "### Upstream documentation",
        "",
        # The settings page keeps bare backward-compatibility `<span id=…>` stubs
        # (`#plugin-settings`, `#configuration-scopes`): lychee's fragment check passes a
        # link to a stub id, but a reader following it lands on blank space, so these
        # anchors must target the live headings. A link CI accepts is not the same as a
        # link that works.
        "- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export",
        f"- [Plugin configure]({CONFIGURE_DOCS}): the `--values-stdin` flag's reference entry",
        "- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry",
        "- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`",
        "- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence",
        "- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`",
        "",
        END,
    ]
    return "\n".join(lines)


def split_block(readme: str) -> tuple[str, str] | None:
    """Text before and after the generated block, or None when there is none."""
    if END not in readme:
        return None
    begin = BEGIN if BEGIN in readme else LEGACY_BEGIN
    if begin not in readme:
        return None
    return readme[: readme.index(begin)], readme[readme.index(END) + len(END) :]


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
            # Skipping here would leave a stale block documenting options that no longer
            # exist, and --check would never read the README on this branch, so the gate
            # would report it as up to date -- the one path where the gate silently
            # fails at its own job.
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
