---
bump: patch
---

### Fixed

- `/evals:plugin-eval` run-validity counts a tool result's sandbox `deny network-outbound <host>:<port>` violation as a permission denial and names the denied hosts in the summary: a with-arm one is a FAIL, a without-arm one takes the ordinary denial rules, and one in an invocation-probe or control case is a warning
