# Animation catalog

The rules for whether a piece of interface should move and, if it should, with which ingredients.
The project's design system, motion tokens and conventions override everything in this file, and
the values in the resolved `animation:` config fill only what the project leaves undefined.
That config is `config.values.animation` in the output of `scripts/detect.mjs --config`; when
detect cannot run, it is the `animation:` block of `reference/defaults.yaml`.

Animation in a product interface is feedback, not decoration. The best UI animations go unnoticed:
they make the interface feel fast, connected, and physical, then get out of the way. Default to
less: a fast, well-eased 200ms transition beats an elaborate 500ms sequence every time. When in
doubt, don't animate. When you do animate, be exact: easing and duration are decisions, not
defaults you inherit from a snippet.

The rules name what the eye and hand experience, not an API. For how the project's stack expresses
a rule, look up the stack's own current documentation. An example anywhere in this folder is
labeled an illustration of one stack, to adapt to whatever the project uses, never a template to
copy. CSS authoring itself belongs to `/user-interface:write-css` and the names for effects to
`/user-interface:glossary`. Per-component specs are in `behaviors.md`, touch and drag in
`gestures.md`, frame cost in `performance.md`, all in this folder.

Already covered in `../types/web.md` ("Motion and interaction") and not restated here: continuing
from the current value when the target changes, expanding to content height, appearance changes
that never move the layout box, and layout changes that keep each element's identity.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like. Product UI and marketing pages have different bars: apply the
tags to product routes strictly; marketing routes get more room on duration. Each finding is graded
once: layout-property animation, `transition: all`, blur and `will-change` in `performance.md`,
reduced motion in `reduced-motion` below.

Other concerns own the neighbors, one home each: scroll-triggered reveals, scroll hijacking,
parallax, auto-advancing carousels and an intro animation that plays once per session are the
`marketing-pages` concern; a wait over 400ms that needs an indicator is the `states` concern; a
theme switch that animates every color is the `theming` concern; looping animation, video and
polling that keep running off-screen, and state updates that re-render a component every frame,
are the `web-performance` concern; hover styles gated to a precise pointer and enlarged hit areas
are the `touch` concern; animated blobs behind a hero are the `generic-defaults` concern; focus,
names and the rest of the accessibility floor are the `accessibility` concern.

Contents: `should-it-animate`, `name-the-purpose`, `cheapest-tool`, `properties`, `physicality`,
`easing`, `duration`, `dropdown-example`, `springs`, `interruption-and-exit`, `page-load`,
`stagger`, `reduced-motion`, `pointer-gating`, `personality`, `feel-check`, `never-ship`.

## Should it animate: `should-it-animate`

Decide this first; sometimes the right result is no animation at all, and that is a success. Ask
how often the user will trigger it:

- **100+ times a day** (command menu, keyboard navigation, tab switching in a power tool) → **No
  animation.** Speed beats smoothness.
- **Keyboard-initiated action** (arrow-key list navigation, shortcuts, focus movement) → **Never
  animate.** Keyboard users are moving fast; animation makes the UI feel disconnected from their
  input.
- **Tens of times a day** (hover effects, list navigation) → near-imperceptible motion, or nothing.
- **Occasional interaction** (opening a modal, a dropdown, a drawer) → Standard animation, under
  300ms. The limit each one takes is its resolved role in `duration`; 300ms is the default of the
  longest element-scale role, `large`.
- **Rare or first-time moment** (onboarding, empty state, success celebration) → Can be more
  elaborate.
- **Marketing page vs. product**: marketing pages may use longer, showier motion; product UI must
  stay fast and purposeful.

An animation the user sees a hundred times a day is a tax they pay a hundred times a day.

- Data the user is reading or acting on does not move for style. A decorative pointer-tracking
  effect belongs on a marketing page, not on a chart someone is working from.
- When the request fails this gate, say so and offer the non-motion alternative: an instant state
  change or a static affordance.
- Removing an animation changes something the user may have chosen, so ask before deleting one
  that isn't plainly a mistake. Cutting a command palette's 300ms entrance to 0 is a fix; removing
  a success celebration is a decision.

