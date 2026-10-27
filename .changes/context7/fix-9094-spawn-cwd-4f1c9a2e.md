---
bump: patch
---

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.
