# Layout and spacing

Read this when a web screen is laid out from scratch, or an existing one looks off and nobody can
say why: hierarchy, spacing, alignment, grids, containers, stacking order and the layers that sit
over content. The project's own spacing scale, tokens and layout conventions win over every rule
here; suggest a change to them, never override them.

The CSS that implements these rules is in `/user-interface:write-css`: its `layout.md`,
`spacing-and-shape.md` and `foundations.md` recipes, named by id beside the rule that uses them.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

## 1. Settle layout first

This concern goes first on almost every interface feature. It owns hierarchy, spacing and
alignment.

A worked example: a domains settings page that looks generated, a card with a gradient, emoji and
badges around a table and an add-domain field. The layout pass asked to fix the hierarchy and
spacing, and to drop anything that isn't adding value. After it, the card, the gradient, and the
sparkle are gone. The title is now the biggest thing on the page, the status is a dot with quiet
text, and there's one primary button. The page finally looks like it belongs to a product.

The form is still broken though: no validation, and any text is added to the list. That's fine,
because layout doesn't own forms. Next comes one concern for whatever the screen is made of:

- `forms` for anything a person types into or presses
- `shape-and-depth` for cards, modals, dropdowns, shadows, and borders
- `typography` when you want to change the font, size, weight, or line height
- `component-api` for the props of a component other people will reuse
- `marketing-pages` for a landing page, which pulls the others in by itself

## 2. Core principles

1. **One primary action per view.** If three buttons carry equal visual weight, none of them is the
   next step. Demote: primary, secondary ghost, text link. Secondary actions are visually quieter.
2. **Hierarchy is subtraction.** Make the important thing prominent by making everything else
   recede; don't make everything louder. Restraint: if everything is emphasized, nothing is. Fewer
   borders, fewer shadows, fewer competing focal points.
3. **Space with system, not eyeballing.** Spacing follows a consistent scale, not arbitrary one-off
   values, and `gap` over per-child margins.
4. **Know when to break the rules.** The baseline-grid rule below is a trick question on purpose.
   The rule is the default; context decides.
5. **Specific beats generic.** "Save changes" beats "Submit". "Your email must include an @ symbol"
   beats "Invalid input". Empty states say why and what to do next.
6. **Use semantic tokens and perceptual color spaces.** `--color-border-subtle` over raw hex; OKLCH
   over HSL when comparing or deriving lightness; `color-mix` over hand-picked hover hexes.
7. **Every state is designed.** Default, hover, focus, active, disabled, loading, empty, error: each
   visually distinct. A missing pressed state makes a button feel dead.
8. **Accessibility is a floor.** Focus rings, labels wired to inputs, real `<button>` elements,
   color-plus-icon-plus-text for errors. Non-negotiable, not a polish pass.

The detail behind principles 5 to 8 lives in its own concern: copy in the plain-language rule of
`../../principles.md`, tokens and color spaces in `color`, each state in `states`, and the floor in
`accessibility`. Borders and shadows that recede rather than sit on top are the `shape-and-depth`
concern. A finding against principles 5 to 8 takes its severity from that owner once the owner
grades it; until then, the tag below grades generic copy.

**Audit: Important.** More than one visually primary button in view.

**Audit: Suggestion.** Everything emphasized at once: competing focal points, or borders and
shadows added where removing something would have made the important thing stand out.

**Audit: Important.** Generic copy ("Submit", "Invalid input", "No items") where the specific
outcome or fix is known. This holds until `../../principles.md` grades its plain-language copy
rule.

## 3. Spacing

Take spacing steps from the project's spacing tokens; with none,
`one-fluid-scale-for-type-and-space` derives a scale.

**Audit: Important.** Arbitrary one-off spacing values where the project has a scale.

Space siblings with `gap` on the parent, not `margin-bottom` on every child: margin leaves a
trailing gap after the last item. Inside components, prefer `gap` over `margin`: margin bleeds past
the component boundary, gap stays contained. Recipe: `space-between-siblings-set-by-the-parent`.

**Audit: Important.** Per-child margins instead of parent `gap`.

Radius between nested surfaces is the `shape-and-depth` concern; paragraph spacing and line length
are the `typography` concern.

## 4. Alignment

Edges align. Optical alignment beats mathematical when they disagree.

Mathematical centering often reads as off-center; nudge elements until they look right:

- Button with trailing icon: icon-side padding = text-side padding − 2px (`pl-4 pr-3.5`). Those
  are Tailwind classes; in plain CSS, `padding-inline: 16px 14px`.
- Play triangles: shift `2px` toward the pointed side (`margin-left: 2px`).
- Asymmetric icons (stars, arrows, carets): fix the SVG viewBox/path itself; a `1px` margin is the
  fallback.

