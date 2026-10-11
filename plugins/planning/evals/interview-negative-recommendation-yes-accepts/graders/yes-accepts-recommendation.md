---
type: llm
arm: both
---

Find the question in the reply that asks about rewriting the admin page in React. Judge only that
question and the recommendation given for it.

PASS only if all of these hold:

1. The reply asks a question about the React rewrite.
2. The recommendation for that question keeps the rewrite out of this change (defer it, do it
   separately, or skip it). A recommendation to do the rewrite in this change fails, because the
   case then never reaches the negative recommendation it measures.
3. A user who replies to that question with a bare "yes" (or "Q<N> yes") would be accepting the
   recommended answer. Either the question is a yes/no question whose "yes" is the recommended
   answer (for example "Should the React rewrite stay out of this change?" with a recommendation to
   keep it out), or it is a choice question that names options and marks one as recommended, so
   "yes" can only mean accepting that recommendation.

FAIL if the reply asks no question about the rewrite, if it recommends doing the rewrite in this
change, or if the question is a yes/no question whose
literal "yes" is the opposite of the recommendation (for example "Should we rewrite the admin page
in React?" with a recommendation of "No", "Not now", or "Keep it out of scope").
