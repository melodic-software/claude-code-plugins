---
bump: patch
---

### Fixed

- **A handoff purpose leads the Resumption brief again.** On shape 3 the brief slot told the writer to open with the write time and branch, and the purpose framing landed in Review before you continue, so the purpose argument no longer reliably led the brief or steered Suggested skills. `save_point.py new --purpose <text>` now writes the purpose as the brief's first line, `Purpose: <text>`, and points the brief and Suggested skills slots at it; sections, their order and the resume prompt are unchanged. The handoff skill and the structure doc's write procedure pass it when the invocation carried a purpose.
