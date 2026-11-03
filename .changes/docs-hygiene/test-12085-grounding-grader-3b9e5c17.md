---
bump: none
---

The `wfh-grounding-readme` eval case grades grounding with a deterministic regex in place of an LLM judge, which split its votes on READMEs that opened the same way. The first prose sentence that uses `collector`, `checkpoint` or `tail set` must define it, label it, or name it as assumed knowledge; a definition in the next sentence fails. Sample answers, including the openings earlier probes recorded, let `/evals:validate` check the grader offline. No shipped skill text changes, so no release is needed.
