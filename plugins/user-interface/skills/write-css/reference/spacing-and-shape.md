# Spacing and shape

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `section-spacing-that-depends-on-its-neighbors`,
`space-between-siblings-set-by-the-parent`, `push-one-item-away-with-an-auto-margin`,
`concentric-nested-radius`.

## Section spacing that depends on its neighbors: `section-spacing-that-depends-on-its-neighbors`

Why: when two particular sections meet, the spacing between them changes on its own, so reordering
needs no spacer or per-page override.

Baseline: [`:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has#browser_compatibility);
the `+` combinator is widely available. As of 2026-10-11, recheck on a status change.

Use it on any page built from reorderable sections, above all in a CMS where an editor decides the
order.

```css
section { padding-block: var(--space-section, 6rem); }

.logos:has(+ .features) { padding-block-end: 2rem; }
.features:has(+ .cta) { padding-block-end: 0; }

.hero + .logos { padding-block-start: 2rem; }
.features + .faq { padding-block-start: 3rem; }

.logos:where(.hero + *) { border-block-start: 1px solid; }
```

Rules:

- A section owns its default padding. Write a pair rule only for a meeting that looks wrong with
  the defaults.
- Never fix spacing with a spacer element, a per-page override, or a modifier class the template
  has to work out.
- Put the rule on the section whose edge changes: look ahead to change a bottom edge, look back to
  change a top edge.
- Name sections by what they are (`.hero`, `.faq`), never by the page they sit on. The pair rules
  depend on those names.
- Keep the list short. When many pairs share a reason, such as the same background, write one rule
  for the reason.
- Where the authoring system has no sibling selectors, keep these few rules in a plain stylesheet.

## Space between siblings set by the parent: `space-between-siblings-set-by-the-parent`

Why: the parent sets one space between its children and no child carries a block margin, so a
moved or removed child never leaves a stray gap.

Baseline: [`gap` in flex layout](https://developer.mozilla.org/en-US/docs/Web/CSS/gap#browser_compatibility),
[`:is()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:is#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it wherever elements sit one above another: form fields, the parts of a card, the blocks of an
article.

```css
.fields {
  display: flex;
  flex-direction: column;
  gap: var(--space-s, 1rem);
}

.prose > * { margin-block: 0; }
.prose > * + * { margin-block-start: var(--flow-space, 1em); }

.prose > :is(h2, h3) { --flow-space: 2em; }
.prose > :is(h2, h3) + * { --flow-space: 0.5em; }
```

Rules:

- Use the flex form in a component whose children you know. Use the margin form for content you do
  not control, such as CMS or Markdown output, because flex turns every child into a flex item.
- A flex column stretches its children, so a direct-child button or link becomes full width. Set
  `align-self: start` on it.
- In the margin form, zero the children's block margins first, or the browser's default margins
  stay above the first child and below the last.
- Keep the `>`. Without it the rule reaches every nested element, list items included.
- The margin form counts a hidden child, so a hidden first child leaves a space at the top. `gap`
  ignores hidden children.

## Push one item away with an auto margin: `push-one-item-away-with-an-auto-margin`

Why: an auto margin absorbs the free space on one side, replacing a spacer element, `space-between`
over three or more children, or a wrapper around the group.

Baseline: auto margins work wherever flexbox does;
[`margin-block`](https://developer.mozilla.org/en-US/docs/Web/CSS/margin-block#browser_compatibility),
[`svh`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it when one item in a flex row or column sits apart: the actions at the bottom of a card, the
account link at the end of a toolbar, a title centered in a full-height section between a header
and a footer.

```css
.card {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.card > .actions { margin-block-start: auto; }

.toolbar {
  display: flex;
  gap: 1rem;
}

.toolbar > .account { margin-inline-start: auto; }

.hero {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  min-block-size: 100svh;
}

.hero > h1 { margin-block: auto; }
```

Rules:

- The container needs free space. A card has it when a grid row stretches it to match a taller
  neighbor. A column that is the only child of a taller box needs `block-size: 100%`.
- The centered item is centered in the space left over, not in the section. A footer with no
  header pulls the title up by half the footer's height.
- Write `min-block-size`, never `block-size`. A fixed height cuts off long content.
- This is a flex technique. In a grid column the spare height goes to the rows and every child
  grows.

## Concentric nested radius: `concentric-nested-radius`

Why: an outer radius of inner radius plus padding keeps the two curves parallel, so the nesting
looks deliberate.

Baseline: [`border-radius`](https://developer.mozilla.org/en-US/docs/Web/CSS/border-radius#browser_compatibility),
widely available. As of 2026-10-11, recheck on a status change.

Use it wherever a rounded element sits inside a padded rounded parent: an image in a card, a
button in an input.

```css
.card {
  --radius: var(--radius-m, 0.75rem);
  --pad: 0.5rem;
  padding: var(--pad);
  border-radius: calc(var(--radius) + var(--pad));
}

.card > * { border-radius: var(--radius); }
```

Rules:

- Derive the outer radius from the inner one. The other way round reaches zero once the padding
  exceeds the radius.
