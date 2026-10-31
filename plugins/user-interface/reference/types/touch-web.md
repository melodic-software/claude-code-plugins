# Touch web: web interfaces used by finger

Scope: web pages and web apps reached on touch screens or other coarse, non-hovering pointers.
`principles.md` applies first and `web.md` is the base; this file adds only what touch changes.
The project's own conventions and its stack's documentation override it. Native and cross-platform
app stacks are `app.md`'s.

Read this when a web app is built for or reviewed on a phone, when something works in a desktop
browser but feels wrong on a phone, or when building a PWA, a bottom sheet, a carousel, a
full-screen layout or any touch interaction. The rules are about the platform layer (viewport,
touch, scroll, safe areas, the keyboard, the browser chrome), where a handful of lines decide
whether the app feels installed or embedded.

The CSS that implements these rules is in `/user-interface:write-css`: its `interaction.md`,
`scroll-and-viewport.md` and `foundations.md` recipes, named by id beside the rule that uses them.
The viewport meta tag is in `web.md`, "Document head".

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Other concerns own their lines, one home each: a button's missing `:active` state, autofocus on
touch, the input `type` and `autocomplete` tokens and dead zones between a checkbox and its label
are the `forms` concern; press scale and press timing are the `motion` concern; control labels that
select on a double click are the `typography` concern; a sticky header's height cap is the
`web-layout` concern; `theme-color` per scheme is the `theming` concern; inline autoplaying video is
the `web-performance` concern; keyboard access, focus and screen readers are the `accessibility`
concern.

Contents: opening rules, symptoms, 1 hover and press, 2 targets, 3 long press, 4 inputs and the
keyboard, 5 viewport, safe areas and anchors, 6 scroll and gestures, 7 verify on hardware.

## Opening rules

1. **Every fix ships with the reason.** Each rule below has a why. Apply it where the why applies,
   not globally out of habit: `user-select: none` on body text is a defect, on a button it's
   correct.
2. **Media queries over device sniffing.** `(hover: hover)`, `(pointer: fine)`, `env()`, `dvh`. The
   platform tells you what it can do. Never branch on user agent strings or screen width to guess at
   touch.
3. **Touch and mouse are not exclusive.** iPads with trackpads, laptops with touchscreens, phones
   with a mouse. Write for both at once and gate by capability, not by device.

Browser behavior on touch changes between releases, so each rule below names the behavior and the
pointer says where to read it live.

**Audit: Important.** A touch, hover or device check that reads the user agent string or the
screen width.

## Symptoms

Start here. Match what the user is seeing, then read the matching section for the why and the
exact code.

| Problem | Solution | Section |
| --- | --- | --- |
| Hover state stuck after tap | Wrap in `@media (hover: hover) and (pointer: fine)` | 1 |
| Gray/blue flash on tap | Kill `-webkit-tap-highlight-color` | 1 |
| Layout has the wrong height | `100dvh` (app) or `100svh` (hero) | 5 |
| Page zooms into input | Input font size 16px at the minimum | 4 |
| Tap feels laggy | Feedback on pointer-down + `touch-action: manipulation` | 1 |
| Taps miss small buttons | 44px hit area through a pseudo-element | 2 |
| Pull-to-refresh hijacks scroll | `overscroll-behavior-y: none` on `html, body` | 6 |
| Content stops at the notch | `viewport-fit=cover` + `env(safe-area-inset-*)` | 5 |
| Keyboard covers the input or the CTA | `interactive-widget=resizes-content` + `dvh` | 4 |
| Keyboard opens by itself | No `autoFocus` on coarse pointers | the `forms` concern |
| Long-press selects button text | `user-select: none` on controls only | 3 |
| Carousel scrolls vertically | `touch-action: pan-y` on the gesture surface | 6 |
| Video opens fullscreen or won't autoplay | `muted` + `playsinline` | the `web-performance` concern |
| Status bar color doesn't match | `theme-color` per color scheme | the `theming` concern |
| Anchor links land under the sticky header | `scroll-margin-top` | 5 |
| Right in Chrome, wrong on phone | Test on real hardware | 7 |

