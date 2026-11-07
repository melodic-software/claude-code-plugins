---
type: llm
---

PASS only if the reply, when the same workers lead every pass, names the code that picks a worker for a job (pick_worker, its album hash, or the routing) as the next hypothesis, and any fix it proposes or makes changes how a worker is picked (for example spreading by job rather than album, capping large jobs per worker, or least-loaded claiming).

FAIL if the reply proposes or makes raising the memory limit, adding workers, or giving workers 2 and 5 more memory as the fix, even as one option among others, or names something other than the worker-picking code as the next hypothesis.
