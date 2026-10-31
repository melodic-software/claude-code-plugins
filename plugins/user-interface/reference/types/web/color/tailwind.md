# Color in Tailwind

Read this from `../color.md` only when the project uses Tailwind. The project's own `@theme`
tokens, names and configuration win; suggest a change to them, never override them.

Tailwind's bundled palette is authored in oklch, so custom `@theme` scales should be too.

- **Pointer**: Tailwind CSS colors page, the default palette reference and "Customizing your
  colors", <https://tailwindcss.com/docs/colors#customizing-your-colors>; opacity modifiers,
  <https://tailwindcss.com/docs/colors#adjusting-opacity>
- **As of**: 2026-10-29
- **Recheck trigger**: a Tailwind major release, or the colors page changes the palette's notation,
  the `--color-*` theme namespace or the opacity modifier syntax.

**Audit: Suggestion.** Hex values inside a Tailwind v4 `@theme` block → convert them. How:
`converting-colors.md`.

## Declaring a scale

Tokens named `--color-<name>-<step>` inside `@theme` make the color utilities for that name
available: `bg-berry-400`, `text-berry-100`, `border-berry-700`, and friends:

```css
@theme {
  --color-berry-50:  oklch(0.97 0.007 330);
  --color-berry-100: oklch(0.895 0.042 330);
  --color-berry-200: oklch(0.82 0.103 330);
  --color-berry-300: oklch(0.745 0.189 330);
  --color-berry-400: oklch(0.67 0.251 330);
  --color-berry-500: oklch(0.595 0.231 330);
  --color-berry-600: oklch(0.52 0.195 330);
  --color-berry-700: oklch(0.445 0.151 330);
  --color-berry-800: oklch(0.37 0.105 330);
  --color-berry-900: oklch(0.295 0.063 330);
  --color-berry-950: oklch(0.22 0.03 330);
}
```

(Scale construction (lightness spacing, chroma curve, per-step clamping) is covered in
`building-scales.md`.)

## Opacity suffixes

The slash modifier composes with oklch tokens: `text-berry-600/75` sets the color's alpha to 75%.
No separate alpha variables needed.

## Porting a hex-based theme

1. Re-express every `@theme` color token as oklch.
2. Chase down `theme()` calls and component-level hardcoded hex that duplicated those tokens, and
   point them at the converted values.
3. Re-run your contrast checks and eyeball dark mode: exact conversion preserves each color, but
   colors that were *approximated* by eye in hex often turn out slightly off once measured
   perceptually.
4. Where the brand wants more punch than sRGB allows, add the `@media (color-gamut: p3)` layer from
   `gamut-and-p3.md` rather than raising the base token's chroma.

**Audit: Important.** Component-level hardcoded hex that duplicates a `@theme` color token.
