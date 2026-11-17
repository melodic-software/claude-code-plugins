# HiddenClock

TLC reached 2 states and 2 steps. The chart draws 2 states and 1 arrows.
The chart does not draw 1 steps that stay in one chart state.
With VIEW, TLC keeps one representative for each group of states that it counts as the same. An arrow can lead to the representative rather than to the state that the step reaches.

## EndsAtZero breaks
The cfg has a VIEW. A VIEW can make TLC report a liveness path that the spec does not allow, so check this rule again without the VIEW before you treat it as a bug.
TLC's counterexample is in tlc-EndsAtZero.out. It has 1 step:
```
0. x=0 clock=0
1. Tick: x=1 clock=1
```
The run stops in "x=1 clock=1" forever.
