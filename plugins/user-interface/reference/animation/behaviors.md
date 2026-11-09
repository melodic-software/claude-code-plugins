# Animation behaviors

What each common component's motion does, stated as behavior, not code. The project's design
system and motion tokens override everything here, and the roles and curves named below resolve
from the `animation:` config (`catalog.md`, "Easing" and "Duration"). Build each spec in the
project's own stack after looking up how that stack does it; CSS authoring belongs to
`/user-interface:write-css`. A component the project does not have yet comes from a component
library first (`../component-libraries.md`).

All values assume the defaults from `catalog.md`: `ease-out` to enter or leave and `in` for a
permanent exit (`catalog.md`, "Easing"), exits within `exit_factor` of their entrance,
transform/opacity only, and a `prefers-reduced-motion` path for everything. Adapt the syntax
to the project's stack (CSS, Tailwind, Motion), filling each `{{key}}` placeholder as
[`../values.md`](../values.md) says. A block labeled with a stack (Motion
for React, Tailwind) applies only when the project's files show that stack; otherwise keep the
behavior and look up the stack's own form. A rule that ends in **Audit:** gives the severity
`/user-interface:audit` uses for a finding against it.

Contents: `press`, `popover`, `tooltip`, `modal`, `drawer`, `toast`, `accordion`, `group-entrance`,
`section-entrance`, `exit`, `icon-swap`, `first-paint`, `group-exit`, `view-swap`, `looping`,
`hold-to-confirm`, `tab-indicator`, `scroll-reveal`, `drag-to-dismiss`, `crossfade-mask`.

## Button press: `press`

- Any pressable element scales down slightly on press (`animation.scale.press`) and back on release.
- Role `press`, curve `out`. Feedback starts on press-down, never on release.
- Children scale with it, which is what reads as physical.
- No hover gate: a press is real on touch.
- `animation.scale.press` on `:active`, animated over `animation.duration_ms.press` with an ease-out
  CSS transition so a release mid-press glides back instead of snapping. Much further down than
  `animation.scale.press` starts to look cartoonish. The CSS is the press recipe in
  `/user-interface:write-css`; values are written as [`../values.md`](../values.md) says.
- Not every button needs it: dense or high-frequency UI can skip it. Bake an opt-out into your
  Button component, e.g. a `still` prop.
- What may be skipped is the scale, not the pressed state: a button that skips it still shows
  `:active` some other way, such as a color shift, and a button with no `:active` state at all is
  the `forms` concern's finding.

Illustration (React with Tailwind):

```tsx
function Button({ still = false, className, ...rest }) {
  const classes = cn(
    "transition-[scale] duration-[{{animation.duration_ms.press}}ms] ease-out",
    !still && "active:not-disabled:scale-[{{animation.scale.press}}]",
    className,
  );
  return <button className={classes} {...rest} />;
}
```

## Dropdown, popover, menu, select: `popover`

- Opens from opacity zero and a scale near `animation.scale.enter` to full; closes the reverse way.
- Fade + scale from `animation.scale.enter` over `animation.duration_ms.medium`, ease-out,
  **origin-aware**: scale from the trigger, not the
  center.
- Origin at the trigger, so the panel looks like it came out of what was clicked. A dropdown that
  grows from its own center looks detached from the button that opened it. Anchored surfaces scale
  from the trigger side. Viewport-centered modals with no anchored trigger are the exception and
  stay centered.
- Many headless component libraries expose the trigger position as a CSS variable for this; look
  it up for the project's library. The CSS is the popover recipe in `/user-interface:write-css`.
- Role `medium` (`small` for a small popover), curve `out`.
- A small directional nudge (in from `animation.travel_px.small` above when opening downward) adds
  polish.
  Keyboard navigation *inside* the menu gets no animation: highlight moves instantly.

