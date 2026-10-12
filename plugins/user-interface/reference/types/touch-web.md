# Touch web: web interfaces used by finger

Scope: web pages and web apps reached on touch screens or other coarse, non-hovering pointers.
`principles.md` applies first and `web.md` is the base; this file adds only what touch changes.
The project's own conventions and its stack's documentation override it. Native and cross-platform
app stacks are `app.md`'s.

Gate on what the input can do, never on the device: a tablet with a trackpad, a laptop with a
touch screen and a phone with a mouse all exist. Query pointer and hover capability; never sniff
the user agent or guess touch from screen width. Browser behavior on touch changes between
releases, so each rule below names the behavior and the pointer says where to read it live.

## Hover and press

- Hover styles apply only where a precise pointer can hover. A touch screen fakes a hover on tap
  and leaves it applied, so an ungated hover effect sticks after the tap.
- Press feedback comes from the active state or pointer-down, never from the click, which arrives
  when the finger leaves and reads as lag. Keep it within the `press` role duration
  (`../animation/catalog.md`).
- Remove the browser's tap highlight only once every tappable element has its own pressed state.
- Mark controls that never zoom on double tap so a tap fires at once.

- **Pointer**: MDN, "hover" media feature,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/@media/hover>; "touch-action",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/touch-action>; "-webkit-tap-highlight-color",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/-webkit-tap-highlight-color>
- **As of**: 2026-10-11
- **Recheck trigger**: one of these pages changes its browser support or behavior notes.

## Targets

- Every tappable target meets the WCAG target size criterion; leave spacing between small targets.
- Text that is a control (a button label, a tab, a chip, a drag handle) is not selectable by long
  press; text that is content always stays selectable.

- **Pointer**: WCAG 2.2 Understanding 2.5.8 Target Size (Minimum),
  <https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html>
- **As of**: 2026-10-11
- **Recheck trigger**: the Understanding page changes, or the project targets 2.5.5 (Enhanced).

## Viewport and safe areas

- Never lock zoom. When the page zooms into a focused field, fix the field's text size, which is
  the cause.
- Size full-height layouts with the dynamic or small viewport units, not the largest one, so
  browser chrome does not cover a bottom-pinned control: dynamic for an app shell that tracks the
  visible area, small for a first screen that must never be cut off.
- Let the page extend under notches and rounded corners only together with safe-area padding on
  fixed headers, bottom bars, toasts and sheets.
- Ask for the right on-screen keyboard: the input type or input mode for numbers, amounts, email
  and phone, and a return-key hint that says what it does.

- **Pointer**: MDN, viewport `<meta>`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/viewport>;
  viewport-percentage lengths,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/length#relative_length_units_based_on_viewport>; "env()",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/env>; "inputmode",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/inputmode>;
  "enterkeyhint",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/enterkeyhint>;
  WCAG 2.2 Understanding 1.4.4 Resize Text,
  <https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html>
- **As of**: 2026-10-11
- **Recheck trigger**: one of these pages changes the units, the viewport keys or input zoom
  behavior it documents.

## Scroll and gestures

- In an app with its own scroll areas, stop the page-level pull-to-refresh and bounce, and keep an
  inner scroll area from chaining its scroll to the page.
- A gesture surface declares which axes it owns, so the browser keeps the rest: a horizontal
  carousel leaves vertical panning to the page; only a surface that handles every direction claims
  them all.
- Prefer the browser's native scroll snapping over a hand-built gesture for a carousel.
- Never block scrolling with a touch-move handler that cancels the event; it also costs frames.
- Drag, swipe and spring behavior: `../animation/gestures.md`.

- **Pointer**: MDN, "overscroll-behavior",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/overscroll-behavior>; "touch-action" (above)
- **As of**: 2026-10-11
- **Recheck trigger**: either page changes its support or behavior notes.

## Verify on hardware

Desktop device emulation does not reliably reproduce sticky hover, the tap highlight, the tap delay,
browser chrome changing the viewport, input zoom, overscroll, safe areas or the on-screen keyboard.
Say which fixes were verified from code and which need a real phone, ideally an older one, with the
keyboard open and once in landscape.
