---
bump: patch
---

### Fixed

- **Interview source links pin to a commit SHA.** The surface spoke's Source rule requires a repo-file link of the form `blob/<sha>/<path>`, and `round.py add`, `add-round`, `apply` and `revise` warn (without refusing) on a `blob/<branch>` link in a question's `facts`, naming the question.
