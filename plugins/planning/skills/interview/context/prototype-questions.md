# When the outcome feeds a prototype

Read this when the interview's outcome is a prototype to build: the user picked the throwaway
prototype quality bar, or the work's next step is building one or more prototypes (SKILL.md
"Clashing terms, prototypes and fact lookups"). The mid-interview detour in [`composition.md`](composition.md)
"Mid-interview composition" is a different case: there a throwaway answers one interview question
and the interview resumes; here the prototype is what the interview hands off.

## Ask what the prototype must prove

Before the contract locks, ask one registered question: what must the prototype prove? Recommend
the answer from the evidence: the open assumptions, deferred questions and stated unknowns the
prototype exists to settle. Each item in the answer is one question the prototype answers, with
the observable result that answers it (what the user would see, run or measure), so a reviewer can
tell when the prototype has done its job. A prototype with nothing to prove is not asked about
further: say so and treat the work by its quality bar as usual.

## Split by question

Recommend one prototype per question, each small enough to build, judge and throw away on its own,
with no shared state or build order between them, so the pieces can be built at the same time,
each in its own worktree. List them under `Commits you to:` so the user can merge or drop any one.
Two questions that genuinely need the same build stay one piece; name why in that piece's line. The
interview lists the pieces; it creates no worktree and builds nothing.

## Record the pieces

An engineering session writes each agreed piece into the Brief's `### Acceptance criteria` as one
bullet: `Prototype <n> proves: <question>; answered by: <observable result>`. A general session
lists them in the shared-understanding summary. At the hand-off, name for each piece the skill that
fits its question (`/prototype:explore-directions` for look and feel, `/prototype:pressure-test`
for logic, state or data shape, when enabled) and that each runs in its own worktree
(`/source-control:worktree create`, when enabled; otherwise `git worktree add`).
