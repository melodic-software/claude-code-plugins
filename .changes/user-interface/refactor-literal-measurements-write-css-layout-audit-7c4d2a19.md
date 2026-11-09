---
bump: minor
---

### Added

- Config key `icon.label_gap_em` (default 0.5): the gap between an icon and its label when it scales with the text. The icon-beside-text recipes write it.

### Changed

- `/user-interface:write-css` layout, spacing, scroll, text and media recipes write each configurable value as a `{{key}}` placeholder (spacing steps, content and breakout widths, grid track, sidebar, panel height, edge fade, scrollbar, flow, section padding, color mixes, fluid type and scale inputs, media box, border width, icon size), so a team key or project token sets it. Three recipes now follow their key's default: the content width is `layout.content_width` (was `64rem`), the prose flow base is `spacing.flow` (was `1em`), and the code-block scrollbar width is `spacing.xs`.
- The fluid type rules name `typography.fluid_max_ratio` as the limit on a font size's maximum, and the key refuses a value above 2.5, the WCAG 1.4.4 ceiling.
- The content grid's breakout width is never less than the content plus two gutters, so its tracks no longer collapse when the content and breakout widths are in different units.
- `/user-interface:audit` launch scope holds each product-UI motion role to its own duration ceiling, and names `animation.skip_frequency` and `states.wait_indicator_ms` in place of their numbers.
