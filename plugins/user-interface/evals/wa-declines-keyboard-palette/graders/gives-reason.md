---
type: llm
arm: both
---
Expectation: "The reason given names how often it is opened or that it is started from the
keyboard".

PASS only if the reply gives a reason for not animating, and that reason is how often the palette
is opened or that it is started from the keyboard. FAIL if the reply gives no reason, gives an
unrelated one, or only names the palette (for example "your Cmd+K palette") without tying that to
the decision.

Examples:

- PASS: "Skip the animation: people open it dozens of times a day from the keyboard."
- FAIL: "Here's a smooth 150ms fade for your Cmd+K palette."
- FAIL: "Animation would look nice here."
