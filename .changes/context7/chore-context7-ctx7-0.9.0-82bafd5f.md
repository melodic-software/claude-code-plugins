---
bump: patch
---

### Changed

- `/context7:lookup` documents `ctx7 search`, new in `ctx7` 0.9.0, as an option for questions that span several libraries or name none, used only when the installed CLI lists it. Lookups keep `ctx7 library`, then `ctx7 docs`, as the default: in a three-question comparison the two-step answers stayed inside the chosen library, while `search` saved one call but returned larger output that mixed in mirrors and neighbouring topics.
- The CLI reference replaces the record that said `search` was missing with its current state, and the `MSYS_NO_PATHCONV=1` gotcha now covers `ctx7 search --library /org/project`.
