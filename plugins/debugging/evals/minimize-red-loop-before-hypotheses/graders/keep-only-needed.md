---
type: llm
---

PASS only if the reply plans (or makes) cuts to the request body fields, headers and config values one element at a time, runs the loop after each cut, keeps an element only when removing it turns the loop green, and drops an element whose removal leaves the loop red.

FAIL if the reply keeps elements on a guess, cuts several elements per run without isolating which one mattered, keeps an element whose removal leaves the loop red, or skips the loop run after a cut.
