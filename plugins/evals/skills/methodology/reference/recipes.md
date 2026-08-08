# Eval recipes — one per criteria dimension

Distilled from Anthropic's "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>, fetched 2026-08-08). The
source page carries full runnable code for every recipe in Python, TypeScript, C#, Go, Java, PHP,
and Ruby — fetch it for implementation; this file carries the design of each recipe. Re-fetch the
source before treating any specific here as current.

| Dimension | Method | Grading | Example scale |
|---|---|---|---|
| Task fidelity (classification) | Exact match | Code | 1,000 labeled tweets |
| Consistency (FAQ bot) | Cosine similarity of sentence embeddings | Code | 50 paraphrase groups |
| Relevance/coherence (summarization) | ROUGE-L F1 | Code | 200 articles w/ reference summaries |
| Tone & style (support) | Likert 1–5 | LLM | 100 inquiries w/ target tone |
| Privacy (medical chat) | Binary yes/no leak check | LLM | 500 simulated queries |
| Context utilization (assistant) | Ordinal 1–5 | LLM | 100 multi-turn conversations |

## Code-graded recipes

- **Exact match** — normalize (strip whitespace, lowercase) then compare with the labeled answer.
  Fits clear-cut categorical outputs (e.g. positive/negative/neutral/mixed). Edge cases from the
  source: sarcasm ("I just love it when my flight gets delayed for 5 hours"), mixed sentiment.
- **Cosine similarity** — embed each output with a sentence-embedding model (source uses
  Sentence-BERT `all-MiniLM-L6-v2`; <https://sbert.net/>), score mean pairwise cosine similarity
  across outputs for paraphrased variants of the same question; closer to 1 = more consistent.
  Edge cases: typos, long rambling phrasings, irrelevant info mixed into the question.
- **ROUGE-L** — longest-common-subsequence F1 between a generated and a reference summary; high
  score = key information captured in coherent order. Edge cases: multitopic articles, misleading
  titles.

## LLM-graded recipes

- **Likert scale (1–5)** — rate a subjective quality against a named target ("Rate this response
  1–5 for being {empathetic|patient|professional}; 1: not at all, 5: perfectly; output only the
  number"). Edge cases: angry customer, complex issue, compliment-phrased-as-complaint.
- **Binary classification** — "does this response contain/reference X? Output only 'yes' or
  'no'", with X precisely defined in the grader prompt (the source's PHI example enumerates
  identifiers, health data, financial information, communication forms). Catches subtle/implicit
  leaks rule-based systems miss. Edge cases: explicit, hypothetical, and implicit leaks; cases
  without the hazard auto-pass.
- **Ordinal scale (1–5)** — like Likert but for graded degree ("1: completely ignores context …
  5: perfectly utilizes context"), with the full conversation supplied to the grader. Edge cases:
  reliance on much-earlier context, abrupt topic shifts.

For every LLM-graded recipe: constrain grader output, validate its format, prefer a different
model than the generator, and sample-check grader verdicts before scaling — see `grading.md`.
