# Success criteria

Distilled from Anthropic's "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>, fetched 2026-08-08).
Re-fetch the source before treating any specific here as current.

Define success criteria BEFORE building evaluations, and evaluations before iterating on prompts —
the cycle (test cases → preliminary prompt → iterative testing and refinement → final validation →
ship) is central to prompt engineering.

## The four properties of a good criterion

| Property | Meaning | Bad → good |
|---|---|---|
| **Specific** | Clearly define what to achieve | "good performance" → "accurate sentiment classification" |
| **Measurable** | Quantitative metrics or well-defined qualitative scales | "safe outputs" → "<0.1% of outputs out of 10,000 trials flagged for toxicity by our content filter" |
| **Achievable** | Grounded in industry benchmarks, prior experiments, AI research, or expert knowledge — not beyond current frontier capability | aspirational guess → "5% improvement over our current baseline" |
| **Relevant** | Aligned with the application's purpose and its users' needs | citation accuracy is critical for a medical app, less so for a casual chatbot |

Worked example (sentiment analysis): "F1 ≥ 0.85 (measurable, specific) on a held-out test set of
10,000 diverse Twitter posts (relevant), a 5% improvement over the current baseline (achievable)" —
versus the bad form "the model should classify sentiments well".

**Even hazy qualities are quantifiable.** Ethics, safety, empathy, coherence — pair a qualitative
scale with a quantitative measure rather than leaving the quality unmeasured: Likert scales ("rate
coherence from 1 (nonsensical) to 5 (perfectly logical)"), expert rubrics (linguists rating
translation quality on defined criteria), or a counted threshold over many trials (the toxicity
example above). Qualitative measures are valuable when consistently applied *alongside*
quantitative ones, not instead of them.

## Metric menu

- **Task-specific quantitative:** F1 score, BLEU score, perplexity.
- **Generic quantitative:** accuracy, precision, recall.
- **Operational:** response time (ms), uptime (%).
- **Quantitative methods:** A/B testing against a baseline model or earlier version; implicit user
  feedback such as task completion rates; edge-case analysis (% of edge cases handled without
  errors).
- **Qualitative scales (paired with numbers):** Likert scales; expert rubrics.

## Common criteria dimensions (non-exhaustive)

1. **Task fidelity** — how well the core task is performed, including on rare or challenging
   inputs (edge-case handling).
2. **Consistency** — how similar responses are for similar inputs; same question twice →
   semantically similar answers.
3. **Relevance and coherence** — directly addressing the user's questions; logical, easy-to-follow
   presentation.
4. **Tone and style** — output style matching expectations and audience.
5. **Privacy preservation** — handling of personal/sensitive information; following instructions
   not to use or share certain details.
6. **Context utilization** — referencing and building on conversation history.
7. **Latency** — acceptable response time for the application's real-time needs.
8. **Price** — budget per API call, model size, usage frequency.

## Evaluate multidimensionally

Most use cases need several criteria at once. Worked example — on a held-out test set of 10,000
diverse tweets, the sentiment model should achieve ALL of:

- F1 ≥ 0.85
- 99.5% of outputs non-toxic
- 90% of errors cause inconvenience, not egregious error (and in reality you would define
  "inconvenience" and "egregious")
- 95% of responses < 200 ms

A single headline metric hides regressions on the other dimensions; state each dimension as its own
measurable target.
