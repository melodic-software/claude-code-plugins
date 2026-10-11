# Configuration

Every `css` setting resolves through the plugin's five config layers and reaches this skill as
`config.values`, with the layer behind each in `config.provenance`. The layer order, locations and
merge rules belong to the resolver and the plugin README's Configuration section; keys and allowed
values to `<plugin-root>/reference/team.schema.json`. Never name a layer path from memory.

## Settings

| Key | What it changes in this skill | Where it can be set |
|---|---|---|
| `css.browser_target` | the target when there is no `--target` and no project browserslist | every layer; userConfig `css_browser_target` |
| `css.techniques.disable` | technique slugs (as marked in the topic references) never used | files only; lists add up across layers |
| `css.rules.disable` | always-on rule ids turned off; the review script suppresses their findings | files only; lists add up across layers |
| `css.important` | when `!important` may appear: `avoid`, `utilities-only`, `allow` | every layer; userConfig `css_important` |
| `css.layer` | the layer new CSS goes in when the project has no layer system | every layer; userConfig `css_layer` |
| `css.token_fallback` | what happens when no token matches: `ask`, `propose-token`, `literal` | every layer; userConfig `css_token_fallback` |

Per run, the skill's arguments vary the rest: `--target` (browser target), `--no-lint` (whether the
bundled linter runs), `--show-suppressed` (whether config-suppressed findings are listed one by
one). `routing` belongs to `/user-interface:design`, not to this skill.

`/user-interface:setup check` shows each value and its layer; `/user-interface:setup apply` changes
one key in one layer.

## What does not vary, and why

- **The topic split of the reference files.** Techniques are filed by topic (foundations, layout,
  spacing and shape, text and media, interaction, motion, show and hide, scroll and viewport), never
  by source, so a later CSS source merges into the same files instead of adding a parallel set.
- **The review output sections and exit codes.** The three sections (`## Findings`,
  `## Suppressed`, `## Judgment`) and the script's exit code (0 clean, 1 findings, 2 usage error or
  crash) are a contract for whatever calls the script or reads the review.
- **The four-step process order.** Detect, identify and research, answer the checklist, verify the
  output: the checklist in step 3 can only be answered from what steps 1 and 2 found.
- **Project-first precedence.** The project's design system, conventions, lint config and layer
  system outrank every configured value and every default here. The skill exists to fit the
  project, so no setting can make it override the project.
