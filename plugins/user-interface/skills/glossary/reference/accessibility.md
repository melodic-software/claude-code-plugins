# Accessibility terms

How interfaces work for everyone. Each entry gives the term, a definition, and the line between it
and the term most often confused with it.

## Accessibility: `accessibility`

### WCAG: `wcag`

Web Content Accessibility Guidelines. The standard most teams use for color contrast; its contrast
check is the contrast ratio, defined in `color.md`.

**Versus:** APCA is a newer contrast model that weighs font size and weight; WCAG is the established
standard, and its contrast ratio is one of many criteria.

### Screen reader: `screen-reader`

Software that reads interface content aloud for blind or low-vision users. Navigates by DOM order,
heading structure, and ARIA roles, not visual layout. VoiceOver on Mac and iOS, NVDA and JAWS on
Windows are the most common.

**Versus:** a screen magnifier enlarges the screen for low-vision users; a screen reader speaks it.

### Prefers color scheme: `prefers-color-scheme`

A media query that detects the user's system theme preference. The right way to honor dark mode
without requiring a separate in-product setting.

**Versus:** reduced motion is the motion preference; prefers color scheme is the theme preference.

### Focus trap: `focus-trap`

Keeping keyboard focus inside an open modal or dialog. Without it, focus escapes to the page behind
the overlay.

Engineering: Tab keeps cycling inside the open modal instead of escaping to the page behind it.

**Versus:** a skip link moves focus past navigation; a focus trap keeps focus inside an overlay.

### Semantic HTML: `semantic-html`

Using the right element for the job. A button handles keyboard events, focus, and role for free. A
div styled as a button needs all of that added back manually.

Engineering: using elements for what they mean (button, nav, h1) so browsers and assistive tech
understand the page.

**Versus:** ARIA describes roles and states when HTML alone cannot; semantic HTML gets them from the
element itself.

### Color-only state: `color-only-state`

Using color as the sole signal for a state change. An error shown only by a red border is invisible
to colorblind users. Always pair color with an icon or text.

**Versus:** contrast ratio measures whether a color can be seen; color-only state is whether color
is the only signal.

### APCA: `apca`

Advanced Perceptual Contrast Algorithm. A newer contrast model that accounts for font size and
weight. More nuanced than WCAG for real-world conditions. The two specs sometimes disagree.

**Versus:** WCAG's contrast ratio uses one luminance formula for every size; APCA weighs font size
and weight.

### Tab order: `tab-order`

The sequence keyboard focus moves through when pressing Tab. Should follow a logical reading order.
Unexpected jumps are often caused by DOM and visual order being out of sync.

**Versus:** DOM order is the sequence in the markup; tab order is the sequence keyboard focus
follows through it.

### aria-label: `aria-label`

An accessible name for an element with no visible text. Should describe the action, not the element
type. Search, not icon.

**Versus:** label association links a visible label to an input; aria-label names an element that
has no visible text.

### DOM order: `dom-order`

The sequence of elements in the HTML. Screen readers follow this, not visual order. Reordering
visually with CSS while leaving the DOM unchanged creates a disconnect between what is seen and what
is read.

**Versus:** visual order is what CSS shows; DOM order is what assistive tech follows.

### Label association: `label-association`

Linking a label to its input via matching `for` and `id` attributes. Without it, clicking the label
does not focus the field.

**Versus:** a placeholder is hint text that disappears; an associated label stays and names the
field. aria-label is for an element with no visible label.

## Sources

The WCAG contrast pointer lives with Contrast ratio in `color.md`; APCA is named, not adopted.

- **Pointer**: when APCA decides a finding, fetch https://git.apcacontrast.com/documentation/APCA_in_a_Nutshell live.
- **As of**: 2026-10-28
- **Recheck trigger**: APCA ships in a WCAG draft.
