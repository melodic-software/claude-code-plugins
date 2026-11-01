# user-interface

Front door for interface design. An agent building anything a person or agent interacts with (CLI
output, a TUI, a prompt theme, a Claude Code mod, web or app UI) gets guidance that keeps the
project's existing look, reuses the design tools already installed, and fills only the gaps.

| Skill | What it does |
|---|---|
| `/user-interface:design` | Detect the project's design system and the installed design tools, route each concern to the best present source, and supply the plugin's own guidance where nothing covers it; its "Order of work" says which skill or concern to run next for a screen, from deciding a direction to the check before launch |
| `/user-interface:write-css` | Write or review CSS in any stack: discover the project's tokens, browser targets, lint rules and conventions first, fill only the gaps with modern techniques, and name each default used; review mode lints and reports without editing |
| `/user-interface:write-animation` | Decide whether an element should animate at all, then write one interface animation in the project's stack from its motion tokens and the stack's current docs, with reduced motion included; CSS goes through write-css |
| `/user-interface:audit` | Review interface code read-only, one concern lane at a time: the diff (default), the whole tree, or every lane before a launch; the motion lane also finds where animation would help or must not go, and why one drops frames; each finding with severity and evidence, and `--fix` one at a time after a yes |
| `/user-interface:glossary` | Name the design or front-end term for an effect, detail or behavior someone describes, tell near-synonyms apart, and ask for a reference image when no term fits |
| `/user-interface:setup` | Show each setting's value and the layer it came from, or change one key in one layer (user-invoked) |

## How it routes

For each concern the order is:

1. The project's own design system, conventions and MCP servers.
2. This repository's enabled plugins.
3. Official publishers.
4. Community tools, with adoption breaking ties.
5. This plugin's own guidance.

The routes live in [`reference/routing.json`](reference/routing.json), validated by
[`reference/routing.schema.json`](reference/routing.schema.json).
[`scripts/detect.mjs`](scripts/detect.mjs) reports what the project and machine have, and which
installed routes are reachable.

The interface concerns live in
[`reference/concerns.json`](reference/concerns.json), validated by
[`reference/concerns.schema.json`](reference/concerns.schema.json) and
[`scripts/lib/concerns-validate.mjs`](scripts/lib/concerns-validate.mjs). Each row names the
reference files (spokes) `/user-interface:design` loads for that concern and that
`/user-interface:audit` judges against as one lane.

## Working one screen

Run one or two skills or concerns at a time and look at the screen between runs: decide, build on
the foundation and one material concern, refine, then review, and sweep the whole app before a
launch. The order, the overlaps that get confused and the complaint-to-skill table are in
`/user-interface:design`, section "Order of work".

## Guidance

- [`reference/principles.md`](reference/principles.md): the working order, the usability heuristics,
  and the accessibility floor every medium keeps.
- [`reference/types/`](reference/types/): one file per interface type. The skill reads the file
  that matches, so a new type is a new file.
  - [`terminal.md`](reference/types/terminal.md): CLI output, TUIs, prompt themes, PowerShell,
    banners; `NO_COLOR`, non-TTY output and plain-text fallbacks.
  - [`mods.md`](reference/types/mods.md): Claude Code mod displays, building on terminal.md.
  - [`web.md`](reference/types/web.md) and [`app.md`](reference/types/app.md): project-first rules
    and pointers to platform guidelines.

## Configuration

Settings resolve through five layers. A later layer wins per key:

| Order | Layer | Where | Committed |
|---|---|---|---|
| 1 | plugin defaults | [`reference/defaults.yaml`](reference/defaults.yaml) | shipped |
| 2 | userConfig | the `css_*` options below, scalars only | no |
| 3 | user-global | `~/docs/conventions/user-interface.{yaml,md}` | no |
| 4 | team | `<home>/user-interface.{yaml,md}`, where `<home>` is the repository's convention home (default `docs/conventions`) | yes |
| 5 | personal | `<home>/user-interface.local.{yaml,md}` | no, gitignored |

YAML files hold settings and Markdown files hold prose; prose from layers 3 to 5 is read in that
order. Keys and allowed values are in [`reference/team.schema.json`](reference/team.schema.json):

