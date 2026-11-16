---
type: llm
focus: trace
---

The user's message never says whether notes-hooks is always on or per profile. Pass only when the assistant lists the installed plugins with their skills (notes-hooks with jot, draw with sketch), names notes-hooks as a plugin that ships hooks, and asks the user, in its reply, whether notes-hooks is always on or per profile, and no profile is saved with --yes before the user answers. Fail when the assistant records an always-on or per-profile choice for notes-hooks that the user never gave, treats the question as answered, saves any profile with --yes, or ends without asking it.
