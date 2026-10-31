# Easing and spring terms

How speed changes over an animation, and motion driven by physics instead of a fixed duration. Each
entry gives the term, a definition, and the line between it and the term most often confused with
it.

## Easing: `easing`

### Easing: `easing`

The rate at which an animation speeds up or slows down.

**Versus:** duration is how long an animation takes; easing is how its speed changes over that time.

### Ease-in: `ease-in`

Starts slow, ends fast. Use for things leaving the screen for good, such as a modal closing or a
toast dismissed; a panel that leaves but stays nearby, such as a drawer, exits on the curve it
entered with. On entrances, it feels reluctant.

Web: a custom accelerate curve from the ease-in family, kept short, rather than the bare `ease-in`
keyword.

**Versus:** ease-out starts fast and ends slow, the curve for entrances; ease-in is the curve for a
permanent exit.

### Linear: `linear`

Constant speed. Reserved for spinners, progress fills and marquees.

**Versus:** every eased curve changes speed; linear never does.

### Asymmetric easing: `asymmetric-easing`

A curve that speeds up and slows down at different rates. Real motion is asymmetric, which is why it
reads better than a symmetric curve.

**Versus:** ease-in-out is the symmetric curve; asymmetric easing speeds up and slows down at
different rates.

### Ease-out: `ease-out`

Starts fast, ends slow. The default for most UI and anything responding to the user.

**Versus:** ease-in starts slow and suits only permanent exits; ease-out suits entrances and
responses to input.

### Ease-in-out: `ease-in-out`

Slow, fast, slow. Good for elements already on screen moving from A to B.

**Versus:** ease-out is for things arriving; ease-in-out is for things already on screen moving
between two places.

### Cubic-bezier: `cubic-bezier`

An easing curve you define yourself, with four numbers.

**Versus:** a named easing keyword is a preset; a cubic-bezier is a curve you define.

## Spring animations: `spring-animations`

### Spring: `spring`

Gives you more natural motion by setting tension, mass, and damping instead of a duration.

**Versus:** an eased animation runs for a set duration; a spring settles when its physics say it
has.

### Bounce: `bounce`

A spring loose enough to overshoot its target and wobble back into it.

**Versus:** pop in is an entrance with overshoot; bounce is any spring loose enough to overshoot its
target.

### Velocity: `velocity`

How fast an element is moving and in which direction. Interrupt a spring and it carries that speed
into the next animation instead of starting from zero.

**Versus:** momentum is motion that keeps going after the input stops; velocity is the speed and
direction an element carries at any moment.

### Stiffness, damping & mass: `stiffness-damping-and-mass`

A spring consists of tension, mass, and damping.

Stiffness (tension): how strongly the spring pulls toward its target; higher feels snappier.
Damping: how quickly a spring settles; lower damping means more bounce. Mass: how heavy the element
feels; more mass is slower.

**Versus:** response and damping ratio below are the designer-facing pair some platforms expose
instead of these three.

### Momentum: `momentum`

Motion that carries velocity, especially after a drag or interruption, like a flicked card that
coasts to a halt.

**Versus:** velocity is the speed and direction at one moment; momentum is motion that keeps going
after the input stops.

### Interruptible animation: `interruptible-animation`

An animation you can redirect mid-flight instead of waiting for it to finish.

**Versus:** a keyframed transition usually restarts or finishes first; an interruptible animation
changes course from where it is.

### Damping ratio

Damping as a ratio; 1.0 settles without overshoot, below 1.0 overshoots.

**Versus:** damping is the raw resistance, which depends on stiffness and mass; the damping ratio
expresses it independent of them.

### Response

How quickly the spring tries to reach its target. Each platform maps it to a different parameter;
the platform's docs say which.

**Versus:** stiffness is the raw pull a physics spring is set with; response is the designer-facing
parameter, which platforms express differently.

### Perceptual duration

How long a spring feels finished, though it keeps micro-settling.

**Versus:** a duration ends an eased animation exactly; a spring's perceptual duration is when it
looks done.

## Sources

Response keeps one base definition for every platform; each platform's parameter differs.

- **Pointer**: when a platform's spring parameter matters, fetch https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:), https://developer.android.com/develop/ui/compose/animation/customize#spring and https://motion.dev/docs/spring#visualduration live; correlate with https://developer.apple.com/videos/play/wwdc2018/803/.
- **As of**: 2026-10-28
- **Recheck trigger**: one of those pages renames, adds or redefines a spring parameter.
