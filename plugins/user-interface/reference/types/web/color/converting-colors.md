# Converting colors to OKLCH

Read this from `../color.md` when rewriting hex, `rgb()` or `hsl()` literals as oklch. The
project's linter and browser targets win; a value a third-party consumer parses stays in the
format it expects.

Conversion is a value-for-value substitution. The declaration, the selector, the surrounding
function: all of it stays exactly as written; only the color literal itself changes notation.

## What never gets converted

Rule these out before starting, so a mechanical pass doesn't break anything:

- **Keywords**: `currentColor`, `transparent`, `inherit`, `initial`, `unset`. These aren't colors
  to translate; they're behavior.
- **Gradient machinery**: inside a `linear-gradient()` or `conic-gradient()`, rewrite the stops but
  leave the function's shape and any interpolation hints (`in oklab`, `in srgb`, angle, positions)
  untouched.
- **Third-party configuration**: a charting library or manifest field that parses hex gets hex.
  Converting it breaks the consumer, not the color. The same holds for a component prop that takes
  a color string and the `theme-color` meta tag.

**Audit: Blocking.** A conversion that rewrites a keyword, a gradient's interpolation hint, or a
value a third-party consumer parses as hex.

## What counts as input

Any of the legacy notations qualifies: hex in 3, 6, or 8 digits (`#c00`, `#e11d48`, `#e11d4880`),
the `rgb()`/`rgba()` functions in either comma or space syntax, and `hsl()`/`hsla()` likewise.

## Worked examples

```css
/* before */
.alert-title { color: #e11d48; }
.hero        { background: #164e63; }
.callout     { border-color: #fef3c7; }

/* after */
.alert-title { color: oklch(0.586 0.222 17.585); }
.hero        { background: oklch(0.398 0.066 227.392); }
.callout     { border-color: oklch(0.962 0.058 95.617); }
```

Function notations follow the same substitution, with any alpha channel moving behind a slash:

```css
/* before */
.badge   { background: rgb(22, 163, 74); }
.divider { border-top: 1px solid rgba(255, 255, 255, 0.12); }
.link    { color: hsl(268, 60%, 45%); }

/* after */
.badge   { background: oklch(0.627 0.17 149.214); }
.divider { border-top: 1px solid oklch(1 0 none / 0.12); }
.link    { color: oklch(0.468 0.202 299.662); }
```

When alpha is fully opaque, write the three-channel form: no `/ 1` suffix.

**Audit: Suggestion.** An opaque oklch value written with a `/ 1` alpha.

A pure gray, white or black has no hue: write `none` in the hue slot, as in
`oklch(1 0 none / 0.12)`, so a mix with another color keeps that color's hue (recipe `oklch-color`
in `/user-interface:write-css`).

**Audit: Important.** A gray, white or black written with a numeric hue (`oklch(1 0 0 / 0.12)`),
which pulls every `color-mix()` it enters toward that hue (`0` is red).

## Whole-file passes

Migrating a stylesheet end to end:

1. Sweep hex literals first (they're unambiguous to spot), then the `rgb()`/`rgba()` and
   `hsl()`/`hsla()` calls.
2. Inside gradients, touch only the stop colors.
3. Skip everything on the never-convert list above.
4. Keep the author's comments, indentation, and declaration order: the diff should show nothing
   but color values changing.
5. If a converted value participates in a contrast-critical pair, sanity-check the pair afterward
   (`contrast.md`); the conversion is exact, but the audit is cheap.
6. A high-chroma result may sit outside the gamut a target screen can show: check it with
   `gamut-and-p3.md`.

**Audit: Suggestion.** A conversion diff that also reorders declarations, drops comments or
reformats lines.