**Audit: Blocking.** An animation on a keyboard-initiated or 100-times-a-day action that delays
input: an enter animation on the command palette, animated highlight movement on arrow-key
navigation, a transition on tab switches in a tool used all day, anything animated in response to a
keyboard shortcut.

**Audit: Important.** The same animation when it does not delay input.

## Name the purpose: `name-the-purpose`

Animate when it adds information: spatial continuity (where did this come from?), state feedback
(did my click register?), or connection between cause and effect. If the animation answers no
question, cut it.

Name the purpose in one of these words before choosing anything else. If none fits, do not build
it.

- **Feedback**: confirms the interface heard the user.
- **Spatial consistency**: shows where something came from or went.
- **State indication**: makes a state change legible.
- **Preventing a jarring change**: bridges content that would otherwise jump.
- **Explanation**: shows how something works (marketing and onboarding only).
- **Delight**: allowed only at the rare tier of the frequency list.

Every animation answers "why does this move?": feedback, spatial continuity, state change, or
preventing a jarring jump. "Looks cool" on a frequently-seen element is a block.

`fade-in-up` on scroll for every block, staggered children everywhere, `hover:scale-105` on cards,
pulsing blobs: motion applied by default instead of by decision. The scroll entrances are graded by
the `marketing-pages` concern and the blobs by the `generic-defaults` concern; a hover scale on a
card that isn't clickable is graded in `pointer-gating` below, and staggered children in `stagger`.

**Audit: Blocking.** An animation on an element the user sees often whose only purpose is that it
looks cool: none of the purposes above applies.

## Cheapest tool: `cheapest-tool`

Before writing any animation code, check what the project already uses: plain CSS
transitions/keyframes, Tailwind, Motion (`motion`/`framer-motion` in package.json), React Spring, or
WAAPI. Write animations in that system. Never add an animation library for something CSS
transitions can do, and never hand-roll spring physics when Motion is already installed. The same
holds for any spring library the project already has.

Walk down the ladder and stop at the first rung that does the job. The rungs are kinds of tool; the
project's stack names its own.

1. A declarative transition between two states the code already switches (a class, an attribute,
   a state flag).
2. A declarative entry style, so an element animates in when it first appears without script.
3. A declarative keyframe animation, for predetermined motion that must stay smooth while the page
   is busy.
4. The platform's script animation API, for programmatic control without a new dependency.
5. An animation library already in the project, for springs, layout animation, exit animation of
   removed elements, or gesture-driven values.

- Do not add a dependency for a fade. When a library is needed and none is installed, ask before
  adding one.
- When the task needs a component (a toast, a drawer, a command menu, a dropdown), not just its
  motion, pick a component library first: `../component-libraries.md`. Hand-rolled components miss
  focus management and keyboard behavior.

**Audit: Important.** A new dependency for a simple fade, or an animation library added where the
project's existing stack does the job.

## Properties: `properties`

- **Animate only `transform` and `opacity`.** They can run on the compositor and skip
  layout/paint. Never animate `width`, `height`, `margin`, `padding`, `top/left`, or box-shadow
  spread directly: animate `transform: scale/translate` and cross-fade instead. They change how an element is
  drawn, not where it sits, so nothing is re-measured. Anything else needs a reason;
  `performance.md` holds the cost tiers, the blur limit and the finding for a layout property.
- **The accordion is the one sanctioned height exception**, done the way `../types/web.md` says.
  Never animate to an unmeasured automatic height.
- **A clip** (an inset rectangle that eats in from each side) is a strong reveal tool: reveal on
  scroll, a hold-to-confirm fill, a tab highlight, a comparison slider.
- **A translate in percent** moves by the element's own size, so an element of unknown height can
  slide fully out of view. Prefer it over fixed pixel distances.

## Physicality: `physicality`

- **Never enter from `scale(0)`.** Elements should always have a visible shape: start at
  `scale(0.95)` (or `0.97` for small elements) with `opacity: 0`, and settle to `scale(1)`,
  `opacity: 1`. Any start between 0.9 and 0.97 keeps a shape; nothing in the physical world appears
  from nothing.
- An element scaling up from nothing reads as a glitch; real objects always have a visible shape.
  The same goes for a toast that travels the full viewport height to arrive. Travel distances stay
  small (8-16px) unless the element really is coming from off-screen, like a drawer.
