# The switcher

The switcher's appearance is **not a design decision**: it is the bundled
[assets/variant-switcher.html](../assets/variant-switcher.html). On the HTML mockup, inline that
file whole; the only things that change per run are the variant names and count, which the asset
reads from the page. It stays identical across every project so it always reads as harness chrome,
never as part of the design being judged. Do not restyle it with the project's tokens, fonts, or
colors.

It is a floating dark pill, bottom center. Dark glass works on top of any page, light or dark,
which is why it is not theme-aware.

## Rules

- **Verbatim.** The asset's markup, styles and wiring are the spec. No project fonts, no brand
  colors, no theme switching, no extra shadows or borders.
- **The highlight slides; the variant swap stays instant.** The active item's highlight animates
  between buttons (250ms, strong ease-out) as spatial feedback on the switcher itself, but the
  variant being previewed still switches with no transition: flipping happens a hundred times a
  session.
- **One allowed modification:** if a variant occupies the bottom center of the screen (a toast
  stack, a bottom sheet, a dock), set `data-position="top"` so the switcher never covers the work.
  Nothing else about it may move or change.
- **Replay is conditional.** The replay button, and the speed button beside it, render only when at
  least one variant has an entrance or state animation worth re-triggering; a static comparison
  gets a shorter pill. The asset detects CSS animations and transitions; mark a variant
  `data-motion` when a script drives its motion.
- **The worst-content toggle is conditional too.** It renders only when the page carries both
  content sets, described below.

## Behavior contract

The bundled asset's contract; the real-stack switcher follows the table in [real-stack.md](real-stack.md) instead:

- Number keys `1` to `N` and the left and right arrow keys switch variants, wrapping around; `R`
  replays, `W` flips demo and worst content, `S` steps the motion speed. Ignore key events when
  focus is in an input, textarea, select, or contenteditable, or when a modifier is held.
- The state button and the up and down arrow keys step through the current variant's
  `data-screen-state` blocks, wrapping around and keeping the chosen state across a variant switch;
  with fewer than two states the arrows scroll the page as usual.
- Clicking an item switches to it; exactly one item carries `aria-current="true"` at all times,
  and the highlight slides to it. The highlight takes its initial position without animating
  (`data-ready` is added after first paint).
- What it shows lives in memory, since `file://` has no routing.
- Switching re-mounts the variant (so entrance animations re-run); the replay key re-mounts without
  switching.

A real-stack switcher that adopts any of this behavior expresses it idiomatically: state instead
of toggling `hidden`, a keyed re-mount instead of replacing the element, refs and a layout effect
for the highlight measurement.

## Worst content

If the content is dynamic, based on user data, test every variant with the skill's step 2 worst
case. It's much better to find out that something might break during prototyping than in
production.

Give the page two synthetic content sets, the ordinary one marked `data-content-set="demo"` and the
breaking one `data-content-set="worst"`, and every variant renders both; the switcher's Demo/Worst
button (or `W`) shows one set at a time across all variants, so the data stays the control
variable. A variant that renders content from script reads
`document.documentElement.dataset.vsContent`, which is `demo` or `worst`. Each set is defined once,
and every state (empty, error) derives from the set shown, never from a copy. On the real stack, drive
the real page to its worst case instead.

## Slow motion

Running animations in slow motion lets you see things you would not notice at full speed. That
helps most when something feels off but you can't quite put your finger on it, such as content
that jumps when an animation is interrupted mid-flight.

The speed button (or `S`) steps every running animation through the
[control panel's](../../../context/control-panel.md) speed multipliers, and keeps new animations at
that speed until it returns to 1x.
It slows CSS animations, CSS transitions and Web Animations; motion a script drives frame by frame
(`requestAnimationFrame`, timers) keeps its speed, so say so in the handover when a variant moves
that way. When the [control panel](../../../context/control-panel.md) carries its own speed
multiplier, leave the switcher's at 1x so the two do not compound.
