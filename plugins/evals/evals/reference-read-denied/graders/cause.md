---
type: llm
arm: both
---

PASS if the answer says both:

1. Fence: the eval run refuses reads under the plugin's own directory whatever the case's Read grant (the grant covers the tool, not that path).
2. Hub only: only the hub `SKILL.md` text (the injected skill body) reaches the model.

FAIL if either is missing; if the answer blames a deny rule in the user's settings, file permissions, or a relative path; if it says adding Read to `allowed_tools`, `context.add_dirs`, or an `--allow-tools` Read grant fixes it; or if it later contradicts or retracts this. Saying a path-scoped `--allow-tools` Read grant does not lift the denial is correct, and so is saying spoke reads (`context/`, `reference/` and the like) succeed at 2.1.289.
