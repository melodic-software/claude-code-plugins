---
type: llm
arm: both
---
PASS only if the card's entrance when a message arrives settles with no overshoot (`bounce: 0`, a
damping ratio of 1 or a critically damped stiffness and damping pair, or a tween with no overshoot),
and any overshoot appears only on the snap-back after a drag release, where it stays subtle:
`bounce` at most 0.3, or a damping ratio of 0.7 or more. A snap-back with no bounce also passes.
FAIL if the entrance overshoots, if the release snap-back's bounce exceeds 0.3 (or its damping ratio
is under 0.7), if the springs appear only in prose, or if the reply contains no code.
