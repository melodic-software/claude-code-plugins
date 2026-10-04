# Interview gotchas

Failure patterns from real sessions. Loaded on demand from `/planning:interview` SKILL.md.

## Q&A surface

- **Dependent question in its prerequisite's round:** a question that only makes sense once a sibling in that round is answered makes the user guess or answer out of order. The frontier was computed wrong: move the dependent question to the next round.

- **`AskUserQuestion` without the opt-in, or beyond its cap:** the card surface requires the `use_ask_user_question` user config AND a round of ≤4 mutually independent questions. Prose otherwise; when in doubt, prose.

- **Silently resolving an unanswered round question to its recommendation:** a partial reply resolves only what was answered; the rest stays OPEN and re-surfaces next round. Only an explicit accept-shorthand ("accept all recommendations") resolves unanswered questions.

- **Silent capture of user design choices:** when a decision has real tradeoffs and no codebase answer, STOP and ask; do not fold into the Brief as an assumption.

- **An open question dropped on a topic change:** the user replies about something else, the question is never re-surfaced, and the contract locks with a hole in it. Register at ask-time and diff every reply against the `open` rows; the transcript is not the record, the register is.

- **Registering a question only once it is answered:** the register then holds exactly the questions that never needed it, and the gate over it grades nothing. The write belongs at ask-time.

- **Interviewing with plan mode on:** the ask-time register write is a disk write (the ledger's `## Open-question register` section), and plan mode's read-only enforcement blocks it, so the round gets asked with nothing on disk holding it: precisely the failure the register exists to prevent, reintroduced by the permission mode. Plan mode also pushes the run toward writing a plan while the job is still settling *what* to build. Leave plan mode off while interviewing: it is `/planning:plan`'s mode, not this skill's.

- **Passing `--brief` to the Step 3 gate run:** Step 4 writes PLAN.md, so at Step 3 the file does not exist and a named-but-missing `--brief` exits 2; a first-time interview deadlocks before it can persist anything. Ledger-only at Step 3, `--brief` on the Step 4 re-run.

- **Assuming `lock` never needs a register:** a clean lock synthesis writes none, but its STOP-on-gap and the unattended ladder both produce unresolved questions, and a question outside the register is a question outside the gate.

- **Treating the register gate's exit 2 as a pass:** ungradeable means the check could not see the state (missing register, gapped `Q<N>`, a deferred row absent from the Brief), which is when a silent hole is most likely, not least.

- **A blocking question fired mid-phase:** a gate that lands after the caller's phase is underway idles a lane nobody is watching. Emit the open set at the phase boundary; justify the exception in one line.

- **Assuming an answer because nobody was there to give one:** unattended, a genuine user decision becomes a named `blocked` row and a `USER-RESERVED` deferred question, never a quietly captured assumption. There is no way to detect non-interactivity, so the caller declares it.

- **A bundled recommendation locked by accepting its headline:** a design that also picks a platform, a runtime, and a credential reads as one answer, so a "yes" records one row and locks every part the user never saw. List each part under `Commits you to:` with its own row; a part left unlisted is not decided (SKILL.md "A recommendation that fixes more than one decision lists every part").

- **A hedged reply read as accept-all:** "yes?" or "I think so" signals doubt, so it cannot lock a bundle or a round (SKILL.md "A hedged reply resolves only the headline").

- **An upstream Brief treated as binding:** a prior Brief locked "as a starting point" reads as settled, so its constraints steer every recommendation without the user confirming them for this topic. Record them as `inherited` and ask the ones the contract relies on (SKILL.md "Keep a running constraint ledger").

- **A research design recommended as found:** explore or research output, or an existing implementation, arrives with a recommended design that was never checked against this interview's constraints. It is a candidate until re-derived against the constraint ledger (SKILL.md "Composed artifacts are candidates").

- **Drifting from what to how:** recommendations slide into per-step platforms and token scopes with nothing stopping them. The first question that names a mechanism triggers one question: settle mechanisms now, or at planning (SKILL.md "What, not how: the mechanism tripwire").

- **Past evidence read as the target:** months of metrics describe the old process, not the one the user just changed to. Label each finding past, current, or intended, and never recommend the intended process from past-only evidence (SKILL.md "Label evidence by when it was true").

- **A clean register over unasked assumptions:** the register tracks only questions that were asked, so it grades clean while the draft still rests on hidden defaults and contradictions. Sweep before the confirmation gate (SKILL.md "Sweep for assumptions before Step 3").

## Page surface

- **A stale `ops.json`:** a file left from an earlier wake re-applies its old replies; write it fresh with the Write tool on every wake.

- **A forgotten `handle`:** the page stays on "Claude is working on Qn" and the event is re-delivered on the next arm; every event ends handled.

- **A server restart:** the restart issues a new token, so the armed watcher exits 2; re-arm it after `ensure-running`.

## Brief contract

- **`lock` mode with hidden gaps:** if synthesis surfaces a true unknown, stop and ask; do not fudge the Brief.

- **Wrong topic directory:** on umbrella/shared branches the branch-derived slug may not match the topic; derive the slug from the topic name instead and say which one you used.

## Composition

- **Asking what the codebase already answers:** Grep/Read before spending a question on paths, conventions, or existing values.

- **Skipping incremental persist in `me` mode:** lock answers into `interview-checklist.md` + Brief as they resolve; crash mid-interview loses uncaptured branches.

## Scope

- **Interviewing mechanical work:** typo, lint-only, whitespace skips the interview per skill policy. Behavior-changing work is interview-first.

- **Interview used as the execution container for bulk work:** a corpus application yields one small contested-decision set plus an execution contract naming the per-unit loop, never one decision row per source unit with its own adoption ceremony. The tell is the count: candidate questions scaling with the number of source units instead of with genuine forks. Collapse (SKILL.md "Bulk application work is not a decision set").
