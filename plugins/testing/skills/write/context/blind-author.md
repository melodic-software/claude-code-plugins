# Blind Test Author Mode

An opt-in mode: a separate subagent writes the acceptance tests from the spec, without reading the
implementation, and those tests are committed before implementation starts. The implementer may
run them but may not edit them. The point is that the agent doing the work is not the one writing
the check that grades it.

The default cadence in [write.md](write.md), where one agent writes each test and then its code,
stays the default. Choose this mode when the user asks for it, and recommend it for:

- **Unattended work** (a loop, a dispatched worker, a run nobody reviews until the PR), where no
  human reads the tests before they are trusted.
- **HIGH-risk work**: the cases the `advisor` checkpoint in SKILL.md names (new domain logic,
  security-critical behavior, regression-prone paths).

Skip it for trivial changes and for work with no written acceptance criteria; without a spec, the
blind author has nothing independent to write from. Get the criteria first (`/planning:interview`
when the `planning` plugin is enabled).

## Steps

1. **Brief the author from the spec only.** Dispatch a fresh subagent with the acceptance criteria
   (the Brief, PRD, issue), the public interface the tests will call (signatures, routes, CLI
   shape), and the project's test conventions. Do not pass implementation files. Fence it from
   them: where the harness lets you, give that subagent tool or permission rules that exclude the
   implementation paths; otherwise state the fence in the brief and have the author list every
   file it read, and reject the tests if the list includes implementation code.
2. **Author writes acceptance tests at the public boundary.** One or more tests per criterion, each
   naming the criterion it checks, each expected value taken from the criterion, never from running
   code (`testing:test-value`). Outside-in shape: the user-visible outcome first (see
   [write.md](write.md), "Outside-in: the user-flow test first").
3. **Confirm Red, show, then commit.** Run the new tests and confirm each fails because the
   behavior is missing, not because of a typo or a broken fixture. Show the user one plain-language
   line per test, what it asserts and which criterion it checks, and commit only the tests they
   approve; in a run with no user present, put that list in the PR body instead. Commit them on
   their own, before any implementation, so the history shows the oracle predates the code.
4. **Implementer runs, never edits.** The implementer follows the normal cadence, writing its own
   unit tests inside, and runs the acceptance tests as its target. If one looks wrong, it stops and
   raises it to the user or orchestrator with the criterion and the evidence; the change goes
   through the author or the user, recorded in its own commit. At the end, an empty diff of the
   acceptance test files since their commit is the check that none were touched.

   **Optional lock.** When the user opts in, add the deny rule
   `Edit(//<absolute acceptance-test dir>/**)` for the implementer's run: through `--settings` or
   `--disallowedTools` when the implementer runs as its own `claude` session, or in
   `.claude/settings.local.json` when it is a subagent of this session (the rule then binds this
   session too, which is fine, since a test change goes through the user). Remove it when the run
   ends. The rule blocks Claude's file tools and the shell file commands Claude Code recognizes,
   not a script that writes files itself (`python -c`, `node -e`), so the empty-diff check above
   stays the gate.
5. **Review for special-casing.** A frozen test stops test edits, not code that recognizes the
   tested inputs and returns the expected values for them. Read the implementation diff for
   branches keyed to test data before trusting the green run.

## Basis and limits

Claude Code's best-practices page suggests one Claude writing tests and another writing code to
pass them, and describes a separate verifier so the agent doing the work isn't the one grading it:
[Run multiple Claude sessions](https://code.claude.com/docs/en/best-practices#run-multiple-claude-sessions)
and [Add an adversarial review step](https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step).
As of 2026-10-06. Recheck trigger: either section moves or drops the test-writer and code-writer
split.

The optional lock in step 4 rests on file-path deny rules:
[Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) for the path syntax and
what a deny does not cover, and
[When edits take effect](https://code.claude.com/docs/en/settings#when-edits-take-effect) for a
local settings change reaching a running session. As of 2026-10-10. Recheck trigger: either section
changes path anchoring, starts covering files a script writes, or stops reloading settings
mid-session.

Research backing is narrower than the first-party advice. AgentCoder
([arXiv 2312.13010](https://arxiv.org/abs/2312.13010)) separates a test-designer agent from the
programmer agent, measured on function-level benchmarks (HumanEval, MBPP), not repository-scale
agent work. ImpossibleBench ([arXiv 2510.20270](https://arxiv.org/abs/2510.20270), one study on
benchmark tasks) found read-only tests stopped test modification but not special-casing, which is
why step 5 exists. No source found evaluates a code-blind test author on real repositories, so
treat this mode as a design choice to measure, not a proven default.

Basis: the agent-self-check research slice (2026-10-06), prompted by Addy Osmani's 2026-10-05 post
(<https://x.com/addyosmani/status/2106995301802541481>) and its replies. Recheck trigger: a measured
evaluation of code-blind test authors on repository-scale work.
