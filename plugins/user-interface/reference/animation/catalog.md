# Animation catalog

The rules for whether a piece of interface should move and, if it should, with which ingredients.
The project's design system, motion tokens and conventions override everything in this file, and
the values in the resolved `animation:` config fill only what the project leaves undefined.

The rules name what the eye and hand experience, not an API. For how the project's stack expresses
a rule, look up the stack's own current documentation. An example anywhere in this folder is
labeled an illustration of one stack, to adapt to whatever the project uses, never a template to
copy. CSS authoring itself belongs to `/user-interface:write-css`. Words for effects are in
`glossary.md`, per-component specs in `behaviors.md`, touch and drag in `gestures.md`, frame cost
in `performance.md`, all in this folder.

Already covered in `../types/web.md` ("Motion and interaction") and not restated here: continuing
from the current value when the target changes, expanding to content height, appearance changes
that never move the layout box, and layout changes that keep each element's identity.

Contents: `should-it-animate`, `name-the-purpose`, `cheapest-tool`, `properties`, `physicality`,
`easing`, `duration`, `springs`, `interruption-and-exit`, `stagger`, `reduced-motion`,
`pointer-gating`, `personality`, `feel-check`, `never-ship`.

## Should it animate: `should-it-animate`

Decide this first; sometimes the right result is no animation at all, and that is a success.

| How often the user sees it | Decision |
|---|---|
| Many times an hour (keyboard shortcuts, a command palette toggle) | No animation |
| Tens of times a day (hover effects, list navigation) | Near-imperceptible, or nothing |
| Occasionally (modals, drawers, toasts) | Standard animation |
| Rarely or once (onboarding, a success moment, a celebration) | Room for delight |

- An action started from the keyboard does not animate: it repeats so often that motion makes it
  feel slow and disconnected.
- Data the user is reading or acting on does not move for style. A decorative pointer-tracking
  effect belongs on a marketing page, not on a chart someone is working from.
- When the request fails this gate, say so and offer the non-motion alternative: an instant state
  change or a static affordance.

## Name the purpose: `name-the-purpose`

Name the purpose in one of these words before choosing anything else. If none fits, do not build
it.

- **Feedback**: confirms the interface heard the user.
- **Spatial consistency**: shows where something came from or went.
- **State indication**: makes a state change legible.
- **Preventing a jarring change**: bridges content that would otherwise jump.
- **Explanation**: shows how something works (marketing and onboarding only).
- **Delight**: allowed only at the rare tier of the frequency table.

## Cheapest tool: `cheapest-tool`

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

## Properties: `properties`

- **Transform and opacity by default.** They change how an element is drawn, not where it sits, so
  nothing is re-measured. Anything else needs a reason, and `performance.md` holds the cost tiers.
- **The accordion is the one sanctioned height exception**, done the way `../types/web.md` says.
  Never animate to an unmeasured automatic height.
- **A clip** (an inset rectangle that eats in from each side) is a strong reveal tool: reveal on
  scroll, a hold-to-confirm fill, a tab highlight, a comparison slider.
- **A translate in percent** moves by the element's own size, so an element of unknown height can
  slide fully out of view. Prefer it over fixed pixel distances.

## Physicality: `physicality`

- **Never scale from zero.** Start from a scale near 0.95 (between 0.9 and 0.97) with zero opacity.
  Nothing in the physical world appears from nothing.
- **Anchor to the trigger.** A popover, dropdown, menu or tooltip grows out of the element that
  opened it, so set its transform origin there. A modal is exempt: it is not anchored to a trigger
  and stays centered.
- **Press feedback** scales a pressable element down slightly (0.95 to 0.98) on press, within the
  `press` role duration. The label and icon scale with it, which is what reads as a press.
- **Enter and exit along the same path.** A panel that slides in from one edge leaves through that
  edge.

## Easing: `easing`

The curves are the `out`, `in_out` and `drawer` entries of the resolved `animation.easing`, each
four cubic Bezier control points; map them to the stack's own easing form.

| Situation | Curve |
|---|---|
| Entering or leaving the screen | `out` |
| Already on screen, moving or morphing | `in_out` |
| A drawer or sheet | `drawer` |
| A hover or color change | the platform's gentle default ease |
| Constant motion (a marquee, a progress fill) | linear |
| Anything else | `out` |

- **Never ease-in on interface motion.** It starts slowly, which delays the exact moment the user
  is watching; an ease-out of the same length feels faster.
- The platform's built-in ease-out is weak for interface motion; prefer the configured curve.
- Need a curve that is not configured? Take one from an established easing collection rather than
  inventing control points, and name it as a default.