## 1. Hover and press

Touch has no hover, so browsers fake one: the first tap on an element applies `:hover` and leaves
it there until the user taps somewhere else. A button that scales up on hover stays scaled up after
being tapped. Gate every hover style behind a capability query.

Both conditions matter. `(hover: hover)` means the primary input can hover. `(pointer: fine)` means
it's precise, like a mouse, which rules out the odd Android device that claims hover support. A
drawing stylus reports a fine pointer too: a basic one that cannot hover is ruled out by
`(hover: hover)`, and one that hovers keeps the hover styles. Recipe:
`hover-styles-only-where-hover-exists`, which also covers a framework's hover variant.

- **Pointer**: Media Queries Level 4, `pointer` and `hover`, the examples for each value,
  <https://www.w3.org/TR/mediaqueries-4/#pointer> and <https://www.w3.org/TR/mediaqueries-4/#hover>;
  MDN, "hover" media feature, <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/hover#syntax>
- **As of**: 2026-10-29
- **Recheck trigger**: either page changes which devices match `fine` or `hover`.

Hunt for: `:hover` rules outside `@media (hover: hover)`.

**Audit: Important.** An ungated `:hover` rule, so a tap leaves the element hovered until the next
tap elsewhere.

**Hover enhances, never enables.** A control that only appears on hover is unreachable on touch and
by keyboard. Feedback (errors, confirmations, status) is visible without hover. Never rely on hover
for the UI to function: hover reveals and embellishes, it must not be the only way to reach an
action. A row action that only appears on hover doesn't exist on a phone. Render it always at lower
emphasis, or reveal it on `:focus-within` too.

Hunt for: `opacity: 0` → `:hover { opacity: 1 }` and `group-hover:opacity-100` on containers
holding buttons; feedback shown only in a hover tooltip.

**Audit: Important.** An action, or feedback, reachable only through hover: a control that is not
rendered, or is invisible, until the pointer hovers its container.

**Tap highlight.** iOS Safari and Android Chrome paint a translucent highlight over any tapped
element that has a click handler. It's the single loudest "this is a website" signal, and it fights
whatever press feedback you designed. Set it once, globally. Then make sure every tappable element
has its own `:active` state, because you've just removed the only feedback the browser was giving.
Recipe: `the-reset`. With the tap highlight gone, a control without an `:active` state gives no
touch feedback at all; that missing state is graded under the `forms` concern.

- **Pointer**: MDN, `-webkit-tap-highlight-color`,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/-webkit-tap-highlight-color#browser_compatibility>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes which browsers paint the highlight.

**Audit: Important.** The browser's tap highlight left on in an app that styles its own press
states.

**Taps feel instant.** Two separate causes stack here. Browsers wait after a tap to see whether a
second tap is coming, because double-tap zooms. Modern browsers skip the wait when the viewport is
`width=device-width`, but not in every case.
`touch-action: manipulation` tells the browser this element never double-tap-zooms, so it fires
`click` immediately. Native buttons respond the instant
your finger lands. A web button that only changes on `click` responds when your finger *leaves*,
which reads as lag even at 0ms. Style `:active`, and if you need JavaScript for the visual, listen
to `pointerdown`, not `click`. The *feedback* fires on press; the *action* still fires on `click`,
so the user can cancel by sliding their finger off. Recipes: `the-reset` (`touch-action`),
`press-feedback`.

Which elements still wait, and for how long, changes between browser releases; the pointer is
where to read it.

- **Pointer**: MDN, `touch-action`, the `manipulation` value,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action#manipulation>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes what `manipulation` turns off.

Hunt for: tappable elements with no `touch-action`; a pressed look set from a `click` listener.

**Audit: Important.** Buttons, links and inputs with no `touch-action: manipulation`, or press
feedback driven by `click` instead of `:active` or `pointerdown`.

## 2. Targets

A finger pad covers about 44px. A 24px icon button with a 24px hit area gets mistapped, and the
user blames themselves, then the app. The visual can stay small; the hit area can't. Interactive
elements need `44×44px` hit areas for touch/mobile, at least `40×40px` on desktop. Extend small
controls with a pseudo-element, or give the control a minimum width and height. Recipe:
`hit-area-larger-than-the-visual`.

