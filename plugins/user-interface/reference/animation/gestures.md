# Gestures and springs

How touch, drag and spring motion should feel, so an interface responds like a physical object:
it reacts at once, follows the hand, carries momentum, resists at edges, and can be grabbed and
reversed at any moment. The rules are platform-neutral; how a stack exposes pointer events,
springs and velocity is a lookup in its own current documentation, and an example here is an
illustration to adapt, never a template. The project's motion system overrides everything in this
file.

Source for the spring values and formulas: Apple, "Designing Fluid Interfaces" (WWDC 2018) and its
sample code, <https://developer.apple.com/videos/play/wwdc2018/803/>. As of 2026-10-11; recheck
when the session page or its sample code changes, or a project adopts a platform spring API with
its own documented defaults.

Contents: `respond-at-once`, `direct-manipulation`, `interruptible`, `spring-parameters`,
`velocity-handoff`, `momentum-projection`, `rubber-banding`, `drag-details`, `gesture-intent`,
`multimodal-feedback`.

## Respond at once: `respond-at-once`

- Feedback starts on press-down, not on release.
- Remove every delay on the input path that is not essential: debounces, artificial timers, waits
  for a transition to finish, a platform tap delay.
- During a drag, slider or drawer gesture, the interface updates continuously with the pointer the
  whole way through, never only when the gesture ends.

## Direct manipulation: `direct-manipulation`

- A dragged element stays glued to the pointer and keeps the offset from where it was grabbed;
  snapping its center to the pointer breaks the illusion.
- Keep a short history of recent positions and times, not just the current point: release needs a
  velocity.

## Interruptible: `interruptible`

- Never lock out input during a transition. A closing sheet the user grabs again follows the
  pointer instead of finishing its close first.
- Start any new motion from the element's current on-screen value, never from its logical target;
  starting from the target causes a visible jump.
- When a gesture reverses, carry the velocity through the retarget instead of cutting it; a cut
  reads as hitting a wall. Springs that retarget from the current velocity do this.
- Animate the two axes of a 2D motion as independent springs; one spring on the combined distance
  falls out of sync when the axes move at different speeds.

## Spring parameters: `spring-parameters`

Think in two parameters:

- **Damping ratio** controls overshoot: 1.0 settles with no bounce; below 1.0 overshoots and
  oscillates, more as it drops.
- **Response** is roughly how quickly the value reaches its target, in seconds. It is not a
  duration: the settle time emerges from the parameters.

| Interaction | Damping | Response |
|---|---|---|
| Default interface motion | 1.0 | 0.3 to 0.4 |
| After a flick, throw or drag release | about 0.8 | 0.3 to 0.4 |
| Moving or repositioning an element | 1.0 | 0.4 |
| Rotation | 0.8 | 0.4 |
| Drawer or sheet | 0.8 | 0.3 |

- Overshoot on something the user flicked feels right; overshoot on a menu that simply opened feels
  wrong.
- Libraries parameterize springs differently (damping and response, bounce and duration, or mass,
  stiffness and damping). Look up how the project's library maps to these two parameters before
  writing values.

## Velocity hand-off: `velocity-handoff`

When a gesture ends, the motion continues at the pointer's exact release velocity, so there is no
seam between dragging and animating. Pass the release velocity as the spring's initial velocity.
Some spring APIs take it relative to the remaining distance; look up which form the project's API
expects.

Illustration (pseudocode, adapt to the stack):

```text
relativeVelocity = releaseVelocity / (target - current)
```

## Momentum projection: `momentum-projection`

Do not snap to the boundary nearest the release point. Project where the momentum would carry the
element, then snap to the target nearest that projected point; this is what makes a flick throw.
Decide whether to commit or return from the velocity's direction at release, not from position
alone.

Illustration (pseudocode, adapt to the stack; the deceleration rate is about 0.998 for a normal
scroll feel and 0.99 for a snappier one):

```text
project(velocityPxPerSecond, rate) = (velocityPxPerSecond / 1000) * rate / (1 - rate)
target = nearestSnapPoint(current + project(releaseVelocity, rate))
springTo(target, initialVelocity = releaseVelocity)
```

## Rubber-banding: `rubber-banding`

At an edge, resist progressively instead of stopping hard: the further past the boundary, the less
the element follows. A hard stop reads as frozen; rising resistance reads as responsive with
nothing more there.

Illustration (pseudocode, adapt to the stack; the constant is about 0.55):

```text
rubberband(overshoot, dimension, c) = (overshoot * dimension * c) / (dimension + c * |overshoot|)
```

## Drag details: `drag-details`

- **Pointer capture** once the drag starts, so tracking continues when the pointer leaves the
  element.
- **Multi-touch protection**: ignore extra touch points after the drag begins, or switching fingers
  makes the element jump.
- **Dismiss on a flick**: a release faster than `animation.gesture.velocity_threshold` (px/ms)
  dismisses a small element such as a toast, whatever the distance. A large surface such as a
  drawer needs a higher threshold; tune it on a device.
- **Set the moving value on the element itself.** Driving it through an inherited value on a parent
  makes every child recompute each frame (`performance.md`).
- **Settle with a spring**, so an interrupted drag keeps its velocity.

## Gesture intent: `gesture-intent`

- **Tap**: highlight on touch-down, commit on touch-up, with about 10 px of slack around the
  target, and cancel when the pointer is dragged away.
- **Drag or swipe**: require a small movement (about 10 px) before committing to a direction, then
  track 1:1.
- Recognize every plausible gesture in parallel from the first movement and drop the losers once
  intent is clear. Avoid recognizers that report only a final swipe; they discard the continuous
  tracking feedback needs.
- Pay the delay of double-tap detection only where a double tap exists.
- Intermediate frames point toward the outcome: motion that grows toward the pointer tells the user
  where it is going.

## Multimodal feedback: `multimodal-feedback`

When motion is paired with sound or haptics:

- **Causality**: fire on the event that caused it (the toggle flipping, the item snapping home).
- **Harmony**: the visual, sound and haptic land on the same frame.
- **Utility**: reserve sound and haptics for meaningful moments (success, error, commit, snap);
  too much trains people to ignore all of it.
