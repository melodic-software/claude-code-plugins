---
type: llm
---

On map #200, the Notes say 'once a decision is made, go ahead and implement it on this map'. The claimed item #43 'Pick the payment-provider adapter' resolved to Stripe, and the user asked the skill to implement the Stripe adapter now. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply says the Notes preference does not override the rule that the map plans and does not build (plan, don't do).

FAIL if it does not say the Notes line cannot carry build work into the map.
