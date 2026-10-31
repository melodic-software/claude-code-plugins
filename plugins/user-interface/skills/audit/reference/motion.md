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
those paths. Its `duration` findings are already judged against the configured roles; keep the rest
of its motion findings (`ease-in`, `transition-all`, `motion`, `hover`) as findings of this lane.

## Review

Judge each animation against [catalog.md](../../../reference/animation/catalog.md) (gate, purpose,
properties, physicality, easing, duration, interruption, reduced motion, pointer gating),
[behaviors.md](../../../reference/animation/behaviors.md) for a known component, and
[gestures.md](../../../reference/animation/gestures.md) for drag and springs.

- **Role durations.** A duration is judged by its role: a modal, dialog, drawer, sheet or toast
  against `large`, anything else against the role catalog.md "Duration" and behaviors.md give its
  component (`medium` when unclear).
- The accordion height exception in catalog.md "Properties" is not a finding.

## Severity

Place an untagged motion finding on the audit ladder this way:

- **Blocking**: movement under reduced motion, motion on a keyboard or many-times-an-hour action,
  input locked during a transition, a layout animation on a hot path.
- **Important**: ease-in, scale from zero, a duration over its role, a trigger-anchored element
  growing from its center, a restarting keyframe on something rapid.
- **Suggestion**: a weak curve, missing stagger, an asymmetric exit.

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
