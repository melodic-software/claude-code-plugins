# Mockup setup: the skills a run loads

The brief decides which sibling skills you take into the run. Load them **now**, before writing
variant code: they are what makes each variant look designed instead of assembled, and
retrofitting craft after the switcher is built means editing every variant. You want the user to
reject a direction because it doesn't work, not because it doesn't look good.

| When the brief involves | Load |
| --- | --- |
| Text as the design: headlines, editorial, docs, data tables, a type scale | `/user-interface:design`, `typography` |
| Palette, accent, contrast | `/user-interface:design`, `color` |
| Theme, dark mode, a theme switch | `/user-interface:design`, `theming` |
| Cards, modals, dropdowns, elevation, borders, glass, anything that stacks | `/user-interface:design`, `shape-and-depth` |
| Icons, icon buttons | `/user-interface:design`, `icons` |
| Motion: entrances, exits, gestures, drag, press and hover feedback | `/user-interface:write-animation` (the `motion` concern routes there) |
| Inputs, buttons, validation, signup, checkout, settings | `/user-interface:design`, `forms` |
| Loading, empty, error and disabled states | `/user-interface:design`, `states` |
| Content that loads in late: images, web fonts, async data, anything that can shift | `/user-interface:design`, `layout-stability` |
| Touch targets, small screens, mobile gestures | `/user-interface:design`, `touch` |
| Keyboard and focus order, screen-reader labels, reduced motion | `/user-interface:design`, `accessibility` |
| A hero, pricing table, landing page, blog, or changelog | `/user-interface:design`, `marketing-pages` |
| Long lists, heavy media, anything that could feel slow | `/user-interface:design`, `web-performance` |
| A variant that declares its own visual direction (no app look to keep) | `/user-interface:design`, `generic-defaults` |
| The API of the component being promoted (the record step only) | `/user-interface:design`, `component-api` |

**Every run, no exceptions:** `/user-interface:design` with `web-layout` before building
(hierarchy, spacing, restraint: it owns the calls that decide whether any of this reads as
designed), then `/user-interface:audit` over the variant code before the user ever sees the switcher.

Invoke each skill via the Skill tool, naming the concern id from the table; if one isn't installed,
say so and proceed rather than inventing its rules. A concern id `/user-interface:design` does not
list yet (its `reference/concerns.json`) still runs: the design skill applies its generic design
pass, its interface type file and principles, for that concern. The loadout applies to *every* variant equally:
the quiet variant gets the same type craft as the loud one, or the comparison is rigged.

What a loaded skill returns is guidance this skill applies; it changes no host rule. On the HTML
mockup this skill still writes the CSS itself, and an existing app's own look still wins over any
default a loaded skill suggests.

**Completion criterion:** you can name each loaded skill and the dimension it owns in this run, and
no variant was written from memory of a rule you could have looked up.