- **Make scaling origin-aware.** Popovers, dropdowns, and tooltips must scale from their trigger,
  not from center. Set `transform-origin` to the trigger side. The popover recipe in
  `/user-interface:write-css` shows the CSS, and `behaviors.md` `popover` the behavior.
- Modals and popovers should scale up from the element that triggered them (shared origin), not
  pop from screen center: origin creates continuity. (Exception: viewport-centered modals with no
  anchored trigger stay centered.) In practice the trigger origin applies to anchored surfaces
  (popovers, dropdowns, tooltips, menus); a modal centered in the viewport, the usual case, stays
  centered (`behaviors.md` `modal`).
- **Paired elements share timing.** Modal + overlay, drawer + backdrop, tooltip + arrow: if they
  move as a unit, give them identical duration and easing. Mismatched timing reads as broken. A
  modal at 300ms over a backdrop at 150ms reads as two unrelated things happening near each other.
- **Press feedback** (the scale, its limits, and which controls skip it) is `behaviors.md` `press`.
- **Enter and exit along the same path.** A panel that slides in from one edge leaves through that
  edge.

**Audit: Important.** An entrance from `scale(0)`, `scale: 0` or `initial={{ scale: 0 }}`, or a
small element arriving from `translateY(100vh)` or `translateY(100%)`.

**Audit: Important.** An overlay and its content (a dialog and its backdrop, a drawer and its
backdrop) with different durations or easing.

## Easing: `easing`

The curves are the `out`, `in`, `in_out` and `drawer` entries of the resolved `animation.easing`,
each four cubic Bezier control points; map them to the stack's own easing form. Below, `ease-out`
means the `out` curve, an accelerate curve means `in`, and `ease-in-out` means `in_out`. A drawer or
sheet takes `drawer`; anything else takes `out`.

A **permanent exit** removes the element for good: it unmounts, or the user dismisses it (a dialog
answered or closed, a toast dismissed, an item deleted). The test is whether the control that
opened the element can close it again while it is open (a menu button, a popover trigger, a drawer
toggle, an accordion header): if it can, the element is toggled, not removed, and it leaves on the
curve it entered with, even when the framework unmounts it on close.

1. **Element entering or exiting the screen** (modal, dropdown, toast, tooltip) → `ease-out`. The
   fast start reads as instant response to the user's action. A permanent exit is the exception in
   item 5.
2. **Element already on screen moving or resizing** (reordering, layout shift, slider) →
   `ease-in-out`. Natural accelerate-then-brake motion.
3. **Hover / color / shadow change** → `ease` (or a soft ease-out), 150ms.
4. **Constant-speed motion only** (marquee, spinner, progress-as-time) → `linear`.
5. **`ease-in` alone → almost never.** The slow start delays feedback and feels sluggish. A
   permanent exit (a modal closing, a toast dismissed) accelerates away on an accelerate curve from
   the ease-in family; a panel that leaves but stays nearby, such as a drawer, exits on the standard
   curve it entered with.

- **Never ease-in on entrances or on-screen motion.** `ease-in` starts slow, which delays the
  movement at the exact moment the user is watching for a response to their click. A dropdown with
  `ease-in` feels slower than the same dropdown with `ease-out` at the same duration. A permanent
  exit is the one exception: it accelerates away on a custom accelerate curve (`in`), never the bare
  `ease-in` keyword, and stays short, because a slow-starting exit can still read as lag. An
  explicit request for an exit that accelerates away is honored with `in`, and the reply warns
  that its slow start can read as lag.

Built-in CSS keywords (`ease-out`, `ease-in-out`) are usually too weak to feel intentional. Use
custom curves: a good default for enters is the `out` curve; use the project's easing tokens when
they exist. Stronger curves feel snappier and more designed; start around cubic/quart and adjust by
eye. The library is the resolved `animation.easing_library`: under `out` (enters, toggled exits,
user-initiated UI) and under `in_out` (elements moving or morphing on screen), the curves `quad`,
`cubic`, `quart`, `quint`, `expo` and `circ`.

Why ease-out works for enters: the fast start delivers immediate visual feedback: the element
"jumps" toward its destination, then settles. Ease-in inverts that and back-loads the movement,
which is why the same duration feels slower and sluggish.

