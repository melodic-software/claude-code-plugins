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
those paths. The linter's `duration` check uses fixed limits, not the configured roles, so judge
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

A finding a spoke tag covers keeps that tag. In catalog.md: motion on a keyboard or
many-times-a-day action ("Should it animate"), scale from zero ("Physicality"), a duration over its
role and an exit's length ("Duration"), a keyframe animation that restarts on a toggle or a rapid
trigger ("Interruption and exit"), movement with no reduced-motion handling ("Reduced motion"), and
every ease-in finding, an exit that is not a permanent one included ("Easing"; its **permanent
exit** paragraph, before the numbered list, says which exits are). In performance.md: an animated
layout property ("Swap down a tier").

## Sub-modes

- **`opportunities`**: where animation would help, and where it must not go. For each suggestion,
  the element, its purpose and its frequency tier; then the places that must stay still, with the
  reason.
- **`performance`**: why an animation drops frames. Name the cause from
  [performance.md](../../../reference/animation/performance.md)'s diagnosis order before any
  proposed change.

## Gotchas

- The bundled CSS linter has fixed duration limits of its own; the configured role decides, which
  is why the pre-pass goes through write-css review mode and not the linter directly.
- "Smooth on my machine" is not evidence. A performance finding not reproduced on a device says
  needs a device recording.
- A layer-promotion hint is the last fix, never the first; name the cause.
