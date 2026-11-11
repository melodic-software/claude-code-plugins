# visualization

A Claude Code plugin for on-demand visualization. `visualize` has one job: at any point
in a conversation, decide **what** is most worth showing visually and **how** to
show it, then render it. It is a form-and-medium router, not a craft teacher.
`lib/mermaid-gate.mjs` parses the mermaid it emits; other plugins' mermaid-emitting skills run their own copy.

| Skill | What it does |
|---|---|
| `/visualization:visualize` | Infer the target from the conversation, pick a form (mermaid diagram, table, chart, ASCII/Unicode, code-shape sketch, or a rich page) and a medium (terminal, local HTML file, or published Artifact), and render it, asking only on genuine ambiguity |
| `/visualization:present` | Write a markdown outline as the record, then fill a deck made from the account's claude.ai Slides Artifact type. `lib/publish-gate.mjs` keeps a private repository's or credential-shaped content local, and the outline is the fallback when the account has no Slides type |

## What it decides

Two decisions, then the output:

- **Form**, matched to the *shape* of the content:

  | Content shape | Form |
  |---|---|
  | Flow, hierarchy, sequence, state, or relationships | A mermaid diagram |
  | Attribute comparison | A markdown table |
  | Quantities | A chart |
  | A small structural sketch | ASCII or Unicode |
  | Logic, a call path, a component or file tree, types, or a delta over code | A code-shape sketch (pseudocode, call tree, component tree, shallow file tree, types and signatures, diff), a fenced text form that stays in the terminal by default |
  | A composite or interactive view, or an infographic | A rich rendered page |
  | A slide deck | A hand-off to `/visualization:present` |
  | A visual layout the user would rather tweak by hand | A rich rendered page, with `/design` (the bundled `design` skill's hand-editable canvas, which the person runs) offered alongside it |

- **Medium**. One of three ascending tiers, **inline terminal → local HTML file →
  published Artifact**, chosen by the form's weight, a configurable preference, and
  which surfaces are actually available.

The full grounded catalog lives in the skill's
[`context/decision-matrix.md`](skills/visualize/context/decision-matrix.md).
It covers every mermaid family, the zero-dependency chart paths, and the
rendering-surface facts.

## Router, not craft

This skill decides the form and medium; it does **not** own the craft of a good
chart or the fundamentals of a good page. When a chart is the right form and a
chart-craft/dataviz capability is installed, it routes the craft there; when a rich
page is the right medium, the page's contract and design are owned by the Artifact
tool's own contract and an artifact-design capability. Each is invoked through its
capability when present and degrades to a documented fallback when absent. This
skill never restates their guidance.

It is also **not** a comprehension aid: restating dense text in plainer words is a
different concern. This skill is form-driven (render content as a visual), not
comprehension-driven.

```shell
/visualization:visualize                          # infer the target, auto-decide form and medium
/visualization:visualize this as a sequence       # honor a named form
/visualization:visualize file                     # render richer forms as a local HTML file, never published
/visualization:visualize artifact                 # prefer a published Artifact when that surface is available
```

## Surfaces and availability

A published Artifact is heavily gated (plan, sign-in, provider, version, and
context constraints); when it is unavailable the skill writes a self-contained
local HTML file instead, and if no page surface is available it degrades visibly to
the terminal. A ` ```mermaid ` fence in the terminal is shown as source, not a
rendered diagram. These facts and their sources are documented in the catalog.

## Configuration

- **`medium`** (`userConfig`, string, default `auto`). Preferred delivery medium:
  `auto` (defer to the `rendered-views` cascade, then decide by content and
  available surfaces), `terminal` (always inline), `file` (rich forms as a local
  HTML file, never published off the machine), or `artifact` (prefer a published
  Artifact when available, else a local file, else terminal). `hosted` is accepted
  so one personal `rendered-views` value can serve every lane, and is treated as
  `artifact` here: only `/review:explain-change` sends pages to a page host. A
  `/config` picker offers these five values.
- **`thin_context_prompt`** (`userConfig`, string, default `auto`). What the skill
  does when code is pasted with little conversational context and no form named:
  `auto` (ask one ranked question only when two or more code-shape forms fit about
  equally; render when one form dominates), `always` (offer the ranked menu on any
  bare code paste), or `never` (render the recommended form without asking). A
  `/config` picker offers these three values.
- **`hosted_canvas`** (`userConfig`, string, default `allow`; also the `hosted_canvas` key of a
  repository's `docs/conventions/visualization.yaml` and of the gitignored personal override
  `docs/conventions/visualization.local.yaml`). Whether diagram content may go to a canvas server
  reached over the network: `allow` or `deny`. `deny` from any layer wins.
- **`diagram_target`** (`userConfig`, string, default `auto`; also the `diagram_target` key of a
  repository's `docs/conventions/visualization.yaml` and of the gitignored personal override
  `docs/conventions/visualization.local.yaml`). Where a diagram is drawn: `auto` (pick by where the session runs),
  `terminal`, `local-page`, `excalidraw` or `tldraw`. A later layer wins: the personal override,
  then the team file, then `userConfig`.

Configure with `/plugin configure visualization@<marketplace>`, or headless with
`claude plugin install visualization@<marketplace> -s <scope> --config
medium=<value>`. Against an already-installed plugin that prints `already
installed` and still writes the value. Never uninstall to reconfigure: that drops
the whole stored `pluginConfigs` entry and resets every option to its manifest
default. The verified-version record lives in the
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md). No persistent state; no external prerequisites; no network calls of
its own.

### Option details

**`medium`.** `terminal` degrades richer forms to their best terminal approximation; `file` writes
a self-contained local HTML file; `artifact` applies when that surface is available; `hosted`
behaves as `artifact`. An unrecognized value is reported and treated as `auto`.

**`thin_context_prompt`.** `auto` renders without asking when one form dominates. A value outside
the three the picker offers is reported and treated as `auto`.

**`hosted_canvas`.** A canvas server is an MCP server whose tools draw diagrams in an interactive
view. The skill uses one only on a surface that renders it, never in the Claude Code terminal, and
never for a diagram that will be committed, which stays Mermaid, and only where the resolved
`medium` would deliver a page. With `deny`, or a `medium` that keeps delivery on the machine, it
uses a canvas server only when you say in the session that the server runs locally. The plugin ships no canvas server; the optional official ones (Excalidraw, tldraw) install
at user level from their repositories, listed in the visualize skill's catalog.

`hosted_canvas` only steers `/visualization:visualize`; other skills and tools can still call the
server. To block a canvas server for every tool, add a Claude Code permission deny rule on its
tools, such as `mcp__tldraw__*`, using the server's configured name (a server a plugin provides
takes the `mcp__plugin_<plugin>_<server>__*` form). The
[MCP rule form](https://code.claude.com/docs/en/permissions#mcp) matches every tool of that
server, and a tool denied at any settings level cannot be allowed at another
([Settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence)).

**`diagram_target`.** Applies only when the form is a diagram. An explicit medium argument still
wins, and so does a person's own resolved `medium` setting; the skill names that override in one
line. `terminal` draws an inline Mermaid or ASCII fence, `local-page` a local HTML file, and
`excalidraw` or `tldraw` that canvas server, under the `hosted_canvas` rules above. A diagram that
will be committed stays Mermaid source whatever the target. When the chosen target is unavailable
(no such server connected, a surface that does not render it, or `hosted_canvas` forbids it), the
skill uses `auto` and says so in one line. Unlike `hosted_canvas`, the team file is read from the
working tree only: the key is a preference, not a floor. An unrecognized value is reported and
that layer is dropped.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `medium` | string | `"auto"` | Preferred delivery medium. auto (default) defers to the shared medium resolver, then decides by content and available surfaces; terminal always renders inline; file renders richer forms as a local HTML file, never published; artifact or hosted prefers a published Artifact, else a file. |
| `thin_context_prompt` | string | `"auto"` | What the skill does when code is pasted with little context and no form named. auto (default) asks one ranked question only when two or more code-shape forms fit about equally; always offers the ranked menu on any bare code paste; never renders the recommended form without asking. |
| `hosted_canvas` | string | `"allow"` | Whether diagram content may go to a canvas server reached over the network (a remote MCP server). allow (default) permits it where the surface renders a canvas; deny keeps diagrams local or on a local server. deny from any layer wins. |
| `diagram_target` | string | `"auto"` | Where a diagram is drawn. auto (default) picks by surface; terminal draws an inline Mermaid or ASCII fence; local-page writes a local HTML file; excalidraw or tldraw draws on that connected canvas server. A target that is unavailable, or that hosted_canvas forbids, falls back to auto. |

### How to set these

Set the options above for `visualization@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install visualization@melodic-software
```

## Possible future change

- **Third-party visualization server.** No credible egress-free, self-hostable
  visualization server exists to depend on today. Re-evaluate if one lands with a
  maintained security posture (a self-hosted AntV deployment is the current
  candidate). Until then the skill relies only on native rendering surfaces and
  the presence-gated craft capabilities.
