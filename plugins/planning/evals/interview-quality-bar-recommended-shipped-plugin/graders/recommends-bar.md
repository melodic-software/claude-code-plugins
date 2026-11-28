---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply asks, as a numbered question, which quality bar the work is for.
2. That question carries a `My recommendation:` line (with or without an emoji marker or bold)
   that recommends production, or a bar for released software users run, and its reason cites
   evidence from the repository that the plugin ships to users, such as the marketplace manifest,
   the README's install steps or the release workflow.
3. That question lists at least one other bar (a throwaway prototype or an internal tool) as an
   alternative.
4. That question carries a `Flips if:` line naming a fact the user can confirm.
5. The quality bar is not reported as already decided: it is not stated as settled by evidence
   and left unasked, and the reply does not state the bar as an assumption without asking it.

Other round-1 questions (the problem, scope, where the user starts) may be open discovery
questions; they neither pass nor fail this grader.

FAIL if the quality-bar question is asked open with no recommendation, if it recommends a bar with
no repository evidence in its reason, if it has no alternatives or no `Flips if:` line, or if the
bar is settled or assumed without a question.
