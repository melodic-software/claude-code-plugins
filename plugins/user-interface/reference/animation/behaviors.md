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
to the project's stack (CSS, Tailwind, Motion): keep the values. A block labeled with a stack (Motion
for React, Tailwind) applies only when the project's files show that stack; otherwise keep the
behavior and look up the stack's own form. A rule that ends in **Audit:** gives the severity
`/user-interface:audit` uses for a finding against it.

Contents: `press`, `popover`, `tooltip`, `modal`, `drawer`, `toast`, `accordion`, `group-entrance`,
`section-entrance`, `exit`, `icon-swap`, `first-paint`, `group-exit`, `looping`, `hold-to-confirm`,
`tab-indicator`, `scroll-reveal`, `drag-to-dismiss`, `crossfade-mask`.

## Button press: `press`

- Any pressable element scales down slightly on press (0.95 to 0.98) and back on release.
- Role `press`, curve `out`. Feedback starts on press-down, never on release.
- Children scale with it, which is what reads as physical.
- No hover gate: a press is real on touch.
- `scale(0.96)` on `:active`, animated with a ~150ms ease-out CSS transition so a release mid-press
  glides back instead of snapping. Going under `0.95` starts to look cartoonish. The CSS is the
  press recipe in `/user-interface:write-css`.
- Not every button needs it: dense or high-frequency UI can skip it. Bake an opt-out into your
  Button component, e.g. a `still` prop.
- What may be skipped is the scale, not the pressed state: a button that skips it still shows
  `:active` some other way, such as a color shift, and a button with no `:active` state at all is
  the `forms` concern's finding.

Illustration (React with Tailwind):

```tsx
function Button({ still = false, className, ...rest }) {
  const classes = cn(
    "transition-[scale] duration-150 ease-out",
    !still && "active:not-disabled:scale-[0.96]",
    className,
  );
  return <button className={classes} {...rest} />;
}
```

## Dropdown, popover, menu, select: `popover`

- Opens from opacity zero and a scale near 0.95 to full; closes the reverse way.
- Fade + scale from `0.95`, 150-200ms ease-out, **origin-aware**: scale from the trigger, not the
  center.
- Origin at the trigger, so the panel looks like it came out of what was clicked. A dropdown that
  grows from its own center looks detached from the button that opened it. Anchored surfaces scale
  from the trigger side. Viewport-centered modals with no anchored trigger are the exception and
  stay centered.
- Many headless component libraries expose the trigger position as a CSS variable for this; look
  it up for the project's library. The CSS is the popover recipe in `/user-interface:write-css`.
- Role `medium` (`small` for a small popover), curve `out`.
- A small directional nudge (`translateY(-4px)` → `0` when opening downward) adds polish.
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

- The popover behavior, faster: role `small`, a scale closer to 1 (about 0.97). Fast and subtle:
  fade + `scale(0.97)`, ~125ms ease-out, origin-aware.
- The critical detail is the **instant-group behavior**: the first tooltip gets a hover delay and
  animation; while one is open, sibling tooltips appear instantly with no delay and no animation.
- A tooltip delay (~200ms) stops tooltips firing on incidental mouse travel. Track a shared "warm"
  flag; clear it ~300ms after the last tooltip closes.
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

- Opens from opacity zero and a scale near 0.96; stays centered (no trigger origin).
- Enter: fade + slight scale-up from `0.95`-`0.97`, 200-250ms ease-out. Exit: the same fade and scale,
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
  mid-open). 250-300ms ease-out enter, faster exit. Backdrop fades with the same timing.
- Role `large`, curve `drawer`, on the way in and on the way out: a drawer leaves but stays nearby.
- Dragging it turns it into a gesture: `drag-to-dismiss` and `gestures.md`. If the drawer is
  draggable (mobile sheet), use a spring so release velocity carries into the animation.

Illustration (CSS; the curve is the `drawer` default):

```css
.drawer {
  transform: translateX(100%);
  transition: transform 300ms cubic-bezier(0.32, 0.72, 0, 1);
}
.drawer[data-open] { transform: translateX(0); }
```

## Toast: `toast`

