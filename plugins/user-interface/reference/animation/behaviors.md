# Animation behaviors

What each common component's motion does, stated as behavior, not code. The project's design
system and motion tokens override everything here, and the roles and curves named below resolve
from the `animation:` config (`catalog.md`, "Easing" and "Duration"). Build each spec in the
project's own stack after looking up how that stack does it; CSS authoring belongs to
`/user-interface:write-css`. A component the project does not have yet comes from a component
library first (`../component-libraries.md`).

Contents: `press`, `popover`, `tooltip`, `modal`, `drawer`, `toast`, `accordion`, `group-entrance`,
`hold-to-confirm`, `tab-indicator`, `scroll-reveal`, `drag-to-dismiss`, `crossfade-mask`.

## Button press: `press`

- Any pressable element scales down slightly on press (0.95 to 0.98) and back on release.
- Role `press`, curve `out`. Feedback starts on press-down, never on release.
- Children scale with it, which is what reads as physical.
- No hover gate: a press is real on touch.

## Dropdown, popover, menu, select: `popover`

- Opens from opacity zero and a scale near 0.95 to full; closes the reverse way.
- Origin at the trigger, so the panel looks like it came out of what was clicked. Many headless
  component libraries expose the trigger position for this; look it up for the project's library.
- Role `medium` (`small` for a small popover), curve `out`.

## Tooltip: `tooltip`

- The popover behavior, faster: role `small`, a scale closer to 1 (about 0.97).
- A short delay before the first tooltip prevents accidental opening. Once one tooltip in a group
  is open, moving to a neighbor opens it with no delay and no animation.

## Modal and dialog: `modal`

- Opens from opacity zero and a scale near 0.96; stays centered (no trigger origin).
- Role `large` at most, curve `out`, though most modals feel right well short of the limit.
- The backdrop fades on the same timing, so both read as one surface.

## Drawer and sheet: `drawer`

- Slides in from its edge by its own full size (a percent translate), and leaves through the same
  edge.
- Role `large`, curve `drawer`.
- Dragging it turns it into a gesture: `drag-to-dismiss` and `gestures.md`.

## Toast: `toast`

- Enters from its edge by its own size with a fade, and leaves the way it came.
- Motion that retargets from the current value, never a restarting keyframe, because toasts arrive
  in bursts.
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

- Items of a list or grid the user sees occasionally fade and rise a few pixels into place, 30 to
  80 ms apart.
- Never on a list the user scrolls past all day, and never blocking interaction while it plays.

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
- It dismisses when dragged past a distance threshold or released faster than
  `animation.gesture.velocity_threshold` (px/ms), so a flick is enough.
- Otherwise it springs back with the release velocity.
- Pointer capture, multi-touch protection, resistance past the edge: `gestures.md`.

## Crossfade mask: `crossfade-mask`

- When two states visibly overlap during a crossfade and tuning easing and duration does not fix
  it, add a small blur and a slight opacity dip during the transition so the eye reads one change.
- Keep the blur small; its cost grows with radius and area (`performance.md`).