Worked example, one share menu and two prompts. "the share menu feels janky, make it smoother"
leaves the agent to guess, and it guesses `transform-origin: center; transition: all 400ms
ease-in-out;`: the menu grows out of its own center, detached from the button, over a slow,
symmetric 400ms. "make the share menu origin-aware so it scales in from the trigger, ease-out,
150ms" names the fix, and the agent writes `transform-origin: top left; transition: transform 150ms
var(--ease-out);`: the menu's top-left corner stays pinned under the button and the menu reaches
almost full size within about 65ms on the `out` curve. A fixed origin is right here because no
component library exposes the trigger side; mirror it for right-to-left.

**Audit: Important.** A popover, dropdown, tooltip or context menu with a scale animation and no
`transform-origin` toward its trigger.

## Tooltip: `tooltip`

- The popover behavior, faster: role `small`, a scale closer to full (`animation.scale.enter_small`).
  Fast and subtle: fade + scale from `animation.scale.enter_small` over `animation.duration_ms.small`,
  ease-out, origin-aware.
- The critical detail is the **instant-group behavior**: the first tooltip gets a hover delay and
  animation; while one is open, sibling tooltips appear instantly with no delay and no animation.
- A tooltip delay (`animation.delay_ms.tooltip`) stops tooltips firing on incidental mouse travel.
  Track a shared "warm" flag; clear it `animation.delay_ms.group_warm` after the last tooltip closes.
- Most primitives have this built in, through a provider mounted once around the tooltips; the
  finding is a provider that's missing or mounted per tooltip instead of once. How the project's
  library names it (a skip-delay setting, an instant state or attribute) is a lookup.

- **Pointer**: Radix Primitives, "Tooltip", API reference `Provider` (`skipDelayDuration`) and
  `Content` (the `data-state` values, among them `instant-open`),
  <https://www.radix-ui.com/primitives/docs/components/tooltip#provider>; Base UI, "Popover", API
  reference `Popup` (`data-instant`), <https://base-ui.com/react/components/popover#popup>.
- **As of**: 2026-10-29.
- **Recheck trigger**: either library renames its delay-skip setting or its instant-open state.

**Audit: Suggestion.** Sequential tooltips that each wait for the delay: a tooltip provider that's
missing or mounted per tooltip instead of once.

## Modal and dialog: `modal`

- Opens from opacity zero and a scale near `animation.scale.enter`; stays centered (no trigger origin).
- Enter: fade + slight scale-up from `animation.scale.enter`, within `animation.duration_ms.large`,
  ease-out. Exit: the same fade and scale,
  faster (at most `exit_factor` of the entrance), on `in` as a permanent exit. Overlay fades with **identical duration and easing**:
  they move as one unit.
- Role `large` at most, curve `out`, though most modals feel right well short of the limit.
  Closing a modal is a permanent exit, so it accelerates away on `in` (`catalog.md`, "Easing").
- The backdrop fades on the same timing, so both read as one surface. The CSS is the dialog recipe
  in `/user-interface:write-css`.
- Avoid: sliding modals in from off-screen, scaling from 0, bounce on a dialog (it's an
  interruption, not a toy).

## Drawer and sheet: `drawer`

- Slides in from its edge by its own full size (a percent translate), and leaves through the same
  edge. Slides from its edge with a translate transition (interruptible: users close drawers
  mid-open). `animation.duration_ms.large` ease-out enter, faster exit. Backdrop fades with the same
  timing.
- Role `large`, curve `drawer`, on the way in and on the way out: a drawer leaves but stays nearby.
- Dragging it turns it into a gesture: `drag-to-dismiss` and `gestures.md`. If the drawer is
  draggable (mobile sheet), use a spring so release velocity carries into the animation.

Illustration (CSS):

```css
.drawer {
  transform: translateX(100%);
  transition: transform {{animation.duration_ms.large}}ms cubic-bezier({{animation.easing.drawer}});
}
.drawer[data-open] { transform: translateX(0); }
```

## Toast: `toast`

- Enters from its edge by its own size with a fade, and leaves the way it came. Enters with
  translate + fade from its screen edge (at the bottom edge, up from `animation.travel_px.large`
  below), within `animation.duration_ms.large`, ease-out. Exit: fade + small translate toward the
  edge, faster. A dismissed toast is a permanent
  exit, so it leaves on `in`.
- Motion that retargets from the current value, never a restarting keyframe, because toasts arrive
  in bursts.
- When stacking, move existing toasts with `transform` (never re-layout), same easing, and use a
  spring if toasts are swipeable-to-dismiss.
- A toast may run slightly slower with a gentler ease than other interface motion, within `large`
  (`catalog.md`, "Personality").
- When toasts stack and the list reflows, the opacity change has to work with the height change;
  tune by feel and check again later.

## Accordion and collapse: `accordion`

- Expands to the measured content height, never an unmeasured automatic height: the technique is in
  `../types/web.md` ("Expand to content height").
- Keep it short (`small` to `medium`): it costs layout on every frame, so a long duration is
  expensive as well as slow.
- Expose the open or closed state on the trigger, and make closed content unreachable.

## Group entrance: `group-entrance`

- Items of a list or grid the user sees occasionally fade and rise a few pixels into place, at the
  stagger interval (`catalog.md`, "Stagger").
- Never on a list the user scrolls past all day, and never blocking interaction while it plays.

## Section entrance, split then stagger: `section-entrance`

For page/section entrances, never move one monolithic wrapper. Carve the content into meaningful
pieces (heading, supporting copy, call to action) and offset each by `animation.stagger_ms.section`.
The softest layered enter pairs a fade with a short upward travel (`animation.travel_px.medium`)
while a light blur of `animation.blur_px.soften` melts away. Hero headlines can go finer-grained:
per-word offsets of `animation.stagger_ms.word`.

This offset is for a few large pieces of one section; a list's items take the shorter stagger
interval in `catalog.md`. On a marketing page, an entrance that replays on every visit is the
`marketing-pages` concern.

Illustration (Motion for React):

```tsx
const list = { show: { transition: { staggerChildren: 0.09 } } };
const piece = {
  hide: { opacity: 0, filter: "blur(2px)", y: 8 },
  show: { opacity: 1, filter: "blur(0px)", y: 0 },
};