- Enters from its edge by its own size with a fade, and leaves the way it came. Enters with
  translate + fade from its screen edge (bottom edge → `translateY(16px)` → `0`), 200-250ms
  ease-out. Exit: fade + small translate toward the edge, faster. A dismissed toast is a permanent
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
pieces (heading, supporting copy, call to action) and offset each by roughly 100ms. The softest
layered enter pairs a fade with a short upward travel (`translateY(8px)` → 0) while a light
`blur(2px)` melts away. Hero headlines can go finer-grained: per-word offsets of ~80ms.

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

An exit deserves less emphasis than an enter: by the time something leaves, attention has already
moved elsewhere.

- Nudge a fixed few pixels (`translateY(-8px)` or so), never the element's own height. The
  direction follows the path it entered by, so the sign depends on the edge (`catalog.md`,
  "Physicality").
- A hint of direction tells the eye where the thing went; a pure fade loses that.
- Run it shorter: ~150ms out against ~250-300ms in, at most `exit_factor` of the entrance.
- A permanent exit accelerates away on `in`; a toggled one leaves on the curve it entered with
  (`catalog.md`, "Easing").
- Don't cut straight to `display: none`: instant disappearance severs spatial context.

Reserve a full off-screen slide (`x: "-100%"`) for moments where the destination itself is the
information: a swiped-away list card, a closing drawer.

Illustration (Motion for React; a permanent exit, the curve is the `in` default):

```tsx
<motion.div exit={{ opacity: 0, y: -8, filter: "blur(2px)",
  transition: { duration: 0.14, ease: [0.3, 0, 1, 1] } }} />
```

## Contextual icon swap: `icon-swap`

Icons that change with state (play → pause, like → liked, copy → check) deserve a real cross-fade,
not a visibility toggle. The recipe: shrink deep, fade, add a whisper of blur, and drive it with a
bounce-free spring.

- `scale`: `0.3` → `1`: a deep scale-down reads as a swap; a timid one (0.8, 0.9) reads as a glitch
- `opacity`: fades `0` → `1` alongside the scale
- `filter`: `blur(3px)` sharpening to `blur(0px)`
- spring: `{ type: "spring", duration: 0.35, bounce: 0 }`: keep bounce at zero, icons aren't toys

Illustration (Motion for React):

```tsx
<AnimatePresence mode="popLayout" initial={false}>
  <motion.span key={copied ? "check" : "copy"}
    initial={{ scale: 0.3, opacity: 0, filter: "blur(3px)" }}
    animate={{ scale: 1, opacity: 1, filter: "blur(0px)" }}
    exit={{ scale: 0.3, opacity: 0, filter: "blur(3px)" }}
    transition={{ type: "spring", duration: 0.35, bounce: 0 }}>
    {copied ? <CheckIcon /> : <CopyIcon />}
  </motion.span>
</AnimatePresence>
```

Without Motion: render **both icons at once**, layering one absolutely over the other, and swap
classes to cross-fade: nothing ever unmounts, so the reverse direction animates just as well. A firm
ease-out such as `cubic-bezier(0.25, 0.1, 0, 1)` over ~300ms stands in for the spring. The icon left
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
`AnimatePresence`.

- **Pointer**: Motion, "AnimatePresence", props `initial` and `mode` (`popLayout`),
  <https://motion.dev/docs/react-animate-presence#initial>,
  <https://motion.dev/docs/react-animate-presence#poplayout>.
- **As of**: 2026-10-29.
- **Recheck trigger**: Motion renames `initial={false}` or `popLayout`, or changes what either does.

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
- It dismisses when dragged past a distance threshold or released fast enough, so a flick is
  enough: faster than `animation.gesture.velocity_threshold` (px/ms) for a small element such as a
  toast; a drawer or sheet needs a higher threshold (`gestures.md`, "Drag details"). For
  drag-to-dismiss, trigger dismissal when velocity (`swipeAmount / timeTaken`) exceeds ~0.11, not
  only on distance thresholds. The threshold to compare against is the resolved
  `animation.gesture.velocity_threshold`, not the literal.
- Otherwise it springs back with the release velocity.
- Pointer capture, multi-touch protection, resistance past the edge: `gestures.md`.

## Crossfade mask: `crossfade-mask`

- When two states visibly overlap during a crossfade and tuning easing and duration does not fix
  it, add a small blur and a slight opacity dip during the transition so the eye reads one change.
  Add a subtle `blur(2px)` during the transition to bridge the states (keep well under 20px). The
  limit to keep under is the resolved `animation.blur_max_px`, 20px by default.
- Keep the blur small; its cost grows with radius and area (`performance.md`).