Two hit areas must never overlap. If an extended area collides with a neighbor, shrink both to the
largest non-colliding size, or add spacing.

The 44px is the touch target. WCAG 2.2's 2.5.8 Target Size (Minimum) sets a smaller conformance
floor with a spacing exception; a target under that floor is also an accessibility failure.

- **Pointer**: WCAG 2.2 Understanding 2.5.8 Target Size (Minimum), "Intent",
  <https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html#intent>
- **As of**: 2026-10-29
- **Recheck trigger**: the Understanding page changes the minimum or the spacing exception, or the
  project targets 2.5.5 (Enhanced).

Hunt for: icon buttons with `width` / `height` under 44px (`size-6`, `h-8 w-8`) and no padding or
pseudo-element extending the hit area; toast dismiss buttons; table row actions; pagination.

**Audit: Important.** A touch target under 44px with nothing extending its hit area (a 24px icon
with a 24px hit area), or two extended hit areas that overlap.

## 3. Long press

Hold a finger on a web button and iOS selects its label, or pops the copy/share callout on a link.
Native controls never do that. Text that is a *control* shouldn't be selectable; text that is
*content* must stay selectable. Turn off the long-press callout on links and images used as
controls. Never put `user-select: none` on `body`. Users copy addresses, error messages, and order
numbers; that is content. Recipe: `the-reset`.

Hunt for: `user-select: none` / `select-none` on `body`, `*`, or a layout wrapper.

**Audit: Important.** `user-select: none` on `body`, `*` or a layout wrapper, so content cannot be
selected or copied.

## 4. Inputs and the keyboard

**Inputs are 16px on touch.** iOS Safari zooms the page when focus lands on an input whose font
size is under 16px, and it does not zoom back out on blur. The user is left looking at a cropped,
drifted layout. This is the reason people reach for `maximum-scale=1`, which is the wrong fix
(section 5).

If the design calls for smaller text, keep the computed font-size at 16px on touch devices and
scale visually some other way, never below 16px. Scale it down only where a fine pointer is
primary. In Tailwind: `text-base pointer-fine:text-sm`. `text-sm` alone on an input is the bug.
A width breakpoint such as `md:text-sm` is the screen-width guess opening rule 2 rules out: a
touch tablet wider than the breakpoint gets the small size and zooms. Recipe: `the-reset`.

- **Pointer**: Tailwind CSS, "Hover, focus, and other states", "pointer and any-pointer",
  <https://tailwindcss.com/docs/hover-focus-and-other-states#pointer-and-any-pointer>
- **As of**: 2026-10-29
- **Recheck trigger**: Tailwind renames the pointer variants or changes the query they compile to,
  or the project's installed version predates them.

The threshold is the computed size: a `1rem` input still zooms when the root font size is set below
16px. No first-party browser page documents the threshold; confirm it on a phone (section 7).

Hunt for: `font-size` under 16px on `input`, `textarea`, `select`; `text-sm` / `text-xs` on them or
on a shared `Input` component, alone or behind a width breakpoint (`md:text-sm`); a contenteditable
editor with small text.

**Audit: Blocking.** Text in an input, textarea, select or editable field under 16px on touch, so
the page zooms in on focus.

**Ask for the right keyboard.** While you're in the inputs, set the keyboard: `inputmode="numeric"`
for codes, `inputmode="decimal"` for amounts, `type="email"` and `type="tel"` for their fields,
`autocapitalize="none"` and `autocorrect="off"` on usernames and codes,
`autocomplete="one-time-code"` on verification inputs so iOS offers the SMS code,
`enterkeyhint="send"` / `"search"` / `"done"` so the return key says what it does. The `type` and
`autocomplete` attributes are the `forms` concern's rule.

- **Pointer**: MDN, "inputmode", "Value",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/inputmode#value>;
  "enterkeyhint", "Value",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/enterkeyhint#value>
- **As of**: 2026-10-29
- **Recheck trigger**: either page adds, renames or drops a value.

