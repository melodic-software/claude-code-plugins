# Animation glossary

Names for motion effects, so a request, a review finding or a prompt can say exactly what it means.
The terms are platform-neutral: each names what the eye sees, not an API. To build one, read
`catalog.md` and `behaviors.md` in this folder and look up the project stack's own way of doing it.
The project's design system and docs override this file: when they already name an effect, use
their name.

Contents: `name-the-effect`, `entrances-and-exits`, `sequencing-and-timing`,
`movement-and-transforms`, `transitions-between-states`, `scroll`, `feedback-and-interaction`,
`easing`, `springs`, `looping-and-ambient`, `polish`, `performance-terms`, `principles`.

## Name the effect: `name-the-effect`

When someone describes an effect loosely ("the bouncy thing when a popover opens", "the stretchy
overscroll at the end of a list"), read for the sensation, not the keywords, and answer with the
term below. Lead with the best match; when two terms compete, name one or two alternates and say
how they differ (clip-path versus mask, pop in versus bounce, shared element transition versus
layout animation). When nothing here fits, name the closest term and say it is an approximation, or
describe the effect in these words ("a stagger of scale-in entrances"). Do not invent a term.

## Entrances and exits: `entrances-and-exits`

- **Fade in / fade out**: the element appears or disappears by changing opacity.
- **Slide in**: the element enters from off-screen (left, right, top or bottom).
- **Scale in**: the element grows from slightly smaller to full size as it appears, often with a
  fade.
- **Pop in**: the element appears with a slight overshoot, as if it bounces into place.
- **Reveal**: content is uncovered gradually, often by animating a clip or mask.
- **Enter / exit**: the animation an element plays when it is added to or removed from the screen.

## Sequencing and timing: `sequencing-and-timing`

- **Keyframes**: defined points in an animation (0%, 50%, 100%) that the engine fills in between.
- **Interpolation / tween**: generating the in-between frames from a start value to an end value.
- **Stagger**: several items animate one after another with a small delay between each, a cascade.
- **Orchestration**: timing several animations so they read as one coordinated motion.
- **Delay**: time before an animation starts.
- **Duration**: how long an animation takes.
- **Fill mode**: whether an element keeps its first or last frame before the animation starts or
  after it ends.
- **Stepped animation**: an animation divided into discrete steps, like a countdown.

## Movement and transforms: `movement-and-transforms`

- **Translate**: move an element along an axis.
- **Scale**: make an element bigger or smaller.
- **Rotate**: spin an element around a point.
- **Skew**: slant an element along an axis, shearing it out of its rectangle.
- **3D tilt / flip**: rotate in 3D space to add depth.
- **Perspective**: how strong the 3D effect looks; a lower value exaggerates depth.
- **Transform origin**: the anchor point a scale or rotation grows or spins from.
- **Origin-aware animation**: an element animates out of its trigger, like a popover growing from
  the button that opened it instead of from its own center.

## Transitions between states: `transitions-between-states`

- **Crossfade**: one element fades out as another fades in, in the same spot.
- **Continuity transition**: a change that keeps the user oriented by visually connecting before
  and after, such as the same rectangle growing and shrinking.
- **Morph**: one shape smoothly turns into another.
- **Shared element transition**: an element travels and transforms from one position into another,
  like a thumbnail expanding into a card.
- **Layout animation**: when an element's size or position changes, it animates to the new spot
  instead of snapping.
- **Accordion / collapse**: a section expands and collapses its height to show or hide content.
- **Direction-aware transition**: content moves one way going forward and the opposite way going
  back, so navigation has a direction.

## Scroll: `scroll`

- **Scroll reveal**: elements fade or slide into place as they enter the viewport.
- **Scroll-driven animation**: an animation whose progress is tied to scroll position.
- **Parallax**: background and foreground move at different speeds while scrolling.
- **Page transition**: an animation that plays when navigating from one page or screen to another.
- **View transition**: the platform morphs between two states or pages, connecting shared elements.

## Feedback and interaction: `feedback-and-interaction`

- **Hover effect**: a visual change when a pointer moves over an element.
- **Press / tap feedback**: a subtle scale-down when an element is pressed, so it feels physical.
- **Hold to confirm**: a progress fill that grows while the user holds a control.
- **Drag**: moving an element by grabbing it, often with momentum on release.
- **Drag to reorder**: dragging list items to rearrange them while the others shift to make room.
- **Swipe to dismiss**: dragging an element off-screen to close it, like a drawer or toast.
- **Rubber-banding**: resistance and snap-back when a drag goes past a boundary.
- **Shake / wiggle**: a quick side-to-side jitter signaling an error or rejected input.
- **Ripple**: a circle expanding from the point of a tap, confirming the press.

## Easing: `easing`

- **Easing**: the rate at which an animation speeds up or slows down.
- **Ease-out**: starts fast, ends slow. The default for most interface motion and anything
  responding to the user.
- **Ease-in**: starts slow, ends fast. Usually avoided; reads as lag.
- **Ease-in-out**: slow, fast, slow. For elements already on screen moving from one place to another.
- **Linear**: constant speed. Reserved for spinners, progress fills and marquees.
- **Cubic Bézier**: a custom easing curve defined by four control-point numbers.
- **Asymmetric easing**: a curve that accelerates and decelerates at different rates.

## Springs: `springs`

- **Spring**: motion driven by physics (stiffness, mass, damping) rather than a set duration.
- **Stiffness / tension**: how strongly the spring pulls toward its target; higher feels snappier.
- **Damping**: how quickly a spring settles; lower damping means more bounce.
- **Damping ratio**: damping as a ratio; 1.0 settles without overshoot, below 1.0 overshoots.
- **Response**: how quickly a spring reaches its target, the designer-facing stand-in for
  stiffness; not a duration.
- **Mass**: how heavy the element feels; more mass is slower.
- **Bounce**: a spring that overshoots and settles.
- **Perceptual duration**: how long a spring feels finished, though it keeps micro-settling.
- **Momentum**: motion that carries velocity, especially after a drag or interruption.
- **Velocity**: how fast and in which direction an element moves; a spring carries it into the next
  animation when interrupted.
- **Interruptible animation**: an animation that can be redirected mid-flight instead of finishing
  first.

## Looping and ambient motion: `looping-and-ambient`

- **Marquee**: content that scrolls continuously in a loop.
- **Loop**: an animation that repeats, a set number of times or forever.
- **Alternate (yoyo)**: a loop that plays forward then reverses each iteration.
- **Orbit**: an element circling another on a continuous path.
- **Pulse**: a gentle repeating scale or opacity change to draw attention.
- **Float**: a gentle, continuous drift that makes a static element feel weightless.
- **Idle animation**: subtle motion while an element waits to be used.

## Polish and effects: `polish`

- **Blur**: a blur filter that softens an element or masks a small imperfection.
- **Clip**: cutting an element to a shape, for reveals and before/after sliders.
- **Mask**: hiding or revealing parts of an element with a shape or gradient; like a clip, with soft
  edges.
- **Before / after slider**: a draggable divider that wipes between two overlaid images.
- **Line drawing**: a vector path that draws itself in.
- **Text morph**: text that animates character by character when it changes.
- **Skeleton / shimmer**: a placeholder with a moving sheen while content loads.
- **Number ticker**: digits rolling or counting up to a value.
- **Tabular numbers**: fixed-width digits, so numbers do not shift as they change.
- **Typewriter**: text appearing one character at a time.

## Performance terms: `performance-terms`

- **Frame rate**: frames drawn per second; the display's refresh rate sets the budget per frame.
- **Jank**: visible stutter when frames are dropped.
- **Dropped frame**: a frame that missed its deadline, a small hitch in motion.
- **Compositing**: moving or fading an element on its own layer without redoing layout or paint.
- **Layer promotion hint**: telling the engine ahead of time that an element will animate, so it can
  give it its own layer.
- **Layout thrashing**: animating properties that force layout every frame.

## Principles: `principles`

- **Purposeful animation**: motion serves a function (orient, give feedback, show relationships),
  not decoration.
- **Anticipation**: a small wind-up in the opposite direction before a move.
- **Follow-through**: parts keep moving and settle slightly after the main motion stops.
- **Squash and stretch**: deforming an element as it moves to convey weight and speed.
- **Perceived performance**: the right animation makes an interface feel faster than it is.
- **Frequency of use**: the more often an animation is seen, the shorter and subtler it should be.
- **Spatial consistency**: an element keeps its identity and position across states, so users never
  lose track of it.
- **Reduced motion**: honoring the user's request to reduce motion by removing movement.
