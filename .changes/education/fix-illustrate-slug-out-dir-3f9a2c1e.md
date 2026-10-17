---
bump: patch
---

### Security

- **illustrate keeps the model-chosen slug out of its build command.** The builder takes `--out-dir` and reads the slug from the model JSON, refuses one that is not lowercase letters, digits and hyphens (exit 2), and derives the record and page paths itself, so the command the skill runs carries only fixed paths. The model file is per session, so two sessions sharing the data directory cannot build each other's topic. (#7374)
