# event-storming

A Claude Code plugin for **EventStorming**, Alberto Brandolini's workshop format for collaborative
domain discovery. It helps you explore a business domain, discover bounded contexts, and bridge the
resulting model to DDD tactical design.

It ships **two skills**, split by whether you want to *read* facilitation guidance or *run* an
agentic workshop:

| Skill | Invoke | Does |
|---|---|---|
| `methodology` | `/event-storming:methodology [--big-picture\|--process\|--design-level\|--patterns\|--glossary\|--notation\|--remote]` | Facilitation knowledge and reference across the three formats: notation, building blocks, patterns/anti-patterns, remote adaptations. No args runs an interactive discovery flow. |
| `simulation` | `/event-storming:simulation [--simulate\|--process-model\|--design-level\|--evaluate\|--retrospective\|--induction\|--value\|--crc\|--ux\|--discover-bcs] [domain\|board] [--backend markdown\|miro]` | An agentic, multi-persona EventStorming workshop on a board, plus per-run scoring and bounded-context discovery. Boards are markdown files in your repository by default, or live Miro boards when you choose Miro (see Boards). |

## When to use which

- **methodology** is pure reference. You are facilitating or learning EventStorming yourself and
  want the format guidance, notation, and patterns at hand. It needs no external tools.
- **simulation** *runs* the workshop for you: it spins up 4 to 7 siloed personas, plays every Big
  Picture phase in order, discovers bounded contexts, and lets you drill into Process Modeling and
  Design-Level per context. By default each board is a markdown file in your repository; with
  Miro chosen it is a live Miro board instead.

Each skill auto-invokes on its own trigger phrases, or you can call it directly.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install event-storming@melodic-software
```

## Requirements

- **methodology.** None beyond Claude Code.
- **simulation.** Node.js for the markdown board writer. Two optional surfaces, neither bundled:
  - The first-party **`miro` plugin**, for the Miro backend.
  - A **web-research surface** for domain context. The skills use the Perplexity MCP tools if
    present, otherwise Claude Code's built-in `WebSearch` / `WebFetch`; with no research surface
    at all they ask you for the domain context rather than guessing.

Shareable exports (slides/docs/PDF) hand off to the `document-skills` plugin when it is installed,
and fall back to markdown otherwise.

## Boards

The simulation skill reads and writes boards through named board operations
([`reference/board-operations.md`](reference/board-operations.md)) on one of two backends:

- **markdown** (default): one markdown file per board under the board directory, one folder per
  session (`docs/event-storming/<session>/big-picture.md` by default). The skill writes these files
  through `scripts/board-md.mjs` and never commits them; commit, share or edit them by hand as you
  like. Format: [`reference/board-backends/markdown.md`](reference/board-backends/markdown.md).
- **miro**: a live Miro board through the first-party **`miro` plugin**, a bundled local-stdio MCP
  server that you **install from an available marketplace and then enable** (select the `miro`
  plugin in `/plugin`, then enable it) with a Miro API token, entered when Claude Code asks for it.
  Setup, colors and layout: [`reference/board-backends/miro.md`](reference/board-backends/miro.md).
  Miro's official hosted server (`mcp.miro.com`) was evaluated and **rejected** as the target (no
  board-delete tool for teardown; third-party remote egress). Trust record in the marketplace
  repo's plugin-acceptance review records (the miro record in
  `docs/adr/0093-record-plugin-acceptance-security-reviews.md`; the carry verdict is
  `docs/adr/0092-carry-only-the-miro-mcp-server-in-a-plugin.md`).

A run picks its backend from, in order: a `--backend markdown|miro` argument, the board you name
(a Miro board URL is Miro, a `.md` path is markdown), your `board_backend` option, then markdown.
Enabling the `miro` plugin alone does not switch to Miro. When the chosen backend is not
available, the run stops and says so; it never switches backends on its own.

## Configuration

Your personal `board_backend` option picks the default backend (Options reference below). Board
files go to the board directory; other run state (session archives, run history, comparison
baselines) is written to the plugin's own persistent data directory (`${CLAUDE_PLUGIN_DATA}`), never
into your project tree.

A repository can commit `event-storming.yaml` in its convention home (default `docs/conventions`)
to set these keys, checked against
[`schemas/event-storming.schema.json`](schemas/event-storming.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `board_dir` | a path relative to the repository root | `docs/event-storming` | Where `/event-storming:simulation` writes markdown boards, one folder per session. Read from the working tree. An absolute path, a leading `~` or a `..` segment is invalid and the default applies. |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | Whether `/event-storming:simulation` dispatches its fresh-context rubric scorer: `light` and `off` skip it and leave every criterion `unscored`. Read from the default branch only, through `lib/read-verification.sh`; a skill entry beats the plugin value ([verification level](../../docs/contracts/verification-level/README.md)). |

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `board_backend` | string | `"markdown"` | Where the simulation skill puts its boards when a run names none. markdown (default) writes one markdown file per board in the repository's board directory; miro uses a live Miro board and needs the miro plugin enabled with a token. A --backend argument or a board link wins for one run. |

### How to set these

Set the options above for `event-storming@<marketplace>`, replacing `<marketplace>` with the
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

## License

MIT (SPDX-License-Identifier: MIT).
