---
type: llm
arm: both
---
PASS only if the rewritten section keeps all three rules (no token values printed, read before edit, keep a file's existing indentation when editing) as instructions and none of them carries an added justification: no "because", "since", "so that", "why:", or a clause explaining the risk. Rewording, reordering or merging the rules passes. FAIL if any rule gains a reason or explanation, or if any rule is dropped or weakened.