`linear` is only for constant-rate motion: marquees, tickers, and time visualization (a
hold-to-delete progress ring should be linear because it *is* time).

Need a curve that is neither configured nor in the library? Take one from an established easing
collection rather than inventing control points, and name it as a default.

**Audit: Important.** `ease-in` (not `ease-in-out`) on an entrance or on-screen motion, in a
`transition`, an `animation`, a library's `ease` prop or a utility class.

**Audit: Important.** `ease-in` or an accelerate curve on an exit that is not permanent: a menu,
drawer or popover that its trigger can close while it is open leaves on the curve it entered with.

**Audit: Suggestion.** A built-in keyword curve on a deliberate animation where a custom curve
belongs, or a permanent exit on the bare `ease-in` keyword instead of an accelerate curve. A hover,
color or shadow change on `ease` (item 3) is not a finding.

## Duration: `duration`

The limits are the roles in the resolved `animation.duration_ms`. Each is the longest the role
allows, not a target.

| Role | Covers |
|---|---|
| `press` | press feedback |
| `small` | tooltips, small popovers |
| `medium` | dropdowns, menus, selects, and any other UI transition (hover, color, focus) |
| `large` | modals, dialogs, drawers, sheets, toasts |
| `page` | page-level and full-screen transitions |

- **UI animations stay under 300ms.** If it feels slow, it is slow: cut duration before anything
  else. Past 300ms the user is waiting for the interface to finish performing before they can act.
  The resolved roles govern, not the literal: 300ms is only the default of `large`, the longest
  element-scale role, so a project that sets `large` longer or shorter is held to its own value.
  Each animation stays within its own role, and page and full-screen transitions take `page`.
- **Exits run ~20–30% faster than enters** (e.g. enter 250ms, exit 180ms). The user has already
  decided to leave; don't make them wait. An exit takes at most
  `animation.duration_ms.exit_factor` of its entrance.
- **Bigger elements and longer travel get more time**; a full-screen sheet or a very steep curve
  can justify more than a tooltip. A 500ms fade on a dropdown can't. Duration and easing move
  together.
- Hover transitions: 150ms feels native; 400ms feels like the UI is thinking.
- Small, frequent interface motion sits near the short end of its role; a shorter dropdown feels
  more responsive than a longer one.
- Explanatory and marketing motion may run longer than any role.
- Perceived speed matters as much as real speed: a snappy 180ms dropdown makes the whole app feel
  faster. A spinner that feels slow even though load time is fixed: spin it faster, because
  perceived speed is real UX.

**Audit: Important.** A duration over its resolved role with no stated reason, on product UI (at
the defaults, `duration-500`, `duration: 0.5` or `0.6s` on a dropdown or a modal), or a
`transition` with a long `delay`.

**Audit: Suggestion.** An exit longer than `animation.duration_ms.exit_factor` of its entrance, or
louder than it (a full-height slide where a small nudge would do).

## Worked example, two dropdowns: `dropdown-example`

Two menus open from the same button. The bad one opens in 0.4s with `ease-in`, scales up from
`scale(0)`, and grows from its own center. The good one opens in 0.2s on a strong ease-out curve,
from `scale(0.95)`, out of the trigger.

Here's why the one on the right feels better: it uses `ease-out` as the easing, which is fast at the
beginning and helps it feel snappy. `scale(0.95)` feels better than `scale(0)` because nothing in
the real world appears out of nothing. The duration is `200ms` because a dropdown is used dozens of
times a day, no need to slow the user down.

## Springs: `springs`

Use a **spring** instead of a curve when motion is gesture-driven or interruptible (drag-to-dismiss,
sheets, anything that follows a finger). Springs preserve velocity when interrupted; CSS keyframes
restart from zero. The default spring and when to add bounce are `gestures.md`
`spring-parameters`, which also maps springs to two parameters for any library.

Reach for a spring instead of a fixed duration when the motion follows a drag with momentum, an
element should feel alive, the user can interrupt or reverse a gesture, or a decorative value
follows the pointer. A spring has no fixed duration; it settles from its parameters and keeps its
velocity when retargeted. Parameters, velocity hand-off and drag details are in `gestures.md`.

