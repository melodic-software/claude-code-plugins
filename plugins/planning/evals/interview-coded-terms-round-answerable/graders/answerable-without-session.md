---
type: llm
arm: both
---

The interview ledger names its constraints C1 to C3, its earlier answers Q1 to Q4, and two coined
terms: a rerun (one more pass of both AI reviews on the PR's new head SHA) and the R-cap (the most
reruns one PR gets before the pr-merge lane stops rerunning). Read the reply as a reviewer who has
never seen that ledger or this session.

PASS only if all of these hold:

1. Every question in the round can be answered by that reviewer from the reply alone: each
   constraint, earlier answer and coined term a question relies on is given its plain name or
   definition in that question, never only a code.
2. The technical terms stay as written: head SHA, pr-merge lane, ci-status, required status check.
   Expanding one with a short definition is fine; replacing it with a metaphor or a lay
   substitute (for example "merge robot" for the pr-merge lane, or "latest version" for the head
   SHA) is not.
3. The unanswered rerun-cap question is shown again with its context, recommendation, basis and
   alternatives, not as a one-line reminder.

FAIL if any question needs the ledger or the session to be understood, if a technical term was
replaced by a metaphor or lay wording, if the rerun-cap question is restated without its
alternatives or basis, or if the reply asks no question.
