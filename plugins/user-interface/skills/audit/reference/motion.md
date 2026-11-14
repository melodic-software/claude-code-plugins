# Motion lane

The procedure for the `motion` row of `reference/concerns.json`. The audit's generic steps run
first; this file adds what only motion needs.

## Scope and config

- The resolved `animation:` config sets the role durations and curves the lane judges against;
  the project's own motion tokens beat it.
- Film, video, sprite and pixel-art animation are out of scope.
- List every animation in scope with its element, `path:line`, driver and properties. Name the
  stack of each from its files; when you do not know how that stack animates, look it up as
  the "Look up what you do not know" step of `/user-interface:write-animation` does before judging
  it.

## CSS pre-pass

For CSS-styled files in scope, invoke `/user-interface:write-css review` with the Skill tool on
those paths. Its `duration` check flags only a transition over the configured `large`, so judge
every duration yourself under "Role durations" below, the ones it flagged and the ones it missed.
Keep the rest of its motion findings (`ease-in`, `transition-all`, `motion`) as findings of this
lane; an `ease-in` finding's fix is the one catalog.md "Easing" gives (the configured `in` curve on
a permanent exit, else an ease-out curve), not the linter's message. Keep a
`hover` finding only when it is about the animation (hover motion, catalog.md "Pointer gating"); an
ungated `:hover` rule itself is the `touch` concern's finding.

## Review

Judge each animation against [catalog.md](../../../reference/animation/catalog.md) (gate, purpose,
properties, physicality, easing, duration, interruption, reduced motion, pointer gating),
[behaviors.md](../../../reference/animation/behaviors.md) for a known component, and
[gestures.md](../../../reference/animation/gestures.md) for drag and springs.

- **Role durations.** A duration is judged by its role: a modal, dialog, drawer, sheet or toast
  against `large`, anything else against the role catalog.md "Duration" and behaviors.md give its
  component (`medium` when unclear).
- The accordion height exception in catalog.md "Properties" is not a finding.
- **A captured frame.** When a frame-state export is pasted, or a finding turns on frames (an
  interruption, a page-load entrance), read or capture it as [frame-capture.md](frame-capture.md)
  says; a capture runs only after the user's yes to the command it names.

## Severity

Place an untagged motion finding on the audit ladder this way:

- **Blocking**: input locked during a transition.
- **Important**: a trigger-anchored element growing from its center.
- **Suggestion**: a weak curve, missing stagger.

A finding a spoke tag covers keeps that tag. In catalog.md: motion on a keyboard action or one
used more than `animation.skip_frequency` times a day ("Should it animate"), scale from zero
("Physicality"), a duration over its role and an exit's length ("Duration"), a keyframe animation
that restarts on a toggle or a rapid trigger ("Interruption and exit"), movement with no
reduced-motion handling ("Reduced motion"), and every ease-in finding, an exit that is not a
permanent one included ("Easing"; its **permanent exit** paragraph, before the numbered list, says
which exits are). In performance.md: an animated layout property ("Swap down a tier"). In
behaviors.md: a press scale below its lower limit ("Button press").

## Sub-modes

- **`cleanup`**: the lane's passes in a configured order. Read the resolved
  `animation.cleanup_order` from the detect step's `config.values`, and name the layer it came
  from in `config.provenance`. Run one pass per value, in list order; a value listed twice runs
  once, at its first position. `review` is the lane with no sub-mode (the CSS pre-pass and
  "Review" above); `removal`, `opportunities` and `performance` are the sub-modes below. A pass
  whose scope holds nothing to judge (`performance` with no animation named) says so and asks
  which animation to diagnose. Report each pass as its own subsection of the motion lane's
  section, in run order, under the lane's one verdict. A later pass does not report again on an
  animation an earlier pass marked Delete. With `--fix`, findings are offered in pass order.
- **`opportunities`**: where animation would help, and where it must not go. For each suggestion,
  the element, its purpose and its frequency tier; then the places that must stay still, with the
  reason.
- **`performance`**: why an animation drops frames. Name the cause from
  [performance.md](../../../reference/animation/performance.md)'s diagnosis order before any
  proposed change.
- **`removal`**: which existing animations should go. The burden of proof reverses: "it's already
  there" and "it looks nice" are not defenses. Walk every animation through catalog.md "Should it
  animate" and "Name the purpose", and record the rule that decided it. Each verdict is one of:
  - **Delete**: it fails the gate.
  - **Reduce**: it has a purpose but is too much for its frequency or role. Reduce means a smaller
    version of the same motion, at the role and curve the resolved config gives: a hover lift
    becomes a color or opacity change, a frequent slide or scale entrance becomes a fade, a loop on
    a persistent element runs once. When that stops carrying the purpose, delete it instead.
  - **Keep**: it passes, or a comment or design doc explains why it exists. A rare, first-time
    moment is kept. Motion that prevents a jarring change is kept: deleting it trades a slow
    interface for a disorienting one.

  Report the Keep list too, with the purpose that saved each one. List a kept animation that is
  badly built as a normal finding of this lane. Without that list a reader can't tell a judgment
  from deleting every transition.

  Each Delete and Reduce names the removal hazards below it was checked against, and the cleanup
  it leaves. With `--fix`, a Delete removes the animation, a Reduce replaces it with its smaller
  version and sets only the role and curve that version takes, and a Keep is not edited. No verdict
  adds motion to anything that had none. Removing a dependency is proposed, never done.

### Removal hazards

Removal is not find-and-replace. Check each before deleting:

- **Hidden start state.** A keyframe that holds its start, a library's initial state or a reveal
  class can leave the element at `opacity: 0`. Delete the start state with the animation, or the
  element stays invisible.
- **Code that waits for the animation.** An animation-end or transition-end listener, a timer sized
  to a duration, or a library's exit callback. Delete the wait, or the UI keeps pausing for motion
  that no longer exists.
- **Exit that delays unmount.** A wrapper that holds a component until its exit finishes. Move what
  ran after the exit to where the component closes.
- **Layout animation hiding a jump.** Removing it exposes a layout shift. Keep the animation and
  list the shift for the `layout-stability` concern.
- **Focus timed after motion.** Focus moved in an animation callback must move at once.
- **Tests and selectors** that wait for an animation class or duration need the same removal.

### Removal cleanup

Delete what a removal orphaned: keyframes, utilities and tokens with no references, a library's
animated element wrappers with no motion props left, empty exit wrappers, unused variants and
imports. Then search for each removed name to confirm nothing still references it.

## Gotchas

- The bundled CSS linter's own duration limits ignore the config; write-css review mode checks the
  configured `large` instead, which is why the pre-pass goes through it and not the linter directly.
- "Smooth on my machine" is not evidence. A performance finding not reproduced on a device says
  needs a device recording.
- A layer-promotion hint is the last fix, never the first; name the cause.
