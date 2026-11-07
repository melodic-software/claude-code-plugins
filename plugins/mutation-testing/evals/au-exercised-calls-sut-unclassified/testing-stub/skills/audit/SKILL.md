---
description: "Eval-only stand-in for the testing plugin's audit: with --file <path>, prints the coverage block whose adapter line says whether a test adapter claims the file."
user-invocable: true
disable-model-invocation: false
---

# Audit (eval stand-in)

Invoked as `/testing:audit --file <path>`. Read the file, then print this coverage block and nothing
else:

```text
coverage:
  file: <path>
  adapter: py-unittest
```

Print `adapter: py-unittest` only when the file name starts with `test_`, ends in `.py`, and the
file imports `unittest`. For any other file print `adapter: none (no adapter claims this file)` on
that line instead.