**Audit: Suggestion.** A code, amount or search field with no `inputmode` or `enterkeyhint`, or a
username or code field that autocapitalizes or autocorrects.

**The keyboard doesn't cover the input.** The software keyboard takes roughly half the screen, and
browsers disagree about what happens to the layout. Where the keyboard shrinks only the *visual*
viewport, the browser scrolls the focused input into view. Where it overlays the page, a
bottom-pinned composer or a fixed CTA ends up underneath it. Which browser does which by default is
the pointer's to say. `interactive-widget=resizes-content` in the viewport meta tag makes the
keyboard shrink the layout viewport, so `100dvh` and bottom-pinned inputs move above it. With that
in place a chat composer at the bottom of a `100dvh` flex column stays above the keyboard with no
JavaScript.
The tag is in `web.md`, "Document head".

- **Pointer**: MDN, viewport `<meta>`, "interactive-widget" and "The effect of interactive UI
  widgets",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/viewport#interactive-widget>
  and
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/viewport#the_effect_of_interactive_ui_widgets>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes the default value or what `resizes-content` resizes.

Hunt for: chat composers, comment boxes, and sticky form footers pinned with `position: fixed;
bottom: 0`; the viewport meta tag missing `interactive-widget`.

**Audit: Important.** A bottom-pinned composer, comment box or form footer in a page whose viewport
meta tag has no `interactive-widget=resizes-content`.

**Fixed bottom CTAs don't cover the last field.** A fixed bottom button sits over the final form
field and over the home indicator. Pad the scroll container by the CTA's height plus the safe area,
so the final input can scroll clear of it, and pad the CTA itself with
`env(safe-area-inset-bottom)` (section 5). The same goes for cookie banners and chat widgets: check
what they sit on top of at 375px wide. Recipe: `content-clear-of-the-notch`.

**Audit: Important.** A fixed bottom CTA, cookie banner or chat widget that covers the last form
field or the home indicator at 375px wide.

## 5. Viewport, safe areas and anchors

**Never disable zoom.** `user-scalable=no` and `maximum-scale=1` are accessibility failures. Some
browsers ignore them for pinch zoom while others obey and lock low-vision users out. Fix the
input font size instead, which is what was causing the zoom (section 4).

- **Pointer**: MDN, viewport `<meta>`, "user-scalable",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/viewport#user-scalable>;
  WCAG 2.2 Understanding 1.4.4 Resize Text, "Intent",
  <https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html#intent>
- **As of**: 2026-10-29
- **Recheck trigger**: the MDN page changes which browsers ignore the zoom keys, or 1.4.4 changes.

Hunt for: `user-scalable`, `maximum-scale`, `maximumScale`, `userScalable` in the viewport meta tag
or the Next.js `viewport` export.

**Audit: Blocking.** A viewport meta tag or framework viewport setting with `user-scalable=no` or
`maximum-scale=1`.

**Viewport height is `dvh` or `svh`, not `vh`.** `100vh` on mobile is the *largest* viewport, the
height with the browser chrome collapsed. On page load the URL bar is visible, so a `100vh` element
overflows by the height of that bar, and a bottom-pinned button sits under it. `dvh` resizes as the
URL bar collapses, which is right for an app shell but causes layout shifts on marketing content
mid-scroll. `svh` is stable and never overflows, which is right for a hero. `lvh` is the old `vh`
and you almost never want it. Desktop-only admin tools can keep `vh`; note it and move on. Recipe:
`full-height-that-browser-chrome-cannot-cover`.

- **Pointer**: MDN, `<length>`, "Relative length units based on viewport",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/length#relative_length_units_based_on_viewport>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes how the small, large or dynamic units are defined.

Hunt for: `100vh`, `h-screen`, `min-h-screen`, `max-h-screen`, `calc(100vh - …)`.

**Audit: Important.** `100vh` (or `h-screen`) on an app shell or bottom-pinned UI, or `100dvh` on a
marketing hero, outside a desktop-only tool.