## Interruption and exit: `interruption-and-exit`

- **Interactive state gets CSS transitions; one-shots get keyframes.** Transitions retarget
  smoothly when the user reverses mid-animation (open → close while still opening); keyframes
  restart and look broken. Reserve `@keyframes` for enter sequences and loaders that always run to
  completion.
- **Retarget, do not restart.** Anything the user can trigger twice in a second (a toggle, a toast
  being added) uses motion that continues from its current value; a keyframe animation that
  restarts from its first frame is wrong there. A drawer closed while it's still opening jumps to
  fully open and then plays the close. A toast stack that re-runs its entrance whenever a sibling
  is added flickers. Transitions and springs retarget from wherever the element currently is.
- Put on the human list: "open and close each drawer, menu, and accordion as fast as you can and
  watch for jumps".
- **Asymmetric timing where the user is deciding.** A deliberate phase (holding to confirm a
  destructive action) is slow and linear, because it is progress; the system's response on release
  is fast.
- Exit-and-enter should be asymmetric: an exit is departure, not an entrance played in reverse. It
  takes the entrance's path, runs shorter (`duration`) and is quieter; its distance and curve are
  `behaviors.md` `exit`.
- **Exits exist.** An element that animates in and then vanishes instantly severs the spatial
  context the entrance built. In React the cause is usually conditional rendering with no presence
  wrapper: the node unmounts before any exit can play.
- **Masking a crossfade that will not settle.** When two overlapping states stay visible however
  the easing and duration are tuned, a small blur during the transition blends them into one
  perceived change. Keep it small: blur cost grows with radius and area (`performance.md`).

A transition interpolates from wherever the element currently is toward its newest target:
interrupt it and it retargets from the live position, taking only as long as the remaining distance
needs. A keyframe animation plays a fixed timeline from frame one; interrupt it and it snaps back to
the start and replays.

Illustration (CSS):

```css
/* Interruptible: hitting close mid-open reverses from the current position */
.side-panel { transform: translateX(100%); transition: transform 240ms var(--ease-out, ease-out); }
.side-panel[data-open] { transform: translateX(0); }

/* Not interruptible: closing mid-open replays or jumps */
.side-panel[data-open] { animation: panel-in 240ms var(--ease-out, ease-out) forwards; }
```

**Audit: Important.** `@keyframes` or `animation:` on anything with an open and closed toggle
(drawers, accordions, toggles, tabs, toasts), or gesture-driven motion (drag-to-dismiss, sheets) on
a fixed-duration tween instead of a spring. Rapidly-triggered or gesture motion is interruptible:
transitions or springs that retarget, not `@keyframes` restarting from zero.

**Audit: Important.** An entrance with no exit: a conditionally rendered element with an exit
defined but nothing that keeps it mounted while the exit plays (in Motion for React, an `exit` prop
with no `AnimatePresence` ancestor, so the `exit` is silently dead), or CSS enter keyframes with
`display: none` on close.

## Page load: `page-load`

**Don't animate initial page load state.** Anything that's simply sitting in its resting position
when the page appears has no reason to play an entrance: save the motion for state changes the user
causes afterward. A tab indicator that slides into place on first render, an icon that plays its
swap animation on mount, a sidebar that animates open on every navigation. Nothing the user didn't
cause should move when the page appears. A genuinely first-run entrance, like a staggered hero,
keeps its entrance; how to suppress the rest in a stack is in `behaviors.md` `first-paint`.

**Audit: Important.** An element present at first paint that plays an entrance on mount: a toggle,
tab or icon swap that animates in on load, or a shared-layout indicator that animates from `0,0`.

## Stagger: `stagger`

Stagger the entrance of a group the user sees occasionally. Eight items entering at once read as a
flash; staggered at 30–50ms they read as arrival. A 150ms stagger across twelve items makes the user
wait two seconds for a list. Cap the total: stagger × count stays under ~400ms. When the project
sets no stagger of its own, write the resolved `animation.stagger_ms.interval`, and the cap is the
resolved `animation.stagger_ms.max_total`. Stagger is decoration: it never blocks interaction while
it plays, and a list the user scrolls past all day does not stagger.

