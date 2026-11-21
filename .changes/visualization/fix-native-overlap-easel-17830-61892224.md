---
bump: patch
---

### Changed

- **`visualize` routes a transcript chart to the built-in charts mod where it loads.** The
  skill's Boundary section names `cc-plugin-easel`: when its chart tool resolves in the session,
  a chart of quantities in the transcript goes to it, and the skill keeps every other form and
  medium. The mod's requirements and switches are recorded in `context/easel-mod.md`.
  ([#17830](https://github.com/melodic-software/claude-code-plugins/issues/17830))