<motion.section variants={list} initial="hide" animate="show">
  {sections.map((s) => (
    <motion.div key={s.id} variants={piece}>{s.content}</motion.div>
  ))}
</motion.section>
```

Illustration (CSS; set `--n` per child, 0, 1, 2 and so on, in the markup):

```css
.entrance > * {
  opacity: 0;
  translate: 0 8px;
  filter: blur(2px);
  animation: rise-in 350ms ease-out forwards;
  animation-delay: calc(var(--n, 0) * 90ms);
}
@keyframes rise-in {
  to { opacity: 1; translate: 0 0; filter: none; }
}
```

## Exit: `exit`

An exit deserves less emphasis than an enter, because by the time something leaves, attention has
already moved elsewhere.

- Nudge a fixed few pixels (`animation.travel_px.medium` or so), never the element's own height. The
  direction follows the path it entered by, so the sign depends on the edge (`catalog.md`,
  "Physicality").
- A hint of direction tells the eye where the thing went; a pure fade loses that.
- Run it shorter: at most `animation.duration_ms.exit_factor` of an entrance within
  `animation.duration_ms.large`.
- A permanent exit accelerates away on `in`; a toggled one leaves on the curve it entered with
  (`catalog.md`, "Easing").
- Don't cut straight to `display: none`: instant disappearance severs spatial context.

Reserve a full off-screen slide (`x: "-100%"`) for moments where the destination itself is the
information: a swiped-away list card, a closing drawer.

Illustration (Motion for React; a permanent exit on the `in` curve):

```tsx
<motion.div exit={{ opacity: 0, y: -{{animation.travel_px.medium}}, filter: "blur({{animation.blur_px.soften}}px)",
  transition: { duration: {{animation.duration_ms.medium}} * {{animation.duration_ms.exit_factor}} / 1000,
    ease: [{{animation.easing.in}}] } }} />
```

## Contextual icon swap: `icon-swap`

Icons that change with state (play → pause, like → liked, copy → check) deserve a real cross-fade,
not a visibility toggle. The recipe is a deep scale-down, a fade, a slight blur, and a
bounce-free spring.

- `scale`: from `animation.scale.swap_start` to full size: a deep scale-down reads as a swap; a
  timid one (0.8, 0.9) reads as a glitch
- `opacity`: fades `0` → `1` alongside the scale
- `filter`: a blur of `animation.blur_px.soften` sharpening to none
- spring: duration `animation.spring.duration_s.small`, bounce `animation.spring.bounce.default`:
  icons aren't toys

Illustration (Motion for React):

```tsx
<AnimatePresence mode="popLayout" initial={false}>
  <motion.span key={copied ? "check" : "copy"}
    initial={{ scale: {{animation.scale.swap_start}}, opacity: 0, filter: "blur({{animation.blur_px.soften}}px)" }}
    animate={{ scale: 1, opacity: 1, filter: "blur(0px)" }}
    exit={{ scale: {{animation.scale.swap_start}}, opacity: 0, filter: "blur({{animation.blur_px.soften}}px)" }}
    transition={{ type: "spring", duration: {{animation.spring.duration_s.small}}, bounce: {{animation.spring.bounce.default}} }}>
    {copied ? <CheckIcon /> : <CopyIcon />}
  </motion.span>