Choreograph: when three elements would move simultaneously and clash, let one move at a time.
Competing parallel motion is visual noise.

**Audit: Suggestion.** A list or grid stagger interval over 50ms (or over the project's own
stagger), or interval × count over `animation.stagger_ms.max_total`; a group entering all at once
where a short stagger belongs. The larger offsets of a section entrance (behaviors.md
`section-entrance`) are not this finding.

## Reduced motion: `reduced-motion`

The floor is `../principles.md` ("Motion is optional"): under a reduced-motion setting, remove
movement (sliding, scaling, parallax, springs, overshoot) and keep only short opacity or color
changes that help the reader follow a state change. `prefers-reduced-motion` is honored: keep
opacity/color, drop movement; disable decorative-only motion entirely. Without the check,
movement-heavy UI triggers vestibular symptoms for some users.

Motion can make people sick. `prefers-reduced-motion: reduce` means **remove the movement, keep the
meaning**: a modal that scales in becomes one that fades in; a sidebar that slides becomes one that
fades; a multi-step form that slides crossfades instead. Never zero out feedback entirely.

- **Respect `prefers-reduced-motion`: always.** Every animation you add gets a reduced-motion path.
  Ship the reduced variant with the animation, never as a follow-up.
- Build the state change first and add movement only when the user has not asked to reduce
  motion, instead of stripping it afterwards. If the project's animations run through shared
  keyframes or duration tokens, make the swap there. The CSS is the `reduced-motion-swap` recipe in
  `/user-interface:write-css`.
- The blanket `* { animation: none !important; transition: none !important; }` is a finding, not a
  fix. It removes the fades that tell the user something happened.
- **Autoplaying video**: don't autoplay under `reduce`; show controls. For video, a reduced-motion
  path means offering a play button instead of autoplaying.
- **Animated GIF/AVIF**: `<picture>` with a `media="(prefers-reduced-motion: no-preference)"` source
  and a static `<img>` fallback.
- **Looping animation**: pause it on a representative frame, not frame 0: `animation-play-state:
  paused; animation-delay: -0.4s`.
- **Smooth scrolling** is opt-in under `no-preference`, not opt-out under `reduce`; the CSS is the
  anchor-target recipe in `/user-interface:write-css`.
- Avoid large moving backgrounds, slow looping oscillations and abrupt brightness jumps even
  without the setting.
- How the stack reads the setting (a media query, a platform accessibility API, a library hook) is
  a lookup for the stack's own docs. In Motion for React, read when the project lists `motion` or
  `framer-motion`: gate `initial`/`animate` values with `useReducedMotion()`, and honor the OS
  setting app-wide with `<MotionConfig reducedMotion="user">`, set explicitly rather than left to
  the library's default (pointer below).

Illustration (React with Motion; adapt to the stack):

```tsx
const reduce = useReducedMotion();
<motion.div initial={reduce ? false : { opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} />

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
<video autoPlay={!prefersReducedMotion} controls={prefersReducedMotion} muted playsInline />
```

Verify with the browser's rendering tools, emulating `prefers-reduced-motion: reduce`. The common
failure is a "reduced" variant that still moves because one transform lives in a shared class.

- **Pointer**: Motion, "MotionConfig", props, `reducedMotion` (options and the `"never"` default),
  <https://motion.dev/docs/react-motion-config#reducedmotion>; Motion, "Accessibility",
  <https://motion.dev/docs/react-accessibility#automatic>.
- **As of**: 2026-10-29.
- **Recheck trigger**: Motion changes the `reducedMotion` default or its options, or renames
  `useReducedMotion`.

**Audit: Blocking.** Large movement (a slide, a scale-in of a panel, parallax, a full-screen
transition, an autoplaying video or animated image) with no `prefers-reduced-motion` handling or
library equivalent anywhere in the file or the tokens.

**Audit: Important.** Smaller movement with no reduced-motion handling; a reduced variant that still
moves; reduced motion done with the blanket rule that removes every fade; an infinite loop or
`scroll-behavior: smooth` that ignores the setting.

## Pointer gating: `pointer-gating`

