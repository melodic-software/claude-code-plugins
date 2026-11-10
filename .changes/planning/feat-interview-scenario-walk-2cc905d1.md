---
bump: minor
---

### Added

- `/planning:interview`: a scenario walk. When the user calls something unclear, or a question rests on a term the glossary does not define or uses two ways, the interview offers numbered concrete scenarios (`S1`, `S2`, ...) inside one question, each ending with its own recommendation and the term or rule it forces, answered per scenario ("S3: a"). Once an assumption sweep has logged `S<N>` items, scenario ids are qualified by their question (`Q17.S1`), and the bare-code gate fails a bare `S<N>:` scenario that is also a sweep id. Resolutions go on that question's register row and agreed terms to the glossary; during a walk it offers an opt-in diagram through `/visualization:visualize` when available.
- `/planning:interview`: a closing summary before the confirmation recap groups the decisions changed since read-back, glossary terms added, renamed or removed, out-of-scope items with where each goes, and one ADR verdict line per decision naming the part of `/architecture:record-decision`'s admission test it passes or fails. Replying "Q12: record it" overrules a verdict and hands that decision to `/architecture:record-decision`.