</AnimatePresence>
```

Without Motion: render **both icons at once**, layering one absolutely over the other, and swap
classes to cross-fade: nothing ever unmounts, so the reverse direction animates just as well. A firm
ease-out such as `animation.easing.spring_stand_in` over `animation.spring.duration_s.small` stands
in for the spring. The icon left
in normal flow determines the component's size.

Good candidates: actions revealed on hover, state toggles, icons inside contextual toolbars, loading
→ success indicators. Poor candidates: permanent navigation icons, purely decorative marks, anything
always on screen, text labels.

## First paint: `first-paint`

If a component is showing its resting state when the page first paints, it must not play an
entrance: reserve enter animations for state changes the user causes afterward (`catalog.md`, "Page
load"). In Motion, `initial={false}` on `AnimatePresence` handles this for icon swaps, toggles,
tabs, and segmented controls.

Exception: components whose whole point is a first-run entrance (staggered hero, loading state) rely
on their `initial` prop: there, `initial={false}` would wipe out the whole entrance. After applying
it, hard-refresh the page and confirm nothing that should animate went static.

## Group exit: `group-exit`

When an exiting element sits in a group (list items, toasts, tags), let siblings slide into place
while the exit plays, instead of waiting for it. In Motion for React that is `mode="popLayout"` on
`AnimatePresence`. Without a library, pin the leaving element at its current offset with absolute
positioning inside a positioned parent before its exit starts, so it no longer holds its slot; the
siblings then reflow or animate into the gap (`catalog.md`, "Choreography").

- **Pointer**: Motion, "AnimatePresence", props `initial` and `mode` (`popLayout`),
  <https://motion.dev/docs/react-animate-presence#initial>,
  <https://motion.dev/docs/react-animate-presence#poplayout>.
- **As of**: 2026-10-29.
- **Recheck trigger**: Motion renames `initial={false}` or `popLayout`, or changes what either does.

## View swap in one container: `view-swap`

Steps of a flow, tabs of a panel, or states of one morphing surface replace each other inside the
same container (`catalog.md`, "Choreography").

- The outgoing view fades out as the incoming one fades in (a crossfade), not one after the
  other. The container's resize and the swapped content belong to one object: one duration role
  and one easing family, with the content on a lighter curve of that family keeping the change
  readable.
- The content fade lengthens with the resize distance, clamped within the role: a tiny
  resize with a full-length fade reads as a flicker.
- Direction follows the step: forward and back slide opposite ways. A leaving view reads its
  direction when its exit starts, so the newest direction has to reach it; how a stack passes it is
  a run-time lookup (in Motion for React, the `custom` prop).
- Small containers or near-identical views take a crossfade with a few pixels of shift instead of a
  full slide.
- Two dense views in a container resizing on both axes sequence instead: the old view
  leaves before the new one enters, unless a duplicate of the leaving view is rendered on top to
  fade out on its own path.
- Each view carries a stable, unique key, which is how the stack detects a departure; when an
  exit never plays, check the key before anything else.

- **Pointer**: Motion, "AnimatePresence", props `mode` and `custom`,
  <https://motion.dev/docs/react-animate-presence#mode>,
  <https://motion.dev/docs/react-animate-presence#custom>.
- **As of**: 2026-11-07.
- **Recheck trigger**: Motion renames `mode` or `custom`, or changes how an exiting child reads
  `custom`.

## Looping animation: `looping`

A loop (a spinner, a shimmer, a marquee) is constant motion, so it runs `linear`
(`catalog.md`, "Easing"), and under reduced motion it pauses on a representative frame
(`catalog.md`, "Reduced motion"). Pausing a loop when it is off-screen or in a background tab is
the `web-performance` concern.

## Hold to confirm: `hold-to-confirm`

- For a destructive action where a single click is too easy.
- While held, a fill sweeps across the control slowly and linearly (it is a progress indicator,
  so it does not ease); the action fires when the fill completes.
- On early release, the fill retracts quickly with `out`. The control also takes press feedback.

## Tab indicator: `tab-indicator`

- The active highlight slides to the selected tab with `in_out`, role `medium`.
- When the active tab also changes text and background color, timing separate color transitions
  never quite lands. Instead, render an active-styled copy of the tab row and clip it to the
  selected tab, animating the clip: text and background change together because they are one
  element being revealed.

## Scroll reveal: `scroll-reveal`

- Marketing and editorial surfaces only, never functional interface a user visits daily.
- Content is uncovered (a clip or a fade-and-rise) once, when it first enters the viewport, using
  the platform's visibility observer. Re-animating on every scroll past fights the reader.

## Drag to dismiss: `drag-to-dismiss`

- The element follows the pointer 1:1 from where it was grabbed.
- It dismisses when dragged past `animation.gesture.distance_threshold` (a fraction of its travel,
  0 to 1) or released fast enough, so a flick is enough: faster than `animation.gesture.velocity_threshold` (px/ms) for a small element such as a
  toast; a drawer or sheet needs a higher threshold (`gestures.md`, "Drag details"). For
  drag-to-dismiss, compare velocity (`swipeAmount / timeTaken`) with
  `animation.gesture.velocity_threshold`, not only distance.
- Otherwise it springs back fast with the release velocity; a slow return reads as the interface
  disagreeing with the user.
- Pointer capture, multi-touch protection, resistance past the edge: `gestures.md`.

## Crossfade mask: `crossfade-mask`

- When two states visibly overlap during a crossfade and tuning easing and duration does not fix
  it, add a small blur and a slight opacity dip during the transition so the eye reads one change.
  Add a subtle blur of `animation.blur_px.soften` during the transition to bridge the states, kept
  well under `animation.blur_max_px`.
- Keep the blur small; its cost grows with radius and area (`performance.md`).
