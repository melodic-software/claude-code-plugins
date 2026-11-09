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

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install user-interface@melodic-software
```

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
| `css.concentric_radius.max_gap_px` | `24` | px: the widest gap at which a nested radius is still derived from its parent's |
| `css.border_px.hairline`, `.standard`, `.strong` | `0.5`, `1`, `2` | px: a high-density hairline, a standard border, an emphasis line |
| `css.edge_fade.length` | `2rem` | a CSS length: the fade band on an overflowing scroller |
| `css.edge_fade.stops_percent` | `10`, `90` | two percents: where that fade is full, start then end |
| `css.focus_ring.offset_px` | `2` | px between an element and its focus ring |
| `css.focus_ring.width` | `max(2px, 0.08em)` | a CSS length: the focus ring's width |
| `css.image_outline.opacity` | `0.1` | 0 to 1: the outline around an image |
| `animation.easing.out`, `.in`, `.in_out`, `.drawer`, `.spring_stand_in`; `animation.easing_library.out.*`, `.in_out.*` | four cubic Bezier control points each, in `defaults.yaml` | a list of four numbers |
| `animation.duration_ms.press`, `.hover`, `.small`, `.medium`, `.large`, `.page` | `160`, `150`, `200`, `250`, `300`, `400` | milliseconds: the value a recipe writes for the role, and the longest the role allows |
| `animation.duration_ms.exit_factor` | `0.8` | the longest an exit runs, as a fraction of its entrance |
| `animation.delay_ms.group_warm`, `.tooltip`, `.indicator` | `300`, `200`, `150` | milliseconds: a group staying warm after it closes, and the wait before a first tooltip or a loading indicator shows |
| `animation.scale.press`, `.press_min`, `.enter`, `.enter_small`, `.swap_start` | `0.97`, `0.95`, `0.95`, `0.97`, `0.3` | 0 to 1: a pressed element, the lower limit `/user-interface:audit` reports a press scale below, an entering surface, a small entering element, an icon swapping in |
| `animation.scale.hover_max` | `1.02` | at least 1: the largest scale a hovered element takes |
| `animation.stagger_ms.interval`, `.max_total`, `.section`, `.word` | `40`, `400`, `100`, `80` | milliseconds between items, for the group, between a section's large pieces, and between a headline's words |
| `animation.travel_px.small`, `.medium`, `.large` | `4`, `8`, `16` | px a surface travels: a nudge, a short rise or exit, an arrival from its edge |
| `animation.blur_max_px` | `20` | px, the largest blur an animated element takes |
| `animation.blur_px.soften` | `2` | px, a small blur that softens a transition |
| `animation.spring.bounce.default`, `.playful_max` | `0`, `0.3` | 0 to 1: default motion, and the most a playful interaction takes |
| `animation.spring.duration_s.default`, `.small` | `0.5`, `0.35` | seconds: the default spring, and a small element's |
| `animation.spring.response_s` | `0.3`, `0.4` | two numbers in seconds, low then high, for stacks that take damping and response |
| `animation.gesture.velocity_threshold` | `0.11` | px/ms for a small element's swipe to dismiss |
| `animation.gesture.distance_threshold` | `0.4` | Fraction of its own travel, 0 to 1, past which a dragged element dismisses on release |
| `animation.gesture.deceleration_rate`, `.rubberband_constant`, `.slop_px` | `0.998`, `0.55`, `10` | momentum projection after a flick, resistance past an edge, and px of travel before a drag commits |
| `animation.inspect_playback_rate` | `0.1` | 0 to 1: the slowed playback for checking motion by eye |
| `animation.skip_frequency` | `100` | uses per day above which an action takes no animation |
| `animation.cleanup_order` | `removal`, `review`, `performance` | a list of `removal`, `review`, `opportunities`, `performance`: the passes `/user-interface:audit cleanup` runs, in order |
| `color.border.dark_solid_l`, `.light_alpha` | `0.285`, `0.08` | 0 to 1: a solid border's OKLCH lightness in a dark theme, a translucent border's alpha in a light one |
| `color.dark_mode.brand_desaturation_percent` | `20`, `30` | two percents, low then high: how far a brand color is pulled back for a dark theme |
| `color.hover_mix_percent` | `15` | percent of black mixed into a base color for its hover shade |
| `color.illustration_max_colors` | `3` | the most colors an illustration uses |
| `color.overlay_alpha` | `0.2` | 0 to 1: a translucent fill on a small control |
| `color.ramp.chroma_percent` | `30`, `85` | two percents of the sRGB chroma ceiling: at the ramp's ends, at its peak |
| `color.ramp.endpoints_l` | `0.97`, `0.22` | two OKLCH lightnesses: the lightest step, the darkest step |
| `color.ramp.hue_spread_max_deg` | `10` | degrees: the largest hue spread across a ramp |
| `color.subtle_mix_percent` | `12` | percent of a base color in a subtle tint |
| `color.triage.light_surface_min_l` | `0.6` | OKLCH lightness above which a surface reads as light |
| `color.triage.near_black_l` | `0.25`, `0.75`, `0.3` | three lightnesses: a near-black surface's highest, the lowest for text on it, the bottom of the mid-tone band |
| `color.triage.near_white_l` | `0.85`, `0.45` | two lightnesses: a near-white surface's lowest, the highest for text on it |
| `components.primitives_default` | `base-ui` | `base-ui`, `radix`, `react-aria`: the primitives library a React project with none installed builds on |
| `icon.filled_below_px` | `12` | px under which an outline icon swaps to filled |
| `icon.label_gap_px` | `6`, `8` | two numbers in px, low then high: the gap between an icon and its label |
| `icon.label_gap_em` | `0.5` | em: the gap between an icon and its label when it scales with the text |
| `icon.size_em` | `1` | em: an icon sized by the text beside it |
| `icon.size_px` | `12`, `16`, `20`, `24`, `48` | five sizes in px an icon is drawn at, smallest first |
| `layout.breakout_width`, `.content_width`, `.grid_track_min_width` | `80rem`, `1200px`, `16rem` | CSS lengths: the content grid's wide track, the content cap, an intrinsic grid's smallest track |
| `layout.media_aspect_ratio`, `.media_small`, `.panel_max_height` | `16 / 9`, `3.5rem`, `80dvh` | CSS values: an image box's ratio, a small media box, a scrolling panel's height limit |
| `layout.sidebar_width` | `20rem`, `50%` | two CSS values: a sidebar's ideal width, and the container share at which it stacks |
| `layout.simple_page_columns`, `.terminal_min_columns`, `.z_index_stray_above` | `8`, `80`, `100` | a simple page's column count, the narrowest terminal in columns, the z-index above which a stray value is a finding |
| `performance.image_max_kb`, `.search_debounce_ms`, `.virtualize_min_items` | `300`, `300`, `50` | the photo weight an audit flags, a search request's debounce, the list length past which a list is virtualized |
| `radius.s`, `.l` | `4px`, `1.25rem` | CSS lengths: small and large corner radii |
| `spacing.xs`, `.s`, `.m`, `.l` | `0.5rem`, `1rem`, `1.5rem`, `2rem` | CSS lengths: the spacing steps |
| `spacing.control_padding` | `0.75rem`, `1.25rem` | two CSS lengths: a control's block and inline padding |
| `spacing.flow` | `1lh`, `2em`, `0.5em` | three CSS lengths: between paragraphs, before a heading, after a heading |
| `spacing.optical_icon_px` | `2` | px: a small optical correction beside an icon |
| `spacing.section` | `clamp(3rem, 1rem + 6vw, 8rem)`, `6rem` | two CSS lengths: a page section's fluid vertical padding, and its fallback |
| `states.copy_confirm_ms`, `.wait_indicator_ms` | `1500`, `400` | milliseconds: a copy confirmation's stay, and the wait past which an indicator must show |
| `states.toast_reading_wpm` | `200`, `250` | two reading speeds in words per minute, low then high, a toast's duration is computed from |
| `typography.long_form_body_px` | `18` | px, at least `16`: long-form reading text, written in `rem` |
| `typography.fluid_body.min_rem`, `.preferred_rem`, `.preferred_vw`, `.max_rem` | `1`, `0.75`, `1`, `1.75` | a fluid body size's clamp parts; `min_rem` at least `1` |
| `typography.fluid_scale.narrow_rem`, `.wide_rem`, `.size_narrow_rem`, `.size_wide_rem`, `.ratio_narrow`, `.ratio_wide`, `.space_m_factor`, `.space_l_factor` | `20`, `77.5`, `1.125`, `1.25`, `1.2`, `1.25`, `1.5`, `2` | a fluid type and space scale's inputs; `size_narrow_rem` at least `1` |
| `typography.fluid_max_ratio` | `2.5` | the most a fluid font size's maximum may be as a multiple of its minimum |
| `typography.line_height.body` | `1.5`, `1.6` | two numbers, low then high: reading text's leading |
| `typography.line_height.display` | `1.1` | display text and headings' leading |
| `typography.measure_ch` | `65` | ch: the reading column's width |
| `typography.small_text_px.caption`, `.control`, `.min` | `13`, `14`, `12` | px: captions, controls, the lowest size without a stated reason |
| `touch.both_axes_activation` | `tap-to-activate` | `tap-to-activate`, `always-active`: whether a touch element that needs both axes waits for a tap before it takes gestures |
| `touch.check_width_px`, `.fixed_width_hunt_px` | `375`, `340` | px: the narrow width a page is checked at, and the width above which a fixed width is a finding |
| `touch.target_desktop_px` | `40` | px, at least `24`: the hit area on a fine-pointer desktop |
| `routing` | none | route rows, `disable` and `deny`, team layer only |

The `css` keys are read by `/user-interface:write-css`; its
[`configuration.md`](skills/write-css/reference/configuration.md) says what each one changes. The
`animation` keys are taste defaults that apply only where the project has no motion tokens of its
own; `/user-interface:write-animation` reads them all, and write-css reads the curves and durations.
`animation.cleanup_order` is the exception: it sets the pass order of the motion lane's `cleanup`
sub-mode in `/user-interface:audit`, and no other skill reads it.
The `typography` key is read through the `typography` concern by `/user-interface:design` and
`/user-interface:audit`, and applies only where the project has no type tokens for long-form text;
the config check refuses a value under the `16px` body floor.
The `touch` key is read through the `touch` concern by `/user-interface:design` and
`/user-interface:audit`, and by `/user-interface:write-css`'s
`gesture-surface-that-claims-only-its-axis` recipe; it applies only where the project has no
pattern of its own for these elements.
The `spacing` key is read by `/user-interface:write-css` and applies only where the project has no
spacing tokens for controls. How a skill writes any key's value is in
[`reference/values.md`](reference/values.md).
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

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `account_tools_enabled` | boolean | `true` | Route to tools that need an account, login or API key (Claude Design, Figma, axe) when installed and reachable; false uses only account-free tools. Paid tools only when nothing free fits. Only Claude Design (interactive sessions) and Figma are tested; the rest stay deferred. |
| `css_browser_target` | string | *(none)* | Browserslist query for the browsers CSS must support when the project has no browserslist config, such as "baseline widely available". Empty uses the plugin default. A team or personal convention file overrides it. |
| `css_important` | string | `"avoid"` | When !important is acceptable: avoid (default), utilities-only, or allow. A team or personal convention file overrides it. |
| `css_layer` | string | *(none)* | The cascade layer new CSS goes in. Empty follows the project's own layer order. A team or personal convention file overrides it. |
| `css_token_fallback` | string | `"ask"` | When no design token matches a value: ask (default), propose-token, or literal. A team or personal convention file overrides it. |

### How to set these

Set the options above for `user-interface@<marketplace>`, replacing `<marketplace>` with the
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

As of 2026-11-04. Recheck trigger: one of these sections moves, or a Claude Code
release note changes how plugin options are set or stored.

<!-- END GENERATED: plugin options -->
