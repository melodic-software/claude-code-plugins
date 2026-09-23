# Animation craft

One rule per line, source in brackets. "(judgment)" marks a rule no source states;
"(single source)" marks a rule only one practitioner states.

Sources: Saint11 tutorial images at `https://saint11.art/img/pixel-tutorials/<Name>.gif`
([index](https://saint11.art/blog/pixel-art-tutorials/)),
[Slynyrd 8](https://www.slynyrd.com/blog/2018/8/19/pixelblog-8-intro-to-animation),
[Slynyrd 9](https://www.slynyrd.com/blog/2018/9/8/pixelblog-9-melee-attacks),
[Slynyrd 41](https://www.slynyrd.com/blog/2022/11/28/pixelblog-41-isometric-pixel-art),
[Slynyrd 50](https://www.slynyrd.com/blog/2024/5/24/pixelblog-50-human-walk-cycle),
[Slynyrd 55](https://www.slynyrd.com/blog/2025/3/24/pixelblog-55-top-down-character-animation),
[Pixel Logic](https://archive.org/stream/pixel-logic-a-guide-to-pixel-art-michael-azzi/Pixel%20logic%20a%20guide%20to%20pixel%20art%20-%20Michael%20Azzi_djvu.txt).

## General

- Key poses first; time with holds and cut frames, not more frames. [Slynyrd 8; Saint11 Impact]
- Removing frames means lengthening the rest to keep the cycle duration. [Slynyrd 8]
- Keep clusters intact between frames. [Saint11 Fundamentals]
- Consistency of frame counts across the cast matters more than the numbers. [Slynyrd 8]
- Only run cycles have sourced per-frame milliseconds; every other ms value below is judgment.

## Idle

- 2 frames is a complete idle: body down 1px with knees bent and arms open, then up 1px with arms
  down; mass never changes. [Saint11 characterIdle]
- A 3rd middle frame slows the fall and smooths the transition. [Saint11 characterIdle]
- 6+ frames add secondary motion (hair lag) and sub-pixel movement. [Saint11 characterIdle]
- Range 2-8 frames by scope. [Slynyrd 8]
- Move face and body contents one frame after the silhouette; pair vertical with some horizontal
  motion. [Saint11 characterIdle]
- Personality beats (blink, look around) as occasional variants. [Saint11 characterIdle]
- Timing: 150-250 ms per frame; hold the low frame longer (judgment).

## Walk

- Default pose names (Saint11, 6 key poses of a 12-frame cycle): contact, down, down+ (lowest,
  widest arms), prepare-passing, passing, up (highest point); mirror for the other leg.
  [Saint11 Walk]
- Alternative (Slynyrd, 4 poses of an 8-frame cycle): contact, down, pass (tallest), swing;
  frames 5-8 mirror 1-4. [Slynyrd 50] The sources disagree on which pose is highest; templates use
  Saint11 names.
- Arms swing with the opposite leg; the planted leg always moves back. [Saint11 Walk]
- Head path is a triangle wave, not a sine. [Slynyrd 50]
- Frame counts: 12 fluid, 8 balanced, 6 low-res (3 per leg), 4 key poses only. [Saint11 Walk;
  Slynyrd 50]
- Mirrored halves need per-frame fixes for asymmetric clothing. [Slynyrd 50]
- Top-down walk: 6 frames, draw 3 and flip for the other leg. [Saint11 TopDownWalkCycle]
- Timing: about 100 ms per frame at 8 frames (judgment); RPG Maker MZ uses its own 0-1-2-1 timing
  (`engine-layouts.md`).

## Run

- Contact and pass are the keyframes never cut; stride poses extend limbs and lean forward.
  [Slynyrd 8]
- 6-frame cycles work in most cases. [Slynyrd 8]
- Simple run: 4 poses (both feet off, fall, contact with straight leg, recover) per leg = 8 frames.
  [Saint11 RunCycleSimple]
- Timing: 8 frames at 80 ms each, or 4 frames at 160 ms each. [Slynyrd 8]
- Top-down 6-frame bob per stride: down 1px, down 1px, up 2px. [Slynyrd 55]

## Attack

- Phases: stance, anticipation, strike (smear), impact, recovery. [Slynyrd 9]
- Player attacks: no or minimal anticipation, or the input feels laggy. [Saint11 AttackSheet;
  Slynyrd 9]
- Cut in-betweens between rest and target and add a smear for a faster, stronger hit.
  [Saint11 Impact]
- Hold at impact briefly (a few frames); hold follow-through slightly longer. [Slynyrd 9;
  Saint11 Impact]
- Recovery can be longer than the strike; the last recovery frame may bounce past the rest pose.
  [Saint11 AttackSheet]
- Example budget: 3 attack frames, 4 back to idle. [Saint11 AttackSheet]
- Enemies and cinematics: full anticipation to telegraph (judgment).
- Timing: strike frames 40-60 ms, impact hold 100-150 ms (judgment).

## Jump (single source: Saint11 Jump)

- Two variants: up (x-speed 0) and forward (x-speed > 0).
- Phases: anticipation (skip for player control), going up, invert (apex bridge as y-speed changes
  sign), fall (arms up, hair and cloth flap), contact (squash hard; may be long and interruptible).
- Add dust on takeoff and landing.

## Hurt (single source: Saint11 Death/Take hit)

- Impact is one frame with the right easing; overshoot the first frame; recover slowly to idle.
- Small enemies: squish (conserve mass), compress, or one black contrast frame.
- White flash, knockback distance, invulnerability blink: unsourced; treat as judgment.

## Death (single source: Saint11 Death/Take hit)

- Strongest frame first (impact throws the body back), partial recovery, give up (knees bend, arms
  and head lag), hit ground (overshoot 1px down, arms bounce), rest; fade effects slowly.

## Squash and stretch (single source: Saint11 Squash)

- Mass never changes: narrower means taller, wider means shorter.
- Preparation squashes opposite to the action; stiff materials deform less.
- Stretch cheaply smooths fast motion; tween squash in game code too.
- At low resolution these are 1-2px changes (judgment).
- Overshoot: a stopping object passes its stop point slightly before settling. [Slynyrd 9]

## Smears

- Few and fast: a non-keyframe blurred to show motion. [Slynyrd 9]
- Connect the smear to the previous frame; lighter colours bleed over darker. [Saint11 MotionBlur]
- With limited palettes, lines work as smears. [Pixel Logic]
- Show a smear for one frame at the cycle's fastest timing (judgment).

## Sub-pixel animation

- Fake sub-pixel motion by shifting colour and value: fade colours, slide line-break points, move
  the interior not the silhouette. [Saint11 Subpixel]
- Too many colours make it blurry. [Saint11 Subpixel]
- Advanced and not always necessary. [Pixel Logic]

## Directions

- 4 directions still allow 8-way movement with limited facing. [Slynyrd 55]
- 8 directions: 5 unique facings when symmetric (3 mirrored), all 8 when gear or hair is
  asymmetric. [Slynyrd 55]
- Top-down layering: feet behind legs, legs behind torso, torso behind head. [Saint11 TopDownWalkCycle]
- Choose 4 on a tight budget or cardinal-grid combat, 8 when diagonal aiming is a mechanic
  (judgment).

## Mirroring

- Mirror only symmetric designs; asymmetric gear, hair, or handedness need unique frames or accept
  swapped hands. [Slynyrd 55; Slynyrd 50; Saint11 TopDownWalkCycle]
- Swapped sword and shield hands pass in play but look wrong in a standing rotation. [Slynyrd 55]
- Mirroring also flips the light direction (top-left becomes top-right); repaint highlights or
  keep the light overhead for mirrored sets (judgment).

## Isometric 2:1

- Lines go 2 pixels across per 1 up (about 26.5 degrees), not a true 30 degrees.
  [Saint11 Isometric; Slynyrd 41]
- Vertical lines stay vertical. [Saint11 Isometric] (single source)
- Build from cuboids and carve; even dimensions help. [Saint11 Isometric; Slynyrd 41]
- Animate on the same 2:1 grid: move 2px across per 1px vertical so motion stays on the lines
  (judgment).
