# Readiness and run contract for an unattended run

## Readiness conditions (Step 0.5)

Check each from evidence (the repo, its history, the session, the commands you can run), and name
the evidence:

1. The task has been done once by hand, or watched once as an agent did it.
2. The agent has the tools and signals the user would use to judge the work (the verification
   command, the tests, the logs), and they run in this session.
3. Every stage proves its work with a check that can stop the run when the work misses the bar.
4. Failures that came back in past runs already have a tool, skill or check that catches them.

## Run contract (Step 4)

Emitted beside the condition when Step 0.5 ran. One line each:

- **Goal**: the intent in one line.
- **Predicate**: the counter-passed condition.
- **Isolation**: a fresh worktree (`/source-control:worktree`, if enabled) or a background session.
- **Pre-granted permissions**: what the run would otherwise stop to ask for, each granted in
  settings or the permission mode before launch, never by a line in the prompt. For how goal turns
  get permission, see the SKILL.md gotcha on a goal whose check is a shell command.
- **Stop limit**: the turn or spend cap that ends the run if the predicate never passes, set
  before launch.
- **Output and approval**: where the result lands (a branch, a pull request, a report) and who
  approves anything irreversible (the merge, a deploy, a deletion).
- **Dead end**: where the run writes up a dead end under Step 2's stall rule (what was tried and
  what blocked each attempt) before handing the decision to the user.
- **Readiness**: each condition with its evidence, and any "no" left open.

The pre-run questions these lines answer, and the flags that cap turns and spend:
<https://code.claude.com/docs/en/best-practices#let-claude-run-without-you>.
