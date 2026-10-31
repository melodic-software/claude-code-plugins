# Motion terms

How things move and transition. Each entry gives the term, a definition, and the line between it and
the term most often confused with it.

Contents: [Motion](#motion-motion), [Entrances and exits](#entrances-and-exits-entrances-and-exits),
[Sequencing and timing](#sequencing-and-timing-sequencing-and-timing), [Movement and
transforms](#movement-and-transforms-movement-and-transforms), [Transitions between
states](#transitions-between-states-transitions-between-states), [Scroll](#scroll-scroll), [Feedback
and interaction](#feedback-and-interaction-feedback-and-interaction), [Polish and
effects](#polish-and-effects-polish-and-effects), [Looping and ambient
motion](#looping-and-ambient-motion-looping-and-ambient), [Principles](#principles-principles).

## Motion: `motion`

### Transition property: `transition-property`

Which properties animate. Animating all properties can accidentally catch layout ones and cause
jank. Opacity and transform are the safe pair.

Web: the CSS `transition-property` list; `transition: all` is the catch-all to avoid.

**Versus:** duration and easing say how long and how a transition runs; transition property says
which properties it covers.

### Choreography: `choreography`

The coordination of multiple elements animating at the same time. When several things move
independently and at different timings, the result is visual noise. Good choreography staggers,
sequences, or groups motion so the eye knows where to look.

**Versus:** orchestration is timing several animations so they read as one motion; choreography is
coordinating them so the eye knows where to look. The two are often used interchangeably; stagger
and sequencing are its tools.

### Shared axis transition: `shared-axis-transition`

When navigating between two related views, the motion direction should reflect the spatial
relationship between them. Moving forward through a flow animates right. Going back animates left.
Violating this creates a sense of spatial disorientation.

**Versus:** a direction-aware transition is the same direction rule for forward and back; a shared
axis transition ties the direction to the spatial relationship between the two views.

### GPU compositing: `gpu-compositing`

Opacity and transform animations run on the GPU and avoid triggering layout recalculation, making
them smooth even on lower-end devices. Animating properties like width, height, padding, or top
forces the engine to recalculate layout on every frame. The performance difference is significant.

**Versus:** compositing in `rendering-performance.md` is the engine step itself; GPU compositing
names the opacity and transform properties that stay on it.

### Reduced motion: `reduced-motion`

A user preference for less animation. Ignoring it can trigger vestibular symptoms. Any significant
movement should check for it.

Web: the `prefers-reduced-motion` media query; respecting it means toning down or removing
animation. iOS and Android expose the same preference as a system accessibility setting the app
reads.

**Versus:** prefers color scheme is the theme preference; reduced motion is the motion preference.
Reducing motion removes movement, not every transition: a fade can stay.

### Enter vs exit asymmetry: `enter-vs-exit-asymmetry`

Entering and exiting animations should not be mirror images of each other. Enter is an arrival and
should decelerate into place. Exit is a departure and should accelerate away. Reversing the enter
animation for the exit makes it feel like content is arriving backwards.

The accelerating exit is for permanent exits; a panel that leaves but stays nearby, such as a
drawer, exits on the curve it entered with (Ease-in in `easing-and-springs.md`).

**Versus:** enter / exit names the two animations; enter versus exit asymmetry says they should not
mirror each other.

### Motion as feedback: `motion-as-feedback`

Using animation to confirm that something happened: a button that compresses on press, a form field
that shakes on invalid input, a checkmark that draws itself on success. The motion is not
decoration, it is the response.

**Versus:** decorative or ambient motion runs on its own; motion as feedback answers an action the
user just took.

## Entrances and exits: `entrances-and-exits`

### Fade in / Fade out: `fade-in-fade-out`

An element appears or disappears by changing opacity. Nothing moves.

**Versus:** a crossfade swaps two elements in one spot; a fade shows or hides one.

### Scale in: `scale-in`

An element grows to full size as it appears, usually with a fade.

**Versus:** pop in overshoots its final size before settling; scale in does not.

### Reveal: `reveal`

A clip-path or mask uncovers the content gradually.

**Versus:** a fade changes opacity of the whole element; a reveal uncovers it gradually with a clip
or mask. Scroll reveal is a reveal triggered by scrolling.

### Slide in: `slide-in`

An element enters from off-screen: left, right, top, or bottom.

**Versus:** translate is the transform that moves it; slide in is the entrance from off-screen.

### Pop in: `pop-in`

An element overshoots its final size before settling, so it looks like it bounced into place.

**Versus:** scale in grows to full size without overshoot; pop in overshoots and settles.

### Enter / Exit: `enter-exit`

The animation an element plays when it's added to or removed from the screen.

**Versus:** a page transition plays between two whole views; enter and exit play when one element is
added or removed.

## Sequencing and timing: `sequencing-and-timing`

### Keyframes: `keyframes`

Points you define along an animation (0%, 50%, 100%). The engine fills in everything between them.

Web: CSS `@keyframes`.

**Versus:** interpolation is the in-between frames the engine generates; keyframes are the points
you set.

### Stagger: `stagger`

Several items animate one after another, each a few milliseconds behind the last.

**Versus:** a delay holds one animation; a stagger offsets each item in a group from the last.

### Delay: `delay`

Time before an animation starts.

**Versus:** duration is how long the animation runs; delay is the wait before it starts.

### Stepped animation: `stepped-animation`

An animation that jumps between fixed steps instead of moving continuously, like a countdown timer.

**Versus:** interpolation moves continuously between values; a stepped animation jumps between them.

### Interpolation / Tween: `interpolation-tween`

The engine generates every frame between a start value and an end value, so the motion is
continuous.

Web: the browser interpolates CSS transitions and animations.

**Versus:** keyframes are the points you define; interpolation fills the frames between them.

### Orchestration: `orchestration`

Timing several animations so they read as one motion instead of several.

**Versus:** a stagger offsets items by a fixed step; orchestration times several different
animations into one motion. Choreography in this file is the near-synonym that stresses where the
eye goes.

### Duration: `duration`

How long an animation takes.

**Versus:** delay is the wait before the animation starts; duration is how long it runs once
started.

### Fill mode: `fill-mode`

Whether an element keeps the animation's first or last frame before it starts or after it ends. Set
forwards and it holds the last one.

**Versus:** delay is how long the animation waits; fill mode is what the element shows during that
wait and after the end.

## Movement and transforms: `movement-and-transforms`

### Translate: `translate`

Move an element along the X, Y or Z axis.

**Versus:** slide in is the entrance that uses it; translate is the move itself.

### Rotate: `rotate`

Spin an element around a point.

**Versus:** 3D tilt / flip rotates out of the screen plane; rotate spins within it.

### 3D tilt / Flip: `3d-tilt-flip`

Rotate in 3D space to add depth.

Web: `rotateX` and `rotateY`.

**Versus:** rotate spins within the screen plane; 3D tilt and flip rotate out of it.

### Transform origin: `transform-origin`

The anchor point a scale or rotation grows or spins from.

**Versus:** origin-aware animation sets the origin at the trigger; transform origin is the anchor
point itself.

### Scale: `scale`

Make an element bigger or smaller.

**Versus:** scale in is the entrance that uses it; scale is the size change itself.

### Skew: `skew`

Slant an element along the X or Y axis, so its corners stop being right angles.

**Versus:** rotate turns the whole shape; skew slants it so its corners stop being right angles.

### Perspective: `perspective`

How strong the 3D effect looks. A lower value exaggerates depth, as if the viewer is closer.

**Versus:** 3D tilt is the rotation; perspective is how strong the depth of that rotation looks.

### Origin-aware animation: `origin-aware-animation`

An element animates out of whatever triggered it. A popover grows from the button that opened it,
not from its own center, which is where a scale grows from by default.

Web: CSS scales from the element's center unless `transform-origin` is set.

**Versus:** scale in grows from the element's own center; origin-aware animation grows from its
trigger.

## Transitions between states: `transitions-between-states`

### Crossfade: `crossfade`

One element fades out as another fades in, in the same spot.

**Versus:** a morph turns one shape into another; a crossfade fades one element out as another fades
in.

### Morph: `morph`

One shape turns into another, like the Dynamic Island.

**Versus:** a crossfade swaps two elements by opacity; a morph turns one shape into another.

### Layout animation: `layout-animation`

When an element's size or position changes, it animates to the new spot instead of snapping.

**Versus:** a shared element transition moves an element between two views; a layout animation moves
it within one when its size or position changes.

### Direction-aware transition: `direction-aware-transition`

Content slides one way going forward and the opposite way going back, so navigation has a sense of
direction.

**Versus:** a shared axis transition is the same rule tied to the spatial relationship between
views; a direction-aware transition only reverses for back.

### Continuity transition: `continuity-transition`

A change that connects before and after, so nobody loses the thread. The same rectangle growing and
shrinking, rather than one swapping for another.

**Versus:** a crossfade swaps one element for another; a continuity transition keeps the same
element changing.

### Shared element transition: `shared-element-transition`

An element travels and transforms from one position into another, like a thumbnail expanding into a
card.

**Versus:** a layout animation stays within one view; a shared element transition carries an element
across two.

### Accordion / Collapse: `accordion-collapse`

A section animates its height open and closed to show or hide content.

**Versus:** Accordion in `components.md` is the component; this is the height animation it plays.

## Scroll: `scroll`

### Scroll reveal: `scroll-reveal`

Elements fade or slide into place as they enter the viewport.

**Versus:** a scroll-driven animation ties progress to scroll position; a scroll reveal plays once
as the element enters the viewport.

### Page transition: `page-transition`

An animation that plays when navigating from one page or route to another.

**Versus:** a view transition is the platform mechanism one page transition can use; a page
transition is any animation between pages.

### Scroll-driven animation: `scroll-driven-animation`

An animation whose progress is tied to scroll position.

**Versus:** a scroll reveal triggers once on entering the viewport; a scroll-driven animation tracks
scroll position continuously.

### View transition: `view-transition`

The platform's transition between two states or pages; elements given a `view-transition-name`
morph from their old state to their new one.

Web: the View Transitions API.

**Versus:** a shared element transition is the effect; a view transition is the platform mechanism
that can produce it.

### Parallax

Background and foreground move at different speeds while scrolling.

**Versus:** a scroll-driven animation is any animation tied to scroll position; parallax is the
depth effect of layers moving at different speeds.

## Feedback and interaction: `feedback-and-interaction`

### Hover effect: `hover-effect`

Visual change when the cursor moves over an element.

**Versus:** Hover state in `interaction.md` is the state; a hover effect is the motion or visual
change it plays.

### Hold to confirm: `hold-to-confirm`

A progress indicator that fills while the user holds a button down.

**Versus:** a confirmation dialog asks with a prompt; hold to confirm asks with a sustained press.

### Ripple: `ripple`

A circle expanding from the point of a tap, confirming the press.

**Versus:** press / tap feedback scales the element; a ripple spreads a circle from the touch point.

### Press / Tap feedback: `press-tap-feedback`

A small scale-down while an element is held down, confirming the press.

**Versus:** a ripple spreads from the touch point; press feedback scales the element itself. Active
state in `interaction.md` is the state it signals.

### Shake / Wiggle: `shake-wiggle`

A quick side-to-side jitter signaling an error or rejected input.

**Versus:** a pulse repeats to draw attention; a shake plays once to reject an input.

### Drag

Moving an element by grabbing it, often with momentum on release.

**Versus:** swipe to dismiss is a drag that ends by closing the element; drag is any grab and move.

### Drag to reorder

Dragging list items to rearrange them while the others shift to make room.

**Versus:** a layout animation is the motion the other items play as they shift; drag to reorder is
the interaction.

### Swipe to dismiss

Dragging an element off-screen to close it, like a drawer or toast.

**Versus:** rubber-banding resists a drag past a boundary and snaps back; swipe to dismiss lets it
leave.

### Rubber-banding

Resistance and snap-back when a drag goes past a boundary.

**Versus:** bounce is a spring overshooting its target; rubber-banding is resistance while the drag
is still held.

## Polish and effects: `polish-and-effects`

### Blur: `blur`

A blur filter that softens an element, or hides the moment two states overlap.

**Versus:** a mask hides parts of an element; a blur softens all of it.

### Mask: `mask`

Hide or reveal parts of an element with a shape or gradient. Like clip-path, except the edge can
fade.

**Versus:** a clip-path cuts to a hard-edged shape; a mask can fade at the edge.

### Skeleton / Shimmer: `skeleton-shimmer`

A placeholder with a moving sheen shown while content loads.

**Versus:** Skeleton in `components.md` is the placeholder component; the shimmer is the moving
sheen on it. A spinner shows waiting without the content's shape.

### Tabular numbers: `tabular-numbers`

Fixed-width digits, so a number doesn't jitter as it changes. Any timer or counter needs them.

**Versus:** Tabular nums in `typography.md` is the same font feature named for tables; a number
ticker is the rolling animation the digits play.

### Clip-path: `clip-path`

Clip an element to a shape. Animate the shape and you get a reveal or a wipe.

**Versus:** a mask can fade at its edge; a clip-path edge is hard. Also called a clip.

### Before / after slider: `before-after-slider`

A draggable divider that wipes between two overlaid images to compare them.

**Versus:** a carousel moves between items; a before / after slider wipes between two overlaid
images.

### Number ticker: `number-ticker`

Digits rolling or counting up to a value.

**Versus:** tabular numbers keep each digit's width fixed; a number ticker is the rolling animation
itself.

### Typewriter: `typewriter`

Text appearing one character at a time, as if being typed.

**Versus:** a text morph animates text that changes; a typewriter reveals text one character at a
time.

### Line drawing

A vector path that draws itself in.

**Versus:** a reveal uncovers a finished shape with a clip or mask; line drawing traces the path
itself.

### Text morph

Text that animates character by character when it changes.

**Versus:** a typewriter reveals new text one character at a time; a text morph animates text that
changes from one value to another.

## Looping and ambient motion: `looping-and-ambient`

### Marquee

Content that scrolls continuously in a loop.

**Versus:** a carousel moves between items on input; a marquee scrolls by itself without stopping.

### Loop

An animation that repeats, a set number of times or forever.

**Versus:** alternate is a loop that reverses each iteration; a plain loop restarts from the
beginning.

### Alternate (yoyo)

A loop that plays forward then reverses each iteration.

**Versus:** a plain loop jumps back to the start; alternate plays the way back.

### Orbit

An element circling another on a continuous path.

**Versus:** rotate spins an element around its own point; an orbit moves it around another element.

### Pulse

A gentle repeating scale or opacity change to draw attention.

**Versus:** a shake plays once to reject input; a pulse repeats to draw attention.

### Float

A gentle, continuous drift that makes a static element feel weightless.

**Versus:** a pulse changes scale or opacity in place; a float drifts position.

### Idle animation

Subtle motion while an element waits to be used.

**Versus:** a loading animation says something is in progress; an idle animation plays while nothing
is.

## Principles: `principles`

### Purposeful animation

Motion serves a function (orient, give feedback, show relationships), not decoration.

**Versus:** motion as feedback is one purpose; purposeful animation is the rule that every motion
has one.

### Anticipation

A small wind-up in the opposite direction before a move.

**Versus:** follow-through happens after the move; anticipation before it.

### Follow-through

Parts keep moving and settle slightly after the main motion stops.

**Versus:** anticipation happens before the move; follow-through after it.

### Squash and stretch

Deforming an element as it moves to convey weight and speed.

**Versus:** skew slants an element at rest; squash and stretch deforms it in motion.

### Perceived performance

The right animation makes an interface feel faster than it is.

**Versus:** frame rate is measured speed; perceived performance is how fast it feels.

### Frequency of use

The more often an animation is seen, the shorter and subtler it should be.

**Versus:** duration is one animation's length; frequency of use is the rule for choosing it.

### Spatial consistency

An element keeps its identity and position across states, so users never lose track of it.

**Versus:** a continuity transition is one technique; spatial consistency is the rule it serves.

## Sources

View transition names the platform mechanism without stating its default animation.

- **Pointer**: when a view transition's default animation matters, fetch https://www.w3.org/TR/css-view-transitions-1/#propdef-view-transition-name live.
- **As of**: 2026-10-28
- **Recheck trigger**: the specification changes its default animation or the `view-transition-name` property.

Reduced motion names the platform preference the project reads.

- **Pointer**: when the web preference's values matter, fetch https://www.w3.org/TR/mediaqueries-5/#prefers-reduced-motion live.
- **As of**: 2026-10-28
- **Recheck trigger**: the media feature's values change.
