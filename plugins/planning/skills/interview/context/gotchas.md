# Interview gotchas

Failure patterns from real sessions. Loaded on demand from `/interview` SKILL.md.

## Q&A surface

- **Dependent question in its prerequisite's round** — a question whose framing depends on another question still open in the same round forces the user to guess or answer out of order. Sloppy frontier computation; the dependent question belongs to a later round.

- **`AskUserQuestion` without the opt-in, or beyond its cap** — the card surface requires the `use_ask_user_question` user config AND a round of ≤4 mutually independent questions. Prose otherwise; when in doubt, prose.

- **Silently resolving an unanswered round question to its recommendation** — a partial reply resolves only what was answered; the rest stays OPEN and re-surfaces next round. Only an explicit accept-shorthand ("accept all recommendations") resolves unanswered questions.

- **Silent capture of user design choices** — when a decision has real tradeoffs and no codebase answer, STOP and ask; do not fold into the Brief as an assumption.

## Brief contract

- **`lock` mode with hidden gaps** — if synthesis surfaces a true unknown, stop and ask; do not fudge the Brief.

- **Wrong topic directory** — on umbrella/shared branches the branch-derived slug may not match the topic; derive the slug from the topic name instead and say which one you used.

## Composition

- **Asking what the codebase already answers** — Grep/Read before spending a question on paths, conventions, or existing values.

- **Skipping incremental persist in `me` mode** — lock answers into `interview-checklist.md` + Brief as they resolve; crash mid-interview loses uncaptured branches.

## Scope

- **Interviewing mechanical work** — typo, lint-only, whitespace skips the interview per skill policy. Behavior-changing work is interview-first.
