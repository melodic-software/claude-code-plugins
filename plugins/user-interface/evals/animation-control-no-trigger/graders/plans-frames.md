---
type: llm
arm: both
---
PASS only if the answer gives a frame count for the walk cycle and says what changes across the
frames (for example legs, arms, a body bob). FAIL if it gives no frame count, or describes only
interface motion, easing or code instead of the character's frames.

Examples:

- PASS: "Use 4 frames: contact, down, passing, up, with the sword arm swinging opposite the legs."
- FAIL: "Use an ease-out curve over 200ms."
