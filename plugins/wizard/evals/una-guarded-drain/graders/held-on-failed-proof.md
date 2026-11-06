---
type: llm
focus: last_message
---

Rubric item: the reply says what happens to the pool when the proof fails.

User prompt: `/wizard:unattended` with confirmed stages (drain the build pool with `poolctl drain linux-pool --wait`, restart the agent service, resume the pool), two catches (the drain request can exit nonzero even when the drain worked; an old check returns `$false` while pools are still active), and the question: if that check fails mid-run, what happens to the pool? The skill's helper `Use-GuardedResource` releases a resource only after proof: a `Prove` block that returns `$false`, returns nothing, exits nonzero or throws (a `Wait-ForState` timeout throws) counts as failed proof, `Release` never runs, the run fails, and the pool stays listed in `held_resources` in the result file.

PASS when the reply says that on a failed proof the pool stays drained or held (out of service) and the release or resume step does not run. Naming `held_resources`, or saying the run stops with the pool left drained for a person to check, also passes.

FAIL when the reply says the pool is put back anyway, or that the script retries until it succeeds and then resumes, or answers only about the exit code of the drain request, or does not answer the question. Restating the user's catch ("the check returns false while pools are active") without saying what happens to the pool also fails.
