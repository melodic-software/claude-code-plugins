---
type: llm
arm: both
---

PASS only if the audit (1) reports the sentence `The CLI feels snappy and modern, and
working with it is a joy.` under rule-mechanism-free-claims (it may also cite another rule such
as promotional language), and (2) reports no rule-mechanism-free-claims finding for `The CLI
starts in 80 ms on a cold cache and reads its settings from one cli.toml file.` FAIL if the
feeling-word sentence is not reported under rule-mechanism-free-claims, if the 80 ms sentence is
reported under that rule, or if the reply says it edited the file.
