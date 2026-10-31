# Gamut and Display P3

Read this from `../color.md` when a color carries high chroma, a value may not fit the screen, or
the project serves wide-gamut colors or supports browsers without `oklch()`. The project's browser
targets win: check them before adding a fallback layer.

## The shape of the displayable

OKLCH describes more colors than any screen can show. Whether a given value is renderable depends
on the target gamut: sRGB is the safe universal floor, while Display P3 (standard on modern phones,
Macs, and better monitors) is a strict superset of sRGB, roughly a quarter larger, with its extra
room concentrated in intense greens, reds, and pinks.

Within either gamut, the chroma ceiling swings dramatically with both hue and lightness. Some
computed sRGB reference points:

- At mid lightness (L 0.5), violet-purples around H 285 enjoy the most headroom (C up to ≈ 0.29),
  reds around H 25 manage ≈ 0.20, and cyans near H 195 are pinned under ≈ 0.09: a 3× spread
  between the roomiest and tightest hues.
- The roomy region migrates as lightness changes: by L 0.7 the peak sits in the pinks (H ≈ 330,
  C ≈ 0.31), and by L 0.9 it has moved to spring greens (H ≈ 130, C ≈ 0.24).
- Cyan is cramped at every lightness: plan for muted teals in sRGB.

## When a value doesn't fit

A color whose C exceeds the ceiling for its L and H gets gamut-mapped by the browser, with results
you didn't choose. Handle it yourself instead: keep L and H (they carry the color's identity) and
pull C down to the boundary.

```css
/* asks for more red than sRGB has at this lightness */
color: oklch(0.6 0.31 20);

/* largest C that renders faithfully: */
color: oklch(0.6 0.241 20);
```

**Audit: Important.** A base color whose chroma exceeds the sRGB ceiling for its L and H, left to
the browser's gamut mapping.

## Progressive enhancement for P3

Ship the sRGB-safe value unconditionally and layer the wider-gamut version behind a capability
query:

```css
.cta {
  background: oklch(0.66 0.2 330);
}

@media (color-gamut: p3) {
  .cta {
    background: oklch(0.66 0.32 330);
  }
}
```

Here the sRGB chroma ceiling at this lightness and hue is about 0.30, and P3's is about 0.33, so
0.32 renders only on wide-gamut screens, and everyone else keeps the safe base.

**Audit: Important.** P3-only chroma with no sRGB base value beneath its `@media (color-gamut: p3)`
layer.

If the project's browser targets include browsers with no `oklch()` parser at all (the Baseline
link in the `oklch-color` recipe of `/user-interface:write-css` says which), put a hex floor
underneath and gate the modern syntax with `@supports`:

```css
.cta {
  background: #d25bcb;
}

@supports (color: oklch(1 0 0)) {
  .cta {
    background: oklch(0.66 0.2 330);
  }

  @media (color-gamut: p3) {
    .cta {
      background: oklch(0.66 0.32 330);
    }
  }
}
```

**Audit: Important.** `oklch()` with no fallback in a project whose browser targets include a
browser that cannot parse it.
