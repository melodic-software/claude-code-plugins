# Order of work

The order skills run in for a single screen: decide with `/prototype:explore-directions`, build
with `web-layout` and one material skill, refine with `layout-stability` and
`/user-interface:write-animation`, review with `/user-interface:audit`, then start over on the next
screen. Maybe you want to run `/planning:interview product` first, to get a better understanding of
the product and the user needs. When every screen has been through the loop,
`/user-interface:audit launch` runs on the whole app. In this file a name in backticks that matches
a concern `id` in `concerns.json` is that concern, run as a pass of `/user-interface:design`, and a
material skill is the concern question 2 names.

## Route in two questions

**1. What phase are you in?** This picks the group. Every skill belongs to exactly one moment in
the work, and reaching for the wrong moment is the most common misroute: polishing something whose
layout is still wrong wastes the pass, because the polish gets thrown away with the layout.

| Phase | You're saying | Go to |
| --- | --- | --- |
| Undecided | "try a few", "not sure which", "show me options" | [Decide](#decide) |
| Foundation | "build this screen", "lay this out" | [Start here](#start-here) |
| Pieces | "build this card / form / component / landing page" | [Build](#build) |
| It works, it feels off | "make it feel finished", "this is janky", "on mobile it's broken" | [Refine](#refine) |
| It's done | "does this look right", "review before I ship", "we launch Thursday" | [Check](#check) |
| The words, not the work | "what's it called when…" | [Underneath](#underneath) |

**2. What is the thing?** Inside the group, the skill is named after the material: type, color,
surfaces, motion, forms, components. If two of them both look right, the answer is in
[Overlaps](#overlaps), not in reading both. Here the material names a concern `id`.

## Decide

- **`/prototype:explore-directions`**: build 3–5 genuinely different versions behind a live
  picker, with every uncertain number on a control, then write down what got picked and what got
  rejected. Reach for it the moment a decision hasn't been made yet. If the user already knows what
  they want, skip straight to the building skill. It builds three by default, its `controls` action
  puts the uncertain numbers on controls, and its "Signs this skill fits" holds the rule for a
  settled question: "a switcher holding three answers to a settled question wastes everyone's
  time."

## Start here

The foundation. Most screens need these three before anything else, and running them after the
pieces are built means redoing the pieces.

- **`web-layout`**: hierarchy, spacing, alignment, restraint. The default answer to "this screen
  looks off and I can't say why". Also owns the supporting elements nobody assigns to a skill:
  button hierarchy, empty states, error messages, microcopy. Here `web-layout` keeps button
  hierarchy; restraint is `principles.md` "Work in this order", empty states are the `states`
  concern, and error messages and microcopy follow `principles.md` "Plain-language copy".
- **`typography`**: font files, variable axes, type scales, line length, wrapping, truncation.
  Anything where the *text itself* is the problem.
- **`color`**: OKLCH palettes, tonal scales, dark mode derivation, contrast that actually passes
  WCAG. Any time a color value gets invented rather than chosen. The contrast bar is the `color`
  concern's "Operating principles".

## Build

The pieces that sit on the foundation.

- **`shape-and-depth`**: shadows, borders, gradients, elevation, and the dark-mode versions of all
  four. Cards, modals, dropdowns, images. The dark-mode surfaces are the `theming` concern's.
- **`component-api`**: the *props API* of a component other people will reuse: composition over
  configuration, compound components, controlled/uncontrolled. Not how it looks.
- **`forms`**: forms, inputs, buttons, validation timing, loading and disabled states, submit
  behavior. Anything a user types into or presses.
- **`marketing-pages`**: landing pages, blogs, docs, changelogs. Owns what's different about
  marketing surfaces: motion restraint, SEO, static generation, CTAs. It pulls the foundation
  skills in rather than replacing them. Here it names the foundation concerns as further passes.

Build also holds `icons` (icon sets, sizes, illustrations) and `theming` (dark mode and the theme
switch). The CSS for any of these pieces goes to `/user-interface:write-css` once the design
decisions are made, as `/user-interface:design` Step 4 says.

## Refine

The screen works. Now it has to feel built.

- **`/user-interface:write-animation`**: whether to animate at all, then easing, duration, springs,
  enter/exit. Motion that looks *wrong*. It builds from the `motion` concern.
- **`layout-stability`**: the invisible pass: font rendering, tabular numbers, layout shift,
  hover/focus/pressed states, hit areas, truncation, stacking. Motion that looks *unfinished*. Here
  that pass is split by concern: `layout-stability` for tabular numbers and layout shift,
  `typography` for font rendering and truncation, `touch` for hover and hit areas, `forms` and
  `accessibility` for pressed and focus states, `web-layout` for stacking.
- **`web-performance`**: virtualization, preloading, GPU compositing, layout stability. Anything
  measured in frames, milliseconds, or scroll jank. An animation that drops frames is the `motion`
  concern's, through `/user-interface:audit performance`, and layout stability is
  `layout-stability`'s.
- **`accessibility`**: tap targets, hover vs touch, focus management, aria, reduced motion, iOS
  Safari quirks. This is a floor, not a refinement: if it fails here it ships broken for someone, so
  run it even when the screen already looks finished. Tap targets, hover on touch and iOS Safari
  quirks are the `touch` concern's, and reduced motion is the `motion` concern's.
- **`touch`**: the platform layer on a phone: sticky hover, the tap flash, `100vh`, inputs that
  zoom, safe areas, the software keyboard, overscroll, `theme-color`. Reach for it when the
  complaint is "it works in Chrome but feels like a website on my phone". Most of those reports
  aren't animation problems, so try this before `/user-interface:write-animation`. `theme-color`
  per color scheme is the `theming` concern's.

Refine also holds `states` (empty, loading, error and success views) and `generic-defaults` (output
that looks templated or AI-generated).

## Check

- **`/user-interface:audit`**: point it at a diff, a generated component, or a change request and
  get findings ranked by how much they hurt. It **reports, it doesn't fix**. Reach for it after an
  agent builds UI, which is the case it exists for: models produce interfaces that look right in a
  screenshot and fall apart under a real cursor. Here `--fix` applies one finding at a time after a
  yes.
- **`/user-interface:audit launch`**: sweep the **whole app** before a launch, a release, or a
  demo: accessibility, performance, mobile, forms, loading/empty/error states, motion, dark mode,
  leftover debug output and dev tools, metadata. It **finds what a diff can fix**, then lists what
  needs a phone or a person and ends with Ship or Not yet. It's the one exception to "one or two
  skills": it crosses every other skill on purpose, an inch deep, and names the owning skill when a
  finding needs more than a one-line fix. Run it last, and **never while the screen is still being
  designed**: it fixes defects, not taste. Here the sweep stays read-only unless `--fix` was given,
  then takes a yes per finding, naming the owning concern, as `/user-interface:audit`'s launch
  scope says.

## Underneath

Run beneath the others. Reach for them when the **words**, not the work, are the problem. Both
exist because a vague prompt gets a vague interface. Getting the term right before asking for the
thing is the cheapest quality win available. Here both lookups, a visual concept and a behavior,
are `/user-interface:glossary`.

## Overlaps

The routes that get confused. Each pair is one question, not two skills to read.

| If you're torn between | Ask | Then |
| --- | --- | --- |
| `web-layout` / `layout-stability` | Is the layout itself wrong, or right but unfinished? | Wrong → `web-layout`. Unfinished → `layout-stability`. |
| `layout-stability` / `/user-interface:audit` | Do you want it fixed, or told what's wrong? | Fixed → `layout-stability`. Told → `/user-interface:audit`. |
| `/user-interface:write-animation` / `/user-interface:audit performance` | Does it look wrong, or does it drop frames? | Looks wrong → `/user-interface:write-animation`. Drops frames → `/user-interface:audit performance`. |
| `/user-interface:write-animation` / an `animation` capture | Do you know what the motion is doing? | No → the capture first. Yes → `/user-interface:write-animation`. |
| `color` / `shape-and-depth` | Is it the value, or what's built from it? | Palette, contrast, dark-mode values → `color`. Shadow, border, gradient, elevation → `shape-and-depth`. |
| `typography` / `web-layout` | Is the text the subject, or one element in a layout? | Subject → `typography`. Element → `web-layout`. |
| `component-api` / everything visual | Is the problem the props, or the pixels? | Props → `component-api`. Pixels → the matching visual skill. |
| `accessibility` / `layout-stability` | Is it broken for someone, or merely unpolished? | Broken → `accessibility`, and it's blocking. |
| `/user-interface:audit` / `/user-interface:audit launch` | One diff, or the whole app? | A diff you want judged → `/user-interface:audit`. The app, the week it ships → `/user-interface:audit launch`. |
| `accessibility` / `touch` | Is someone locked out, or does it just feel like a website? | Keyboard, screen reader, focus → `accessibility`. Viewport, browser chrome, scroll, keyboard, tap targets, tap feel on a phone → `touch`. |
| `touch` / `/user-interface:write-animation` | Does it feel wrong only on the phone? | Yes → `touch` first. A tap delay or a stuck hover reads as bad motion and isn't. |
| `/prototype:explore-directions` / any building skill | Has the decision been made? | No → `/prototype:explore-directions`. Yes → build the one thing. |

An `animation` capture is `/app-control:drive capture --kind animation`, read through
`/user-interface:audit`'s frame-capture reference when the motion is not yet understood.

## Stacking

Real work runs two or three in sequence, never in parallel.

- **New screen** → `web-layout`, then the material skill for whatever it's made of, then
  `/user-interface:audit` before it ships.
- **New component** → `/prototype:explore-directions` if undecided → build →
  `/user-interface:write-animation` if it moves → `accessibility`.
- **"Feels cheap"** → `layout-stability` first. It's the highest hit rate on that complaint. Only
  escalate to `web-layout` if the polish pass finds the structure is the problem.
- **"Feels slow"** → `web-performance`, not `/user-interface:write-animation`. Slowness is
  measured; motion taste is judged.
- **Landing page** → `marketing-pages`, which brings the rest in itself. Here it names the
  foundation concerns as further passes.
- **"Feels off on my phone"** → `touch`. Only move on to `/user-interface:write-animation` or
  `web-performance` once the platform tells are gone and it still feels wrong.
- **Launch week** → `/user-interface:audit launch`, once, on the whole app. Whatever it puts on its
  human list comes back to the owning skill after launch.

The polish pass in these lines is the Refine pass, split by concern as Refine says.

## When you don't know which skill

| The complaint | Run this |
| --- | --- |
| I'm not sure which direction | `/prototype:explore-directions` |
| This screen looks off | `web-layout` |
| It feels cheap | `layout-stability` |
| It feels slow | `web-performance` |
| It feels wrong on my phone | `touch` |
| The animation is off | `/user-interface:write-animation` |
| It looks vibe-coded | `generic-defaults` |
| Is this good? | `/user-interface:audit` |
| We are shipping soon | `/user-interface:audit launch` |
| One artifact keeps missing after prompting (a texture, a curve, a generated shape) | `/prototype:build-generator` |
| The contract is not a UI component's props (types, module boundaries, a service's API) | `/planning:design` |

## When nothing fits

Say so. These skills cover the interface: layout, type, color, surfaces, motion, components, forms,
accessibility, performance. They do not cover backend logic, data fetching, state management, build
tooling, or testing. Stretching `web-layout` over a database question produces confident nonsense,
and the user can't tell it apart from a real answer. Answer normally instead, and say no skill
applies.