**Audit: Suggestion.** Edges that almost line up, or an icon visually off-center in a button: −2px
padding on the icon side; fix the SVG for asymmetric icons.

## 5. Grids and containers

Cap content containers (~1200px, centered) on wide monitors. Uncapped layouts produce unreadable
line lengths and sparse, drifting compositions. Recipe: `content-grid-with-breakouts`.

**Audit: Important.** A page whose content stretches to the full width of a wide monitor.

Set breakpoints where the content breaks, not at device sizes (768/1024). Device-named breakpoints
routinely miss the actual failure point. Recipes: `intrinsic-grid`, `sidebar-that-wraps-on-its-own`
and `container-queries-with-container-units` remove many breakpoints altogether.

**Audit: Suggestion.** Breakpoints at device widths that do not match where the layout breaks.

A simple marketing page doesn't need a 12-column grid: 8 columns (or fewer) does the job without
configuration overhead.

Baseline grids are an editorial tool: they shine in long-form layouts and are usually overkill in
dense product UI. (Trick question: know which context you're in.)

Symmetric two-column layouts are static; a wider column offset by a narrower one creates tension
and interest.

**Audit: Suggestion.** A 12-column grid or a baseline grid where the page needs neither, or an
even two-column split where a wider column beside a narrower one would carry the hierarchy.

Constrain sticky headers with `max-height` and `dvh` units. An 80px header on a 667px landscape
viewport leaves almost no room for content. The 667px is that viewport's width; the height the
header competes with is the short side, so cap it in `dvh` rather than at a device size.

**Audit: Important.** A sticky header with a fixed height and no cap against the viewport height.

A fixed bottom call to action on a phone needs safe-area padding: that rule is the `touch`
concern's.

Text over full-bleed images requires a scrim, color-matching, and contrast checks. Text in a
column beside or below the image just works: default to that. The contrast bar itself is the
`color` concern's. Recipe for the layered case: `stack-layers-with-grid`.

**Audit: Important.** Text over a full-bleed image with no scrim.

## 6. Stacking comes from a scale

`z-index: 9999` is how a toast ends up behind a modal, a dropdown gets clipped under a sticky
header, and a tooltip disappears inside a dialog. These only show up when two layers meet, which is
never on the screen the developer was looking at.

No arbitrary `z-index: 9999`. Define a scale and use only its steps:

```css
:root {
  --z-dropdown: 100;
  --z-modal: 200;
  --z-tooltip: 300;
  --z-toast: 400;
}
```

Tokens go wherever the project keeps its design tokens. Better: avoid z-index entirely where
possible. `isolation: isolate` (or `position: relative` with a `z-index` other than `auto`) creates
a local stacking context so children can't leak above unrelated UI. Where a component only needs
its children contained, `isolation: isolate` beats a z-index.

- **Pointer**: MDN, Stacking context, Features creating stacking contexts,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Positioned_layout/Stacking_context#features_creating_stacking_contexts>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes which `position`, `z-index` or `isolation` values form a
  stacking context.

If the project has a scale, move the strays onto it. If it doesn't, don't invent one mid-sweep: fix
the collisions that are provably wrong (toast under modal) and note the rest. That choice belongs
to an audit sweep; when writing or revising the CSS, define the scale above. Put on the device
list: "open a modal, trigger a toast, open a dropdown inside the modal, hover a tooltip inside the
dropdown". The stacking check passes only on a real device, not from reading the code.

Hunt for: `z-index` values over 100 that aren't tokens; `z-[9999]`, `z-50` sprinkled without a
system; portaled and non-portaled overlays mixed. The bracketed and numbered forms are Tailwind
class names to search for.

**Audit: Blocking.** `z-index: 9999` or any random large z-index instead of a scale. Blocking
applies where the project has a scale or the value causes a collision you can show (a toast under a
modal).

**Audit: Important.** The same value in a project with no scale and no collision shown: note it
rather than invent a scale mid-sweep.

**Audit: Important.** Other `z-index` values off the project's scale, or portaled and non-portaled
overlays mixed.

## 7. Decorative layers are inert

A gradient overlay, a glow, or an illustration positioned over a control swallows its clicks. It
works on the developer's viewport and fails at the width where the two overlap.

Anything purely visual gets `pointer-events: none` so it can't steal clicks from real controls, and
code-built illustrations get `user-select: none`.

```css
.hero-glow, .fade-overlay { pointer-events: none; }
```

Hunt for: absolutely positioned decorative elements (gradients, noise, glows, fades) without
`pointer-events: none`.

**Audit: Important.** A decorative layer over a control without `pointer-events: none`.

**Audit: Suggestion.** A code-built illustration without `user-select: none`.
