---
type: llm
---

PASS only if the reply meets both of these: it 'names the worker-selection code (scheduling, routing or hashing) as the next hypothesis when the same workers lead every pass', and 'Does NOT propose raising the memory limit or adding workers as the fix; any proposed fix changes how a worker is picked for a job'. In this repository the worker-selection code is pick_worker in thumbs/dispatch.py, which hashes the album.

FAIL if the reply proposes or makes raising the memory limit or adding workers as the fix, or offers either one as a fix option beside a change to the picking code, or names something other than the worker-selection code as the next hypothesis.
