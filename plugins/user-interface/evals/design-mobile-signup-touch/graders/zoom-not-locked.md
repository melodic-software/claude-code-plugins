---
type: llm
arm: both
---
Expectation: "The answer does not lock zoom".

PASS only if no viewport tag or setting the answer proposes carries `maximum-scale` at or below 1
or `user-scalable=no` (or `0`), and nothing in it blocks pinch zoom from script. Saying not to lock
zoom, or quoting a locked tag only to reject it, passes. FAIL if the answer proposes any zoom lock.
