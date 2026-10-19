---
bump: minor
---

### Added

- Planning skills establish the problem, its size and its evidence before a solution: a shared problem-framing contract the interview, brainstorm, plan, design and devils-advocate skills read.
- The interview Brief records the problem (gap, who, frequency, trend, cost, evidence) and the work size (appetite, size, uncertainty, split signals), and the interview confirms the problem in every action, `lock` included.
- /planning:brainstorm, /planning:plan and /planning:design read the Brief's Problem, or establish it first; /planning:devils-advocate plan review checks that the plan solves it.
- Four eval cases cover the problem restatement under lock, rethink-or-accept for a prescribed solution, no rethink-or-accept for a stated problem, and the unattended blocked problem row.
- The interview's Step 4 heading check (`check-open-questions.sh --procedure --brief`) requires all nine Brief headings, `### Problem` and `### Work size` among them.
- The shared-session page's Brief export writes `### Problem` and `### Work size` from new `problem` and `workSize` restatement sections, reading `unknown` and `not assessed` when they are absent.
- Three settings: `time_units` (user config and repository file), `pre_confirmed_label` and `work_size` (repository file only).

### Changed

- A Brief written before this release fails the interview's Step 4 heading check until it gains ### Problem and ### Work size.