**Safe areas are respected.** By default the browser letterboxes your page inside the safe area,
leaving the notch, Dynamic Island, and home-indicator zones the body's background color. A native
app paints edge to edge and pads its *content* away from those zones. `viewport-fit=cover` lets the
page under the notch; `env(safe-area-inset-*)` gives you the insets to pad back out. Without the
meta tag the `env()` values are all `0px`. Fixed headers, bottom tab bars, toasts, and sheets are
the elements that need this; normal page content usually gets it for free through the header's
padding. Landscape puts the notch on the side. Recipe: `content-clear-of-the-notch`.

- **Pointer**: MDN, `env()`, "Syntax" (the safe-area inset names),
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/env#syntax>; viewport `<meta>`, "viewport-fit",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/viewport#viewport-fit>
- **As of**: 2026-10-29
- **Recheck trigger**: either page renames an inset or changes what `cover` does.

Hunt for: `position: fixed` / `sticky` elements at `top: 0` or `bottom: 0` with no
`env(safe-area-inset-*)`; the toaster's offset; `env()` used without the meta tag.

**Audit: Important.** A fixed header, bottom bar, toast or sheet with no safe-area padding, or
`env(safe-area-inset-*)` in a page without `viewport-fit=cover`.

**Anchor links land clear of the sticky header.** An in-page link scrolls its target to the very
top of the viewport, which is exactly where the sticky header sits. On a phone the header is a
bigger share of the screen, so the heading the user asked for is fully hidden. Give anchored
elements `scroll-margin-top` so in-page links don't land under it; read the header's height from the
code. The recipe writes the margin as the logical `scroll-margin-block-start`. Recipe:
`anchor-targets-that-clear-a-sticky-header`.

**Audit: Important.** In-page links on a page with a sticky header and no scroll margin or scroll
padding, so the target lands under the header.

## 6. Scroll and gestures

**Scroll doesn't chain or pull-to-refresh in app UI.** Scrolling past the top of the page triggers
pull-to-refresh on Android Chrome and the whole-page rubber band on iOS. Fine on a document. Wrong
in an app with its own scroll containers, a drawer the user drags down, or a canvas. `overscroll-behavior-y:
none` on the root, `contain` on inner scrollers. `contain` keeps the container's own bounce (which feels native)
but stops the page behind it from moving. Never reach for a `touchmove` + `preventDefault()`
listener for this. It blocks scrolling entirely and makes the listener non-passive, which costs
frames. Recipe: `no-rubber-band-bounce-on-desktop`, whose app-shell rule keeps `none` on phones
and sets the vertical longhand on the root, since `none` on the horizontal axis can also turn off
swipe to go back.

When a modal or sheet is open, the page behind it must not scroll. Use a dialog primitive that locks
scroll rather than `overflow: hidden` on `body`, which iOS Safari has a long history of ignoring for
touch scrolling. Which primitive, and where its documentation lives, is
`../component-libraries.md`'s choice; read its dialog page for how it locks scroll.

- **Pointer**: MDN, `overscroll-behavior`, "Values",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/overscroll-behavior#values>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes what `none` or `contain` turns off.

Hunt for: `preventDefault` inside `touchmove`; inner scroll containers (`overflow-y: auto`) without
`overscroll-behavior`; modals whose background scrolls when the modal content hits its end;
`overflow: hidden` on `body` as the only scroll lock.

**Audit: Important.** In app UI, a page that chains scroll or pulls to refresh from an inner
scroller, a `touchmove` listener that calls `preventDefault()` to stop it, or a modal whose only
scroll lock is `overflow: hidden` on `body`.

**Gesture surfaces declare their axis.** A horizontal swipe on a carousel is ambiguous to the
browser. It doesn't know whether you're scrolling the page or the track, so it guesses, and the
guess is often the page jittering up while the carousel moves. Tell it which axes the element owns.
The values name what the *browser* may still do. `pan-y` on a horizontal carousel means "browser,
you keep vertical panning; I'm handling horizontal". `none` means the element handles everything.
Use it only on elements that really do, or the user won't be able to scroll past them. For custom
components that implement their own pan/zoom gestures (canvases, sliders, drawing surfaces), disable
native gestures entirely so they don't fight yours. Recipe:
`gesture-surface-that-claims-only-its-axis`.

