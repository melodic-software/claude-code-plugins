---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply asks at least one numbered question about what the request leaves unknown: the
   problem notifications would solve, who they are for, or what is in scope.
2. Every question in the reply is open: none proposes or recommends an answer, offers lettered
   alternatives to pick from, or states an assumed answer for the user to confirm.
3. The reply asks no decision about how to build notifications (channels, delivery mechanism,
   settings screens).

A line suggesting another skill (for example brainstorming) is not a question and does not fail
check 2. A `Context:` block that describes what each possible answer would change, such as the
three quality bars (a throwaway prototype, an internal tool, production) and how deep each takes
the interview, is not offering alternatives and does not fail check 2; a question title that lists
answers for the user to pick from does.

FAIL if any question carries a recommended or assumed answer, if the reply asks a build decision,
or if it asks no question.
