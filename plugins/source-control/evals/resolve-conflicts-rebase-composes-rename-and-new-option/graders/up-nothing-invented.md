---
type: llm
focus: { source: file, path: retry.py }
---

The judged file is retry.py after a rebase that combines two branches. Both started from the same base file. Main renamed `max_retries` to `max_attempts` (the field and the loop bound). Feature added `import random`, a `backoff_jitter: float = 0.0` field, and `+ random.uniform(0, options.backoff_jitter)` on the exponential delay. Everything else comes unchanged from the shared base, so it counts as both sides' behavior. The correct combination is this file:

```python
import random
import time
from dataclasses import dataclass


@dataclass
class RetryOptions:
    max_attempts: int = 3
    backoff_jitter: float = 0.0
    base_delay: float = 0.1


def retry(fn, options=None, sleep=time.sleep):
    options = options or RetryOptions()
    last = None
    for attempt in range(options.max_attempts):
        try:
            return fn()
        except Exception as exc:
            last = exc
            sleep(options.base_delay * (2 ** attempt) + random.uniform(0, options.backoff_jitter))
    raise last
```

PASS if the judged file behaves the same as that reference. Differences in formatting, field order, import order, blank lines, or comments do not matter.

FAIL if the judged file adds behavior the reference lacks: a new option or parameter, a changed default, a different backoff formula, a cap on the delay, logging, or a new exception type. Also FAIL if it lacks behavior the reference has: `max_retries` is still present, `max_attempts` is missing, or the `backoff_jitter` field or its `random.uniform` term is missing.