Hover motion runs only where a precise pointer can hover: touch screens fire a hover on tap and
leave it stuck. **Gate hover animations to real hover devices.** Touch devices fire hover on tap.
Wrap hover motion in `@media (hover: hover) and (pointer: fine)`. Press feedback needs no gate,
because a press is real on touch. Touch and small-screen behavior, and the finding for an ungated
hover, are the `touch` concern (`../types/touch-web.md`).

A utility framework's hover variant may gate only half of that query: read what the project's
version compiles to (pointer below) and add the `pointer: fine` half where it is missing.

- **Pointer**: Tailwind CSS, "Hover, focus, and other states", "Quick reference" (the `hover` row),
  <https://tailwindcss.com/docs/hover-focus-and-other-states#quick-reference>.
- **As of**: 2026-10-29.
- **Recheck trigger**: Tailwind changes the media query its `hover` variant compiles to.

Hover motion doesn't make the target run away. An element that translates or scales on hover moves
its own hit area. At the edge, the cursor falls off, hover ends, the element returns, hover starts
again: a flicker loop. Keep the hovered element still and animate a child, so the hit area never
moves. A hover scale on something that isn't clickable is a false affordance; remove it. Hover
scale stays at 1-2%.

**Audit: Important.** `:hover { transform: translateY(…) }` or a hover `scale` above ~1.02 applied
to the hovered element itself, or a hover scale on an element that isn't clickable.

## Personality: `personality`

Match motion to the component's character: a playful product can be bouncier; a professional
dashboard is crisp and fast. A notification toast is the common exception that may run slightly
slower with a gentler ease than the generic budget, as long as it stays within `large`. The balance
of opacity against height in a list where items enter and leave has no formula: adjust until it
feels right, then check again later.

## Feel check: `feel-check`

An agent can build almost anything you ask for now. What it can't do is tell you whether the result
is good. That part is still on you. Motion correctness can't be proven from code.

When the result depends on feel that code cannot settle (a crossfade, a spring's bounce, an
entering list), say so and name the check instead of guessing a value:

- Play it at two to five times its duration, or step through it frame by frame in the platform's
  animation inspector, to see whether coordinated properties stay in sync and the easing ends
  cleanly. Animation feels off and you can't say why: screen-record it and scrub frame by frame;
  details invisible at full speed show up. Scrubbing is also how to find the one thing that feels
  off in an animation someone else built. To hand that frame to an agent, capture its state with
  `/app-control:drive capture --kind animation`.
- Put on the human list: "open each animated surface on a mid-range phone and watch the first
  frame", and "in the browser's animation panel, slow playback to 10% and watch each enter and exit
  for a jump at the start or the end". Report these as checks to run, never as verified.
- Test gestures on a real device, not an emulator or a laptop trackpad.
- Don't ship an animation in the same sitting you wrote it. Come back with fresh eyes: the best
  motion is refined over days, not hours. And use your own product daily: the animations that
  become annoying through repetition are the ones to remove. Details that go unnoticed are the
  goal; users should finish their task, not admire the transition.

## Never ship: `never-ship`

| Never | Instead |
|---|---|
| Animating every property at once | Name the exact properties |
| An entrance from scale zero | Scale near 0.95 with zero opacity |
| Ease-in on an entrance or on-screen motion | `out`, or `in_out` on screen; `in` for a permanent exit |
| Motion on a keyboard shortcut or a many-times-an-hour action | No animation |
| A duration over its role with no stated reason | Within the role in `animation.duration_ms` |
| A trigger-anchored popover growing from its center | Origin at the trigger (modals exempt) |
| A restarting keyframe on something triggered rapidly | Motion that retargets from the current value |
| Animating layout properties (width, height, margins, offsets) | Transform and opacity, or the accordion exception |
| Ungated hover motion | Gate it to precise pointers |
| No reduced-motion variant | Movement removed, short opacity or color change kept |
| Everything entering at once | A short stagger |

When reviewing existing animation code, check in order: (1) should this animate at all
(frequency)? (2) transform/opacity only? (3) easing matches the enter/move/hover rule? (4) duration
under 300ms with faster exit? (5) interruptible? (6) origin-aware? (7) reduced-motion path exists?
Report findings as a Before/After markdown table. In item 4, read 300ms as the animation's own resolved
role in `duration`.