If the carousel is native scroll rather than a JS gesture, prefer `scroll-snap-type: x mandatory` on
the track and `scroll-snap-align: start` on slides. The browser's own physics beat a hand-rolled
spring, and `touch-action` becomes unnecessary. Recipe: `carousel-on-native-scroll`. Drag, swipe
and spring behavior are the `motion` concern (`../animation/gestures.md`).

- **Pointer**: MDN, `touch-action`, "Values",
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action#values>
- **As of**: 2026-10-29
- **Recheck trigger**: the page changes what a pan value leaves to the browser.

Hunt for: carousels, sliders, drag-to-dismiss sheets, sortable lists, and canvases with no
`touch-action`.

**Audit: Important.** A carousel, slider, sheet, sortable list or canvas with no `touch-action`, or
`touch-action: none` on something the user needs to scroll past.

**Nothing scrolls sideways.** One element wider than the viewport makes the whole page pan
horizontally on a phone, and every screen feels loose. The usual causes: a long URL or email in a
card, a `<pre>` block, a wide table, a fixed-width element, `100vw` on a page that has a vertical
scrollbar. Fix the element that overflows. `overflow-x: hidden` on `body` hides the symptom and
breaks `position: sticky`. Recipe: `nothing-wider-than-the-viewport`; long text in a card is the
`layout-stability` concern's recipe `long-text-that-wraps-truncates-or-clamps`.

Hunt for: `width: 100vw` / `w-screen`; fixed pixel widths over ~340px; `<table>` and `<pre>` with no
scrolling wrapper; user-generated strings with no `overflow-wrap`.

**Audit: Important.** A page that scrolls sideways at 375px wide, or `overflow-x: hidden` on `body`
covering an element that overflows.

**Fades on scrollers.** A fade on content that scrolls is allowed only on the four terms of recipe
`styles-that-apply-only-when-a-scroller-overflows`, which holds the rule and its code.

Hunt for: `mask-image` or a gradient overlay on an element with `overflow: auto` or `scroll`.

**Audit: Important.** A fade over a scrolling list that breaks one of the recipe's four terms:
static, left on at an edge with nothing beyond it, the only sign the list scrolls, or fading a focus
ring.

**The page scrollbar stays native.** Styled scrollbars belong only inside small scrollers, such as
a code block; recipe `scrollbars-styled-only-inside-small-scrollers` holds the rule and its code.

Hunt for: `::-webkit-scrollbar` with no element before it, or on `html` or `body`;
`scrollbar-width: none` on `html` or `body`.

**Audit: Suggestion.** A custom scrollbar on the page itself rather than inside a small scroller.

## 7. Verify on hardware

Nothing above reproduces in device emulation. Sticky hover, the tap highlight, the URL bar's effect
on `vh`, input zoom, the click delay, overscroll, safe areas, the software keyboard: every one is a
real-hardware behavior.

- Connect the phone over USB, run the dev server on `0.0.0.0`, open it by the machine's LAN IP.
- iOS: Safari, Develop, the device. Android: `chrome://inspect`.
- Test on a phone that's a few years old, not the newest one on your desk. Test with the keyboard
  open. Test in landscape once.
- Test as an installed PWA if that's a target; standalone mode changes viewport, safe areas, and
  status bar behavior.

The Xcode Simulator is a step up from emulation but still misses touch feel. Real hardware is the
bar. Say which fixes were verified from code and which need a real phone. Report this as a device
check, never as verified.

- **Pointer**: Chrome DevTools, "Remote debug Android devices", "Debug content on your Android
  device from your development machine",
  <https://developer.chrome.com/docs/devtools/remote-debugging#debug>; Apple Developer
  Documentation, Safari developer tools, "Inspecting iOS and iPadOS" (a single-topic page with no
  section anchor found), <https://developer.apple.com/documentation/safari-developer-tools/inspecting-ios>
- **As of**: 2026-10-29
- **Recheck trigger**: either page moves or changes how a device connects.
