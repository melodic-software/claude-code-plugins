# Eval design

Distilled from Anthropic's "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>) and the evals cookbook
(`anthropics/claude-cookbooks` `misc/building_evals.ipynb`), both fetched 2026-08-08. Re-fetch the
sources before treating any specific here as current.

## Anatomy of an eval

Four parts per case:

1. **Input prompt** — fed to the model; often a set of variable inputs into a prompt template at
   test time.
2. **Output** — what the model under evaluation produced for that input.
3. **Golden answer** — what the output is compared against. Two legitimate forms: a mandatory
   exact-match answer, or an example/description of a perfect answer that gives a grader a point of
   comparison. For human or LLM graders, the golden answer is best written as INSTRUCTIONS on what
   to look for — what must be included, what is allowed, what is disqualifying.
4. **Score** — produced by a grading method (see `grading.md`), representing how the model did.

## The three design principles

1. **Be task-specific.** Mirror the real-world task distribution — the mix of questions and
   difficulty your application actually sees. Include edge cases explicitly:
   - irrelevant or nonexistent input data
   - overly long input data or user input
   - (chat) poor, harmful, or irrelevant user input
   - ambiguous cases where even humans would find consensus hard
2. **Automate when possible.** Structure questions so grading can be automated: multiple-choice,
   string match, code-graded, LLM-graded. "Often all that lies between you and an automatable eval
   is clever design" — reformatting into multiple choice is a common tactic.
3. **Prioritize volume over quality.** More questions with slightly-lower-signal automated grading
   beat fewer questions with high-quality human hand-grading.

## The cost asymmetry — design for cheap re-runs

Writing questions and golden answers is roughly a one-time fixed cost. Grading is a cost you incur
on EVERY re-run, in perpetuity — and you will re-run the eval a lot. Build evals that can be
quickly and cheaply graded; put that at the center of design choices.

Constrain the output format to make cheap grading possible: e.g. "return just the number of legs as
an integer and nothing else" (plus a small `max_tokens`) turns a free-form task into an exact-match
one.

## Scaling authoring

Writing hundreds of test cases by hand is hard — have Claude generate more cases from a baseline
set of examples. If unsure which eval methods fit your criteria, brainstorm methods with Claude
too. Keep a human sign-off on generated cases: generation scales authoring, it does not replace
judgment about what the distribution should be.
