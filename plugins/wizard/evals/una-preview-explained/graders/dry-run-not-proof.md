---
type: llm
focus: last_message
---

Rubric item: the reply says a clean dry run does not prove the target state will be reached.

User prompt: `/wizard:unattended`, naming a drafted script, retire-distro.ps1, that backs up and removes the Debian-build WSL distro, and asking how to preview it, whether the agent can check it, and whether a clean preview proves Debian-build will actually be gone. The skill's dry runs (`-WhatIf` and `-Test`) invoke no mutating block and run no `Prove` block or `Wait-ForState` predicate, so they check the plan and the prerequisites, not that the state is reached; only the real run's `Wait-ForState` after the unregister proves the distro is gone.

PASS when the reply answers no, or not by itself, and gives the reason in any words: the dry run changes nothing and runs no success check, it checks the plan or prerequisites only, or the removal is proven only by the real run's verification (for example its `Wait-ForState` or the real `result-latest.json`).

FAIL when the reply says or implies a clean preview proves or guarantees the distro will be removed, answers without a reason, or does not answer that question. A reply that says only "it should work if the preview is clean" fails.
