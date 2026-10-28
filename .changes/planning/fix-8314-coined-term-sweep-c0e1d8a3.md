---
bump: minor
---

### Added

- **The interview assumption sweep reports coined names.** A new `coined-term` category catches a name, label or abbreviation the session coined in a recommendation, a `Commits you to:` part or a composed artifact (one the user did not introduce, nothing existing uses, and the session-shorthand glossary lacks), even after the user accepted the answer that carried it. Each becomes a register row asking the user to accept or rename the term, recommending the closest name the user already uses; a rename carries into the draft and the rows that hold the term. The sweep sub-agent is now handed the glossary, the project's domain-vocabulary file and the user's own names for things ([#8314](https://github.com/melodic-software/claude-code-plugins/issues/8314)).
- **A question that coins a name records it at ask-time.** Its glossary line is written in the same step as its register row, and the name is defined in the question (`context/loop.md` "Session-shorthand glossary").
- Eval case `sweep-flags-coined-term-after-accept-all`: a recommendation coins a role name that overlaps the user's existing role, the user answers "accept all", and the sweep must still return a `coined-term` item.
