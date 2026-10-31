# Color terms

How color is defined, mixed, and applied. Each entry gives the term, a definition, and the line
between it and the term most often confused with it.

## Color: `color`

### sRGB: `srgb`

The standard color space most screens have used for decades. All hex values live here. Its gamut is
limited: there are colors a modern display can show that sRGB cannot describe.

**Versus:** P3 is the wider gamut; sRGB is the narrower one every hex value lives in.

### OKLCH: `oklch`

A color space that matches how humans perceive brightness. Unlike HSL, two colors at the same
lightness value actually look the same brightness. Useful for generating palettes and accessible
color mixes.

**Versus:** HSL also has a lightness value, but equal HSL lightness does not look equally bright.

### Semantic token: `semantic-token`

A color variable named for its purpose rather than its value. `--color-border-subtle` instead of
`#e0e0e0`. When the value changes, everything using the token updates.

**Versus:** a primitive value or a raw hex names the color itself; a semantic token names its
purpose.

### Tinted neutral: `tinted-neutral`

A gray with a slight hue bias. Pure `#808080` looks like a placeholder. A tinted neutral feels
chosen.

**Versus:** a pure neutral has no hue at all; a tinted neutral leans slightly toward one.

### Chroma: `chroma`

The OKLCH equivalent of saturation, but perceptually accurate. Reducing chroma for a light tint
keeps the color alive. Reducing opacity does the same but turns it gray and lifeless.

**Versus:** saturation is the HSL measure of the same idea; opacity fades a color toward its
background instead of keeping it vivid.

### Opacity vs visibility: `opacity-vs-visibility`

Two ways to hide an element. Opacity zero still occupies space and receives pointer events.
Visibility hidden removes interaction but keeps the space. Worth knowing which you need.

**Versus:** display none removes the element from layout entirely; opacity and visibility both keep
its space.

### Blending: `blending`

How a layer interacts with what's beneath it. Multiply darkens, Screen lightens, Overlay does both
depending on the base color. Useful for integrating images with colored surfaces and adding depth to
illustrations.

**Versus:** opacity only makes a layer more see-through; blending computes a new color from the
layer and what is beneath it.

### P3: `p3`

A wider color space supported by most modern screens. Allows more vivid colors, particularly greens
and reds, that sRGB cannot reach.

**Versus:** sRGB is the narrower gamut; P3 reaches colors sRGB cannot describe.

### Alpha: `alpha`

The transparency component of a color, from fully opaque to fully invisible. An alpha border recedes
into the surface beneath it. A solid hex sits on top. The difference is subtle but consistently
felt.

**Versus:** opacity applies to the whole element and its children; alpha belongs to one color value.

### Contrast ratio: `contrast-ratio`

The luminance difference between a foreground and background color, the measure WCAG sets its
contrast minimums in.

**Versus:** APCA is a newer contrast model that weighs font size and weight; the contrast ratio is
the WCAG measure.

### Saturation: `saturation`

How vivid or muted a color is. Brand colors at full saturation in dark mode can vibrate off the
screen. Pulling back 20-30% settles them.

**Versus:** chroma is the perceptually accurate OKLCH equivalent; saturation is the HSL measure.

### Gradient: `gradient`

A transition between two or more colors. In HSL or sRGB, the midpoint often goes gray. Building
gradients in OKLCH keeps the colors vivid throughout.

**Versus:** a mask uses a gradient to fade visibility, not color; a gradient here is a transition
between colors.

### Dark mode: `dark-mode`

An interface built on dark surfaces. The brightest surface should sit at the top of the layering
hierarchy. Light mode tokens rarely translate directly, so every color decision needs rechecking.

**Versus:** prefers color scheme is the media query that detects the user's preference; dark mode is
the interface built for it.

## Sources

Contrast ratio is the one home of WCAG contrast here, and names its thresholds without stating them.

- **Pointer**: when a contrast threshold decides a finding, fetch https://www.w3.org/TR/WCAG22/#contrast-minimum and https://www.w3.org/TR/WCAG22/#non-text-contrast live.
- **As of**: 2026-10-28
- **Recheck trigger**: a WCAG version after 2.2 becomes a W3C Recommendation.
