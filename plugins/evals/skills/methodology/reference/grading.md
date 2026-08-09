# Grading methods

Distilled from Anthropic's "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>) and the evals cookbook
(`anthropics/claude-cookbooks` `misc/building_evals.ipynb`), both fetched 2026-08-08. Re-fetch the
sources before treating any specific here as current.

## The ladder — pick the fastest, most reliable, most scalable method that fits

1. **Code-based grading** — fastest and most reliable, extremely scalable; lacks nuance for
   judgments that resist rule-based rigidity. Forms: exact match (`output == golden_answer`),
   string match (`key_phrase in output`), regex, multiple-choice keying. Prefer it whenever the
   eval can be designed to allow it.
2. **LLM-based grading** — fast, flexible, scalable, suitable for complex judgment. TEST the
   grader's reliability first, then scale.
3. **Human grading** — most flexible and highest quality, but slow and expensive. **Avoid if
   possible.** When used, give the human grader rubric-instructions as the golden answer.

## LLM-grader practice

- **Detailed, clear rubrics.** E.g. "The answer should always mention 'Acme Inc.' in the first
  sentence. If it does not, the answer is automatically graded as 'incorrect.'" One use case — or
  even one success criterion — may need SEVERAL rubrics for holistic evaluation.
- **Empirical or specific output.** Instruct the grader to output only `correct`/`incorrect`, or a
  1–5 score. Purely qualitative open-ended judgments are hard to assess quickly at scale.
- **Encourage reasoning, then discard it.** Have the grader think first (e.g. in `<thinking>`
  tags) before deciding, then extract only the verdict (e.g. from `<result>` or `<correctness>`
  tags). Reasoning improves grading on complex judgment; only the verdict is kept.
- **Validate the grader's output format.** Extract the verdict tag with a strict pattern; treat a
  missing/non-conforming verdict as an error, not a silent pass or fail.
- **Different model than the generator.** It is generally best practice to grade with a different
  model than the one that produced the evaluated output.
- **Test the grader before trusting it.** The only way to know whether a model-based grader can
  grade your task is to try it and READ SAMPLES of its verdicts against your own judgment; only
  then scale.
- **Binary correctness is strict by default.** An answer is correct iff it entirely meets the
  rubric; otherwise incorrect — no partial credit unless the rubric defines a scale.

## Grader prompt skeleton

```text
You will be provided an answer that an assistant gave to a question, and a rubric that instructs
you on what makes the answer correct or incorrect.

<answer>{answer}</answer>
<rubric>{rubric}</rubric>

An answer is correct if it entirely meets the rubric criteria, and is otherwise incorrect.
First, think through whether the answer is correct or incorrect based on the rubric inside
<thinking></thinking> tags. Then output 'correct' or 'incorrect' inside <result></result> tags.
```

Extract `<result>` with a strict match; raise on absence. For scale grading, swap the final
instruction for "output only the number" with the scale anchors defined (1: not at all X … 5:
perfectly X).
