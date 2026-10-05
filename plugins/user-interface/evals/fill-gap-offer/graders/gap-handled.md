---
type: llm
arm: both
---
PASS only if the answer (1) notices the project has no shared tokens or design-system file and its
colors are hard-coded per component, (2) reuses the values already in the components where they fit
(for example the error red #C62828 and the success green #2E7D32), and (3) offers to create a shared
token or theme file, or a short design note, and asks before doing it. FAIL if it ignores the
existing values and invents an unrelated palette, or never offers to create the shared piece.
