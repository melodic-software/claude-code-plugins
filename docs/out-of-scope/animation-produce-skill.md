# animation produce skill

Build-later park for
[#4591](https://github.com/melodic-software/claude-code-plugins/issues/4591).

## Decision

**Park. No code.** `/animation:produce` stays unbuilt backlog. The plugin
keeps rotoscope, learn-style, and setup.

**Claim:** the produce skill (brief to boards to delivered film) is
build-later design; this pass does not run `/planning:design` and does not
add a skill.
**Basis:** #4591 (`needs-human`, `priority: medium`). Opened by #4534 as the
next design task after the animation plugin shipped. `plugins/animation/README.md`
already says "Planned next: produce". `plugins/animation/skills/` has
learn-style, rotoscope, and setup only. The issue's out-of-scope line:
learn-style's `## Next` naming `/animation:produce` lands when the skill
ships, not before. Pixel-art #4403-#4406/#4402, woodcut #4507, and Fable
#4346 are out of this record.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds `/planning:design` for produce (field-level
schemas, the approval gate, and how review reads `shots.json` and
`render.json`) and unparks #4591.

## Rationale

- The Brief is a design task, not an implementation brief.
- Shipping produce without the design the issue asks for would invent
  schemas the issue reserved for `/planning:design`.
- learn-style has no `## Next` today; adding one that names a missing skill
  is the issue's own non-goal.

## Revisit when

- A maintainer funds the produce design pass, or
- Unparks #4591 as an attended `/planning:design` session.

## Prior requests

- #4591 (2026-09-28): produce skill design; Option A build-later park.
