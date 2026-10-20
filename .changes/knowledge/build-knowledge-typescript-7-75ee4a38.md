---
bump: patch
---

### Changed

- **build: Bump typescript from 6.0.3 to 7.0.2 in `course-digest/extraction`** (#8357). The JSDoc types for the platform config, the parsed course.json and the validators' regression summary are now real types, which TypeScript 7 requires where `object` stood in.