## Duration: `duration`

The limits are the roles in the resolved `animation.duration_ms`. Each is the longest the role
allows, not a target.

| Role | Covers |
|---|---|
| `press` | press feedback |
| `small` | tooltips, small popovers |
| `medium` | dropdowns, menus, selects |
| `large` | modals, dialogs, drawers, sheets, toasts |

- Small, frequent interface motion sits near the short end of its role; a shorter dropdown feels
  more responsive than a longer one.
- Explanatory and marketing motion may run longer than any role.
- Perceived speed counts as much as measured speed: a faster spinner makes the same wait feel
  shorter, and once one tooltip in a toolbar is open, its neighbors open with no delay and no
  animation.

## Springs: `springs`

Reach for a spring instead of a fixed duration when the motion follows a drag with momentum, an
element should feel alive, the user can interrupt or reverse a gesture, or a decorative value
follows the pointer. A spring has no fixed duration; it settles from its parameters and keeps its
velocity when retargeted. Parameters, velocity hand-off and drag details are in `gestures.md`.

- Default to no overshoot. Add a little bounce only when the gesture itself carried momentum (a
  flick, a throw, a drag release).

## Interruption and exit: `interruption-and-exit`

- **Retarget, do not restart.** Anything the user can trigger twice in a second (a toggle, a toast
  being added) uses motion that continues from its current value; a keyframe animation that
  restarts from its first frame is wrong there.
- **Asymmetric timing only where the user is deciding.** A deliberate phase (holding to confirm a
  destructive action) is slow and linear, because it is progress; the system's response on release
  is fast. Everywhere else, exit mirrors entry in path and timing.
- **Masking a crossfade that will not settle.** When two overlapping states stay visible however
  the easing and duration are tuned, a small blur during the transition blends them into one
  perceived change. Keep it small: blur cost grows with radius and area (`performance.md`).

## Stagger: `stagger`

Stagger the entrance of a group the user sees occasionally, with 30 to 80 ms between items; longer
gaps feel slow. Stagger is decoration: it never blocks interaction while it plays, and a list the
user scrolls past all day does not stagger.

## Reduced motion: `reduced-motion`

The floor is `../principles.md` ("Motion is optional"): under a reduced-motion setting, remove
movement (sliding, scaling, parallax, springs, overshoot) and keep only short opacity or color
changes that help the reader follow a state change.

- Ship the reduced variant with the animation, never as a follow-up.
- Build the state change first and add movement only when the user has not asked to reduce
  motion, instead of stripping it afterwards.
- Avoid large moving backgrounds, slow looping oscillations and abrupt brightness jumps even
  without the setting.
- How the stack reads the setting (a media query, a platform accessibility API, a library hook) is
  a lookup for the stack's own docs.

## Pointer gating: `pointer-gating`

Hover motion runs only where a precise pointer can hover: touch screens fire a hover on tap and
leave it stuck. Press feedback needs no gate, because a press is real on touch. Touch and
small-screen behavior is in `../types/touch-web.md`.

## Personality: `personality`

Match motion to the component's character: a playful product can be bouncier; a professional
dashboard is crisp and fast. A notification toast is the common exception that may run slightly
slower with a gentler ease than the generic budget, as long as it stays within `large`. The balance
of opacity against height in a list where items enter and leave has no formula: adjust until it
feels right, then check again later.

## Feel check: `feel-check`

When the result depends on feel that code cannot settle (a crossfade, a spring's bounce, an
entering list), say so and name the check instead of guessing a value:

- Play it at two to five times its duration, or step through it frame by frame in the platform's
  animation inspector, to see whether coordinated properties stay in sync and the easing ends
  cleanly.
- Test gestures on a real device, not an emulator or a laptop trackpad.
- Look again the next day; imperfections invisible during development surface later.

## Never ship: `never-ship`

| Never | Instead |
|---|---|
| Animating every property at once | Name the exact properties |
| An entrance from scale zero | Scale near 0.95 with zero opacity |
| Ease-in on interface motion | `out`, or `in_out` on screen |
| Motion on a keyboard shortcut or a many-times-an-hour action | No animation |
| A duration over its role with no stated reason | Within the role in `animation.duration_ms` |
| A trigger-anchored popover growing from its center | Origin at the trigger (modals exempt) |
| A restarting keyframe on something triggered rapidly | Motion that retargets from the current value |
| Animating layout properties (width, height, margins, offsets) | Transform and opacity, or the accordion exception |
| Ungated hover motion | Gate it to precise pointers |
| No reduced-motion variant | Movement removed, short opacity or color change kept |
| Everything entering at once | A short stagger |
