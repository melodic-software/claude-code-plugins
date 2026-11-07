---
type: llm
arm: both
---
Expectation: "The answer names at least two motion terms that carry the feel, such as duration,
ease-out, easing or spring stiffness".

PASS only if the reply names at least two distinct motion terms that carry the feel, such as a
duration, an ease-out curve, easing, or spring stiffness. Any two count; a duration is not
required. FAIL if it names fewer than two, or names only general words such as "faster" or
"smoother".

Examples:

- PASS: "Ask for a shorter duration (about 150ms) and an ease-out curve."
- PASS: "Ask for an ease-out curve and a stiffer spring (higher stiffness)."
- FAIL: "Make it faster and smoother."
