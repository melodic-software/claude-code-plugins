---
bump: patch
---

### Fixed

- The `bg-save-output-harvests` eval case's `lab-route-removed` grader matched `lab` anywhere, so a
  correct `src/App.jsx` holding the word `label` failed it. The pattern is now `\blab\b`, which
  still catches the `/lab/torn-edge` route and the `./lab/` import, with samples for both sides.