| Key | Default | Values |
|---|---|---|
| `css.browser_target` | `baseline widely available` | a browserslist query |
| `css.techniques.disable` | `[]` | technique names to skip |
| `css.rules.disable` | `[]` | `hover`, `logical`, `outline`, `ease-in`, `color`, `transition-all`, `motion`, `duration` |
| `css.important` | `avoid` | `avoid`, `utilities-only`, `allow` |
| `css.layer` | `null` (the project's own layer order) | a cascade layer name |
| `css.token_fallback` | `ask` | `ask`, `propose-token`, `literal` |
| `animation.easing.out`, `.in`, `.in_out`, `.drawer`; `animation.easing_library.out.*`, `.in_out.*` | four cubic Bezier control points each, in `defaults.yaml` | a list of four numbers |
| `animation.duration_ms.press`, `.small`, `.medium`, `.large`, `.page` | `160`, `200`, `250`, `300`, `400` | milliseconds |
| `animation.duration_ms.exit_factor` | `0.8` | the longest an exit runs, as a fraction of its entrance |
| `animation.stagger_ms.interval`, `.max_total` | `40`, `400` | milliseconds between items, and for the group |
| `animation.blur_max_px` | `20` | px, a heuristic ceiling for an animated blur |
| `animation.gesture.velocity_threshold` | `0.11` | px/ms for a small element's swipe to dismiss |
| `components.primitives_default` | `base-ui` | `base-ui`, `radix`, `react-aria`: the primitives library a React project with none installed builds on |
| `routing` | none | route rows, `disable` and `deny`, team layer only |

The `css` keys are read by `/user-interface:write-css`; its
[`configuration.md`](skills/write-css/reference/configuration.md) says what each one changes. The
`animation` keys are taste defaults that apply only where the project has no motion tokens of its
own; `/user-interface:write-animation` reads them all, and write-css reads the curves and durations.
`routing` is validated and shown by `/user-interface:setup check`, and `/user-interface:design`
routes from the bundled rows with it applied: a row with a bundled concern and id overrides that
row key by key, a new row adds a route, and `disable` and `deny` skip routes (a `deny` skip names
the team file). A team file that cannot be read leaves the bundled routes, with a disclosure.

**Provenance.** `scripts/detect.mjs --config` prints every resolved value with the layer that
supplied it, and `/user-interface:setup check` shows them as a table. A `css_*` option counts only once you store a
value for it: the `default` in `plugin.json` is not delivered to skills, so an option you never set
reads from a lower layer (probe record:
[`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md),
Test D).

**Changing a value.** `/user-interface:setup apply <key>=<value>` writes the team file;
`--user` writes the user-global file and `--local` the personal file, adding `<home>/*.local.*` to
`.gitignore`. Set a `css_*` option through `/config` or the routes under Options below.

**What does not vary, and why:**

- The layer order and file locations: every skill reads settings through one resolver, so no skill
  names a path. [ADR 0061](../../docs/adr/0061-adopt-a-five-layer-plugin-config-cascade-read-through-one-shared-resolver.md)
  records the decision, and [ADR 0075](../../docs/adr/0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
  supersedes its layers and paths.
- A design system the project already has outranks every configured value: the plugin's job is to
  keep the project's look.
- `routing` is accepted only in the team file: a personal layer must not change which tool a whole
  team's agents use without review.
- `*.disable` lists add up across layers: a personal file cannot quietly re-enable what the team
  turned off.
- Block-style YAML only: the bundled parser rejects flow mappings (`{`), so a file using them is
  reported invalid.

`/user-interface:write-css` also holds these fixed, as its
[`configuration.md`](skills/write-css/reference/configuration.md) records:

- The topic split of its reference files: techniques are filed by topic, never by source, so a
  later CSS source merges into the same files.
- The review output sections (`## Findings`, `## Suppressed`, `## Judgment`) and the review
  script's exit code (0 clean, 1 findings, 2 usage error or crash): callers rely on them.
- The four-step process order (detect, identify and research the stack, answer the stack
  checklist, verify the compiled output): the checklist needs what the first two steps found.
- Project-first precedence: the project's design system, conventions, lint config and layer
  system outrank every configured value and every default.

## Options

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `account_tools_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_ACCOUNT_TOOLS_ENABLED` | Route to tools that need an account, login or API key (Claude Design, Figma, axe) when installed and reachable; false uses only account-free tools. Paid tools only when nothing free fits. Only Claude Design (interactive sessions) is tested; the rest stay deferred. |
| `css_browser_target` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CSS_BROWSER_TARGET` | Browserslist query for the browsers CSS must support when the project has no browserslist config, such as "baseline widely available". Empty uses the plugin default. A team or personal convention file overrides it. |
| `css_important` | string | `"avoid"` | `CLAUDE_PLUGIN_OPTION_CSS_IMPORTANT` | When !important is acceptable: avoid (default), utilities-only, or allow. A team or personal convention file overrides it. |
| `css_layer` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CSS_LAYER` | The cascade layer new CSS goes in. Empty follows the project's own layer order. A team or personal convention file overrides it. |
| `css_token_fallback` | string | `"ask"` | `CLAUDE_PLUGIN_OPTION_CSS_TOKEN_FALLBACK` | When no design token matches a value: ask (default), propose-token, or literal. A team or personal convention file overrides it. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure user-interface@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure user-interface@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"account_tools_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install user-interface@<marketplace> -s <scope> --config account_tools_enabled=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "user-interface@<marketplace>": {
         "options": {
           "account_tools_enabled": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
