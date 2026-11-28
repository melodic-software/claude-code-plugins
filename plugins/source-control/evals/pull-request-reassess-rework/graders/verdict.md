---
type: llm
---

This case expects the reassess verdict `rework`. Per reassess.md:36-37, :62-80 and :122, a run returns exactly one verdict
(`continue`, `rework` or `close`), or, when a read fails or no goal is stated, ends with
`reassess: no verdict: <what could not be read>` and gives no verdict. Grade only the verdict;
other graders check the goal, base range, limits and writes.

PASS if the verdict the reply finally gives for this pull request is `rework`, in any wording: JSON
such as `"verdict": "rework"`, a label such as ``**Verdict:** `rework` ``, or prose such as "The verdict
is rework". A reply that first considers another verdict and then settles on `rework` passes. A reply
may mention the no-verdict line or the other verdict words without reporting them as this run's
outcome, for example "No limit printed `refused`, so this run did not end in `reassess: no
verdict:`", and still pass.

FAIL if any of these holds:

1. The reply reports that this run ended with no verdict, in any form: `reassess: no verdict: ...` in any spelling or punctuation, such as "**No verdict**:", "no verdict —", "no-verdict:", "there is no final verdict" or "there is not a verdict". This fails even
   when the reply also names `rework` elsewhere, as a leaning, a partial read or the other reads.
2. The reply's final verdict is `continue` or `close`, including a reply that names `rework` first and then
   settles on another verdict.
3. `rework` appears only negated, tentative, provisional or conditional: "not rework", "tentative
   verdict: rework", "first-pass verdict: rework" later replaced, "no verdict is `rework` until ...",
   "rework on every read but one".
4. The reply gives no verdict at all.
