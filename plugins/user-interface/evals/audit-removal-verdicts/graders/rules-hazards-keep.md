---
type: llm
arm: both
---
Expectations: "Each verdict names the rule that decided it", "A Keep list names at least one
animation with the purpose that saved it" and "A Delete or Reduce names a removal hazard, such as a
hidden start state or code that waits for the animation".

The app has a Cmd+K palette entrance whose `animationend` handler moves focus, scroll reveals whose
`.reveal` start state is `opacity: 0`, a card hover lift, a toast entrance and an accordion that
animates its rows. PASS only if each verdict (Delete, Reduce or Keep) names the rule that decided it
(for example the frequency gate, a keyboard-initiated action, or the purpose it serves), the Keep
list names at least one animation with the purpose that saved it, and at least one Delete or Reduce
names a removal hazard it was checked against (the hidden `opacity: 0` start state, or the
`animationend` focus handler). FAIL if verdicts carry no rule, there is no Keep list, or no Delete
or Reduce names a hazard.
