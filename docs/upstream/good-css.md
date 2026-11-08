# Upstream source: vojtaholik/good-css (write-css)

Single source of truth for everything in this marketplace derived from
[vojtaholik/good-css](https://github.com/vojtaholik/good-css), MIT, a curated list of modern CSS
techniques for agents. The `user-interface` plugin's `/user-interface:write-css` skill absorbed its
techniques and vendors its CSS linter. Provenance lives here and in the plugin CHANGELOG, never
in skill files, where it is agent-facing noise.

**Last audited upstream state:** `vojtaholik/good-css@92d436ba1937d1b1407c47e35abb3e199eaace2e` (committed 2026-10-10, the latest commit to `PRACTICES.md`; no tags or releases).

Files read, each linked at the pin:

| Upstream path | Ours |
|---|---|
| [`PRACTICES.md`](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/PRACTICES.md) | Absorbed: restructured into the eight topic files under [`skills/write-css/reference/`](../../plugins/user-interface/skills/write-css/reference/) |
| [`scripts/check-css.mjs`](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/scripts/check-css.mjs) | Vendored unmodified: [`skills/write-css/vendor/check-css.mjs`](../../plugins/user-interface/skills/write-css/vendor/check-css.mjs) |
| [`LICENSE`](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/LICENSE) | Vendored unmodified: [`skills/write-css/vendor/LICENSE`](../../plugins/user-interface/skills/write-css/vendor/LICENSE) |

`motion.md`, `show-and-hide.md`, `scroll-and-viewport.md` and `interaction.md` also carry recipes
from another source (`reduced-motion-swap`, `hover-that-keeps-its-hit-area`,
`popover-that-scales-from-its-trigger`, `popover-inside-a-modal`,
`full-height-that-browser-chrome-cannot-cover`, `gesture-surface-that-claims-only-its-axis`,
`nothing-wider-than-the-viewport`, `scrollbars-styled-only-inside-small-scrollers`,
`menu-items-that-fade-at-the-container-edge`, `card-with-a-distinct-link`); their provenance is
`docs/upstream/aiforui-course.md`, not this record.

- **Pointer**: when re-auditing the techniques, fetch the compare view of upstream against the pin
  live (<https://github.com/vojtaholik/good-css/compare/92d436ba1937d1b1407c47e35abb3e199eaace2e...main>)
  and read [`PRACTICES.md` at the pin](https://github.com/vojtaholik/good-css/blob/92d436ba1937d1b1407c47e35abb3e199eaace2e/PRACTICES.md)
  beside it.
- **As of**: the 40-hex pin above stands in for the as-of date: the commit fixes exactly what was
  read, and this page's git history records when.
- **Recheck trigger**: a change, between the pinned commit and upstream HEAD, to a path a row we
  took or rejected something from links, a unit removed or added under the scope: re-audit the
  affected rows. `scripts/check-upstream-drift.sh` detects these, and the monthly drift issue for
  this upstream lists them
  ([upstream-drift convention, "Pinned git upstreams"](../contracts/upstream-drift/README.md#pinned-git-upstreams)).
  A Baseline status change for a technique the skill uses also obliges a re-audit of its row.
- **Re-pin procedure**: re-auditing the affected rows moves the pin and records the outcome per row,
  as [When a trigger fires](../contracts/upstream-drift/README.md#when-a-trigger-fires) requires:
  move the pin on the marker line and in every upstream link, `## Map` included, and run
  `scripts/check-upstream-drift.sh --links` on this page. A changed `check-css.mjs` or `LICENSE`
  also means re-vendoring the copy. The weekly
  `plugins/user-interface/scripts/check-good-css-drift.sh` and its test pin the upstream blob SHAs
  too; update them in the same change.

The 2026-10-18 re-audit moved the pin from `b645ab15b9fc` (`PRACTICES.md` blob `7d746e65`)
to <!-- spellchecker:off -->`92d436ba1937`<!-- spellchecker:on --> (blob `b8a6cb6e`). The only change was to technique 7, `content-grid-with-breakouts`:
upstream now makes the grid the outer layout on every page, including pages where nothing breaks out
past the content column, and adds a rule that the grid takes the place of any centered `max-width`
wrapper. The
reference `layout.md` carries both; no credit changed.

## Map

Units we took nothing from; each counts only if removed upstream.

- [`skills/good-css`](https://github.com/vojtaholik/good-css/tree/92d436ba1937d1b1407c47e35abb3e199eaace2e/skills/good-css):
  its `SKILL.md` and generated `references/` were read for structure; the skill does not ship, wrap
  or depend on them.

## Drift check

[`plugins/user-interface/scripts/check-good-css-drift.sh`](../../plugins/user-interface/scripts/check-good-css-drift.sh)
`--check` reads the current blob SHA of each of the three files on upstream `main`, compares it with
the blob SHA the script pins for that file at the pin above, and checks that both vendored copies
still hash to theirs. Exit 0 means no drift, 1 drift (it names each changed file and prints the
compare URL), and 2 unverifiable (network, auth or rate limit). The pinned SHAs live in one array at
the top of the script. The
`user-interface:write-css` row of
[`.github/workflows/maintenance-check-upstream-drift.yml`](../../.github/workflows/maintenance-check-upstream-drift.yml)
runs it weekly under the exit-code contract every row shares. Its exit-code contract is
tested by `plugins/user-interface/tests/check-good-css-drift.test.sh`.

## Adaptation posture

Absorbed, not depended on. The techniques were restructured by topic so later CSS sources merge into
the same files, and each carries its upstream slug, a one-line rationale and a Baseline status
pointer in place of the upstream support lines' browser versions. Upstream's always-on "In all CSS"
rules became the skill's provisional always-on rules, kept in the body only where evals show a
gain. Upstream's "Left out on purpose" section became the skill's Gotchas. Everything the skill
does around the techniques (project-first precedence, stack discovery, configuration, review mode)
is ours; upstream has no configuration surface.

### Not carried

- **"Next"**: the entries upstream holds back for browser support (scroll-driven reveal,
  customizable `<select>`, a layered box shadow). Re-evaluate when upstream moves one into a
  category.
- **"References"** and the per-entry `Borrowed from:`, `Background:`, `Docs:` and `Source:` credit
  lines: credits are recorded in the table below, never in skill files.
- **The is-agentic check**: no check, record or dependency for is-agentic.com.
- **`whole-card-clickable-from-one-link`** (technique 28): replaced by the course rule in [`aiforui-course.md`](aiforui-course.md). A card takes a distinct link; a stretched link survives only as a labeled carve-out for tiles no one selects text in, without the `:has()` ring or the z-index lift.
- The site, specimen harness, `scripts/build-skill.js` and the plugin manifest: presentation and
  packaging only.

### What the linter wrapper adds

`check-css.mjs` ships byte-identical to the pin. The skill calls it only through
[`skills/write-css/scripts/review.mjs`](../../plugins/user-interface/skills/write-css/scripts/review.mjs),
which adds:

- path and glob expansion over CSS and HTML files, with a case-insensitive `.css` suffix test;
- `--config`, taking the resolved `user-interface` settings, so a rule in `css.rules.disable` moves
  to a `## Suppressed` section with its reason instead of being dropped;
- one output shape, `## Findings`, `## Suppressed` and `## Judgment`, each finding as
  `path:line [rule-id] message`, with the rules no linter checks and any file it could not read
  listed under Judgment;
- an exit-code contract: 0 no findings, 1 findings, 2 usage error or crash.

## Credits per technique

Slug and section are upstream's (`##` category, `###` entry in `PRACTICES.md`); the reference file
is ours, under `plugins/user-interface/skills/write-css/reference/`. Credits name the people and
works that upstream's `Borrowed from:` lines credit at the pin, without their links. Names and
titles keep upstream's spelling, so the spell check is off for the table. What each credit supplied,
and any note on how upstream's version differs, is in our words, never a copy of the credit line.

<!-- spellchecker:off -->

| # | Upstream slug | Upstream section | Our reference file | Credits |
|---|---|---|---|---|
| 1 | `the-reset` | Foundations | `foundations.md` | Travis Arnold (@souporserious on X), 2025 CSS Reset, 2025-04-02: the base reset · Ayomidé Daniel (@aydahnizzy on X), 2025-10-10: font declarations · Kevin Powell, 3 modern CSS properties to add to your reset, 2026-04-02: `svh` units and scrollbar gutter · Emil Kowalski, mobile-native skill: touch declarations · Chris Coyier, The Downsides of scrollbar-gutter: stable, 2025-12-03 · Ahmad Shadeed, Defensive CSS: `overflow-wrap` and `flex: none` · upstream's own addition: `text-wrap: pretty` applied to every element. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 2 | `logical-properties` | Foundations | `foundations.md` | Ahmad Shadeed, Digging Into CSS Logical Properties, 2021-03-10 |
| 3 | `oklch-color` | Foundations | `foundations.md` | Andrey Sitnik and Travis Turner (Evil Martians), OKLCH in CSS: why we moved from RGB and HSL · Björn Ottosson, A perceptual color space for image processing |
| 4 | `one-set-of-color-tokens-for-light-and-dark` | Foundations | `foundations.md` | IP, @ipwanciu on X, 2025-10-30. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 5 | `fluid-sizes-with-clamp` | Foundations | `foundations.md` | Kyrylo Silin, @kyrylo on X, 2026-05-10 · James Gilyead and Trys Mudford, Utopia · Adrian Roselli, Responsive Type and Zoom · Maxwell Barvian, Addressing Accessibility Concerns With Using Fluid Type, 2023-11-07, for the 2.5 limit |
| 6 | `one-fluid-scale-for-type-and-space` | Foundations | `foundations.md` | James Gilyead, Designing with fluid type scales, 2020-02-01: the two type scales · Trys Mudford, CSS-only fluid modular type scales, 2020-02-02, and Fluid custom properties, 2020-02-03 · James Gilyead, Designing with a fluid space palette, 2021-03-16: paired space steps. Upstream's difference: Utopia's calculator emits a precomputed `clamp()` for each step, since 2020-era CSS lacked exponent functions; upstream's version has `pow()` compute the steps in the browser. |
| 7 | `content-grid-with-breakouts` | Layout | `layout.md` | Kevin Powell, A new approach to container and wrapper classes, 2023-11-09 · Ryan Mulligan, Layout Breakouts with CSS Grid · Stephanie Eckles, SmolCSS breakout grid |
| 8 | `intrinsic-grid` | Layout | `layout.md` | Kevin Powell, Breakpoint-Free CSS Grid Layouts, 2025-02-19 · Stephanie Eckles, Smol Responsive CSS Grid · Una Kravets, Ten modern layouts in one line of CSS |
| 9 | `subgrid-rows-shared-across-cards` | Layout | `layout.md` | Josh W. Comeau, Brand New Layouts with CSS Subgrid, 2025-11-25 · Kevin Powell, Subgrid & Container Queries change how we can create layouts, 2023-10-26 |
| 10 | `sidebar-that-wraps-on-its-own` | Layout | `layout.md` | Heydon Pickering and Andy Bell, The Sidebar, Every Layout |
| 11 | `container-queries-with-container-units` | Layout | `layout.md` | Kevin Powell, Improve your reset with these modern CSS additions, 2024-09-04 · Una Kravets, Container queries land in stable browsers, 2023-02-14 · Josh W. Comeau, A Friendly Introduction to Container Queries, 2024-11-04 · Stephanie Eckles, Container Query Units and Fluid Typography |
| 12 | `stack-layers-with-grid` | Layout | `layout.md` | Ana Tudor, @anatudor on X, 2025-03-29 |
| 13 | `safe-alignment` | Layout | `layout.md` | Temani Afif, Safe align your content, 2025-06-10 |
| 14 | `overflow-clip-over-hidden` | Layout | `layout.md` | Kevin Powell, 2 better alternatives to overflow: hidden, 2023-12-14 |
| 15 | `section-spacing-that-depends-on-its-neighbors` | Spacing and shape | `spacing-and-shape.md` | upstream's own pattern, used on production CMS sites · Kevin Powell, The adjacent sibling combinator · Jen Simmons, Using :has() as a CSS Parent Selector and much more, 2022-08-18 |
| 16 | `space-between-siblings-set-by-the-parent` | Spacing and shape | `spacing-and-shape.md` | Heydon Pickering and Andy Bell, The Stack, Every Layout · Heydon Pickering, Axiomatic CSS and Lobotomized Owls, 2014-10-21 · Andy Bell, My favourite 3 lines of CSS, 2023-02-06. Upstream's difference: those sources apply margins in every context, where upstream's version switches to `gap` inside components. |
| 17 | `push-one-item-away-with-an-auto-margin` | Spacing and shape | `spacing-and-shape.md` | Heydon Pickering and Andy Bell, The Stack (its Splitting the stack section) and The Cover, Every Layout. Upstream's difference: The Cover sets a margin on each child and then cancels it on the first and last, which a single `gap` replaces. |
| 18 | `concentric-nested-radius` | Spacing and shape | `spacing-and-shape.md` | Chris Coyier, The Classic Border Radius Advice, Plus an Unusual Trick, 2024-05-13, citing a variant by Jhey Tompkins. Upstream's difference: its recipe starts from the outer radius, removes the parent's padding and border, and never goes below zero; the form that starts from an inner-radius token remains a separate rule. |
| 19 | `long-text-that-wraps-truncates-or-clamps` | Text and media | `text-and-media.md` | Ahmad Shadeed, Defensive CSS, the tips Long content and Minimum content size in flexbox · Ahmad Shadeed, Handling Short And Long Content In CSS, 2020-12-16 |
| 20 | `image-box-that-holds-any-upload` | Text and media | `text-and-media.md` | Ahmad Shadeed, Defensive CSS (tips: Image distortion, Image inner border, Default flexbox stretching); upstream outlines the inner edge rather than adding his extra element · Heydon Pickering and Andy Bell, The Frame, Every Layout, a wrapper around media; upstream puts the declarations straight on `img`, `video` and `iframe`. |
| 21 | `tabular-numbers` | Text and media | `text-and-media.md` | Rauno Freiberg, Web Interface Guidelines · Vercel Web Interface Guidelines |
| 22 | `label-centered-on-its-letters-with-text-box` | Text and media | `text-and-media.md` | Stripe, whose stripe.com buttons use it. Upstream's note: those buttons are flex containers, where the property does nothing and asymmetric padding centers the label instead; upstream's first rule for the technique corrects that. |
| 23 | `icon-sized-by-the-text-beside-it` | Text and media | `text-and-media.md` | Andy Bell, How I build a button component, 2024-09-18, for `cap` and `flex: none`, and LH units are cool, 2023-12-13 · Heydon Pickering and Andy Bell, The Icon, Every Layout |
| 24 | `one-focus-ring-with-focus-visible` | Interaction | `interaction.md` | Stephanie Eckles, Modern CSS Upgrades To Improve Accessibility, 2021-04-09, and Smol Focus Styles · Kevin Powell, 3 super small changes to improve your CSS, 2023-03-07. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 25 | `hover-styles-only-where-hover-exists` | Interaction | `interaction.md` | Emil Kowalski, mobile-native skill and emil-design-eng skill · Rauno Freiberg, Web Interface Guidelines. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 26 | `press-feedback` | Interaction | `interaction.md` | Emil Kowalski, emil-design-eng skill and mobile-native skill |
| 27 | `hit-area-larger-than-the-visual` | Interaction | `interaction.md` | Emil Kowalski, Agents with Taste: the rule · Vercel Web Interface Guidelines · the `inset` formula is upstream's own. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 28 | `whole-card-clickable-from-one-link` | Interaction | `interaction.md` | Heydon Pickering, Cards, for the stretched `::after` · Stripe, for moving the focus ring to the card with `:has()`. Superseded by `card-with-a-distinct-link`; see "Not carried" above. |
| 29 | `has-for-parent-and-page-state` | Interaction | `interaction.md` | Jen Simmons, Using :has() as a CSS Parent Selector and much more, 2022-08-18 · Josh W. Comeau, The Undeniable Utility Of CSS :has, 2024-09-09 · Chris Coyier, Scroll-Locked Dialogs, 2024-02-19 |
| 30 | `form-feedback-with-user-invalid` | Interaction | `interaction.md` | Kevin Powell, Improve forms with :user-valid and :user-invalid, 2025-02-20, and Use these CSS features instead of JavaScript, 2026-09-23 |
| 31 | `textarea-that-grows-with-its-content` | Interaction | `interaction.md` | Jhey Tompkins, @jh3yy on X, 2026-10-01 |
| 32 | `opt-in-motion` | Motion | `motion.md` | Josh W. Comeau, Accessible Animations in React with "prefers-reduced-motion" · Kevin Powell, 3 super small changes to improve your CSS, 2023-03-07 |
| 33 | `motion-tokens` | Motion | `motion.md` | Emil Kowalski, emil-design-eng skill and 7 Practical Animation Tips. Superseded in part: the permanent-exit `--ease-in` curve, the `page` role and the exit factor follow `docs/upstream/aiforui-course.md` |
| 34 | `transition-a-custom-property-with-property` | Motion | `motion.md` | Stripe, on the stripe.com home page and its sales contact page |
| 35 | `shadow-change-that-fades-and-does-not-repaint` | Motion | `motion.md` | Stripe, on its resource cards · Tobias Ahlin, How to animate box-shadow, for the older form of the idea |
| 36 | `cross-document-view-transitions` | Motion | `motion.md` | Jen Simmons and James Craig, Two lines of Cross-Document View Transitions code you can use on every website today, 2025-05-21 · Bramus Van Damme, Cross-document view transitions for multi-page applications |
| 37 | `indicator-that-slides-to-the-active-item` | Motion | `motion.md` | Stripe: a vertical side-nav variant in the stylesheet of its home page. Upstream's note: it located the CSS but no rendered page using it, so the technique rests on the stylesheet only. |
| 38 | `enter-and-exit-transitions-from-display-none` | Show and hide | `show-and-hide.md` | Una Kravets and Joey Arhar, Four new CSS features for smooth entry and exit animations · Kevin Powell, Transition to and from display: none, 2026-07-22 · Chris Coyier, In-N-Out Animations: Dialogs, 2026-06-01 · Adam Argyle, Steal this popover code, 2024-03-15 · Ahmad Shadeed, Grouping vendor selectors, Defensive CSS, for the split rules |
| 39 | `popover-anchored-to-its-trigger` | Show and hide | `show-and-hide.md` | Una Kravets, Introducing the CSS anchor positioning API, 2024-05-10 · Saron Yitbarek, A gentle introduction to anchor positioning, 2025-08-12 · Adam Argyle, Why isn't my position-try-fallback working in small spaces?, 2024-10-12 |
| 40 | `accordion-that-animates-its-height` | Show and hide | `show-and-hide.md` | Bramus Van Damme, Animate to height: auto |
| 41 | `reveal-with-clip-path` | Show and hide | `show-and-hide.md` | Stripe, stripe.com's navigation menu · the `visibility` handling is upstream's own. |
| 42 | `carousel-on-native-scroll` | Scroll and viewport | `scroll-and-viewport.md` | Steve Sewell, Build buttery smooth carousels with pure CSS like Nike. Upstream's difference: `scrollBy()` replaces his `scrollIntoView()`, so the controls move the carousel alone and leave the page where it is. |
| 43 | `scroll-area-between-a-fixed-header-and-footer` | Scroll and viewport | `scroll-and-viewport.md` | Ahmad Shadeed, Defensive CSS (tips: Scrollbars on demand, Scrollbar gutter, Scroll chaining, Minimum content size in flexbox). His tips cover each declaration separately; the surrounding panel layout is upstream's own. |
| 44 | `styles-that-apply-only-when-a-scroller-overflows` | Scroll and viewport | `scroll-and-viewport.md` | Stripe, in the navigation on stripe.com · Bramus Van Damme, Detect if an element can scroll or not with only CSS. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 45 | `anchor-targets-that-clear-a-sticky-header` | Scroll and viewport | `scroll-and-viewport.md` | Kevin Powell, Stop fixed navigations covering content on scroll, 2022-06-02, and Use these CSS features instead of JavaScript, 2026-09-23. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 46 | `no-rubber-band-bounce-on-desktop` | Scroll and viewport | `scroll-and-viewport.md` | wits (@witsdev on X), 2026-09-30, on Vercel limiting it to `pointer: fine` devices · Jhey Tompkins (@jh3yy on X): the `any-pointer` variant · Emil Kowalski, mobile-native skill: nested scroll containers. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |
| 47 | `content-clear-of-the-notch` | Scroll and viewport | `scroll-and-viewport.md` | Emil Kowalski, mobile-native skill. Text since reshaped by the course record, [`aiforui-course.md`](aiforui-course.md). |

<!-- spellchecker:on -->

## License notice

The technique text in `plugins/user-interface/skills/write-css/reference/` and the vendored
`check-css.mjs` carry material from vojtaholik/good-css. Per the MIT condition, the upstream
copyright line and permission notice travel with them: `skills/write-css/vendor/LICENSE` holds the
license file unmodified, and the notice is recorded here and in the `user-interface` CHANGELOG entry
that adds `/user-interface:write-css` (the changelog ships with the installed plugin; this record
does not). Nothing is placed in the skill body or its references.

```text
MIT License

Copyright (c) 2026 Vojta Holik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
