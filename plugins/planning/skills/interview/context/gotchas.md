# Interview gotchas

Failure patterns from real sessions. Loaded on demand from `/interview` SKILL.md.

## Q&A surface

- **Dependent question in its prerequisite's round** — a question whose framing depends on another question still open in the same round forces the user to guess or answer out of order. Sloppy frontier computation; the dependent question belongs to a later round.

- **`AskUserQuestion` without the opt-in, or beyond its cap** — the card surface requires the `use_ask_user_question` user config AND a round of ≤4 mutually independent questions. Prose otherwise; when in doubt, prose.

- **Silently resolving an unanswered round question to its recommendation** — a partial reply resolves only what was answered; the rest stays OPEN and re-surfaces next round. Only an explicit accept-shorthand ("accept all recommendations") resolves unanswered questions.

- **Silent capture of user design choices** — when a decision has real tradeoffs and no codebase answer, STOP and ask; do not fold into the Brief as an assumption.

- **An open question dropped on a topic change** — the user replies about something else, the question is never re-surfaced, and the contract locks with a hole in it. Measured at 31 minutes before the absence was noticed. Register at ask-time and diff every reply against the `open` rows; the transcript is not the record, the register is.

- **Registering a question only once it is answered** — the register then holds exactly the questions that never needed it, and the gate over it grades nothing. The write belongs at ask-time.

- **Passing `--brief` to the Step 3 gate run** — Step 4 writes PLAN.md, so at Step 3 the file does not exist and a named-but-missing `--brief` exits 2; a first-time interview deadlocks before it can persist anything. Ledger-only at Step 3, `--brief` on the Step 4 re-run.

- **Assuming `lock` never needs a register** — a clean lock synthesis writes none, but its STOP-on-gap and the unattended ladder both produce unresolved questions, and a question outside the register is a question outside the gate.

- **Treating the register gate's exit 2 as a pass** — ungradeable means the check could not see the state (missing register, gapped `Q<N>`, a deferred row absent from the Brief), which is when a silent hole is most likely, not least.

- **A blocking question fired mid-phase** — a gate that lands after the caller's phase is underway idles a lane nobody is watching (56% of one session's wall time). Emit the open set at the phase boundary; justify the exception in one line.

- **Assuming an answer because nobody was there to give one** — unattended, a genuine user decision becomes a named `blocked` row and a `USER-RESERVED` deferred question, never a quietly captured assumption. There is no way to detect non-interactivity, so the caller declares it.

## Brief contract

- **`lock` mode with hidden gaps** — if synthesis surfaces a true unknown, stop and ask; do not fudge the Brief.

- **Wrong topic directory** — on umbrella/shared branches the branch-derived slug may not match the topic; derive the slug from the topic name instead and say which one you used.

## Composition

- **Asking what the codebase already answers** — Grep/Read before spending a question on paths, conventions, or existing values.

- **Skipping incremental persist in `me` mode** — lock answers into `interview-checklist.md` + Brief as they resolve; crash mid-interview loses uncaptured branches.

## Scope

- **Interviewing mechanical work** — typo, lint-only, whitespace skips the interview per skill policy. Behavior-changing work is interview-first.

- **Interview used as the execution container for bulk work** — a corpus application yields one small contested-decision set plus an execution contract naming the per-unit loop, never one decision row per source unit with its own adoption ceremony. The tell is the count: candidate questions scaling with the number of source units instead of with genuine forks. Collapse (SKILL.md "Bulk application work is not a decision set").
