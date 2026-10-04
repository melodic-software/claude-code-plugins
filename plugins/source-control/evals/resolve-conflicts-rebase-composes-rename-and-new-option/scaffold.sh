#!/usr/bin/env bash
# A Python repo stopped mid-rebase of feature onto main: main renamed max_retries to
# max_attempts; feature's two commits add backoff_jitter and document it. Both commits conflict.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

cat > retry.py <<'PY'
import time
from dataclasses import dataclass


@dataclass
class RetryOptions:
    max_retries: int = 3
    base_delay: float = 0.1


def retry(fn, options=None, sleep=time.sleep):
    options = options or RetryOptions()
    last = None
    for attempt in range(options.max_retries):
        try:
            return fn()
        except Exception as exc:
            last = exc
            sleep(options.base_delay * (2 ** attempt))
    raise last
PY
cat > test_retry.py <<'PY'
import unittest

from retry import RetryOptions, retry


class RetryTest(unittest.TestCase):
    def test_stops_after_the_configured_count(self):
        calls = []

        def boom():
            calls.append(1)
            raise ValueError("down")

        with self.assertRaises(ValueError):
            retry(boom, RetryOptions(max_retries=2), sleep=lambda s: None)
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
PY
cat > README.md <<'MD'
# retry

Options:

- `max_retries`: how many times to call the function.
- `base_delay`: first backoff delay in seconds.
MD
git add .
git commit -q -m "feat(retry): retry helper with exponential backoff"

git checkout -q -b feature
python3 - <<'PY'
import re
src = open("retry.py").read()
src = src.replace("import time\n", "import random\nimport time\n")
src = src.replace("    max_retries: int = 3\n", "    max_retries: int = 3\n    backoff_jitter: float = 0.0\n")
src = src.replace("sleep(options.base_delay * (2 ** attempt))", "sleep(options.base_delay * (2 ** attempt) + random.uniform(0, options.backoff_jitter))")
open("retry.py", "w").write(src)
PY
cat > test_jitter.py <<'PY'
import unittest

from retry import RetryOptions, retry


class JitterTest(unittest.TestCase):
    def test_delay_stays_within_the_jitter_bound(self):
        delays = []

        def boom():
            raise ValueError("down")

        with self.assertRaises(ValueError):
            retry(boom, RetryOptions(max_retries=2, backoff_jitter=0.5), sleep=delays.append)
        self.assertEqual(len(delays), 2)
        for attempt, delay in enumerate(delays):
            floor = 0.1 * (2 ** attempt)
            self.assertTrue(floor <= delay <= floor + 0.5)


if __name__ == "__main__":
    unittest.main()
PY
git add retry.py test_jitter.py
git commit -q -m "feat(retry): add backoff_jitter option" -m "Clients that fail together retry together and hit the API in lockstep; a random extra delay spreads them out. Refs RET-57."
python3 - <<'PY'
src = open("README.md").read()
src = src.replace("call the function.\n", "call the function.\n- `backoff_jitter`: upper bound of a random extra delay per retry, in seconds.\n")
open("README.md", "w").write(src)
PY
git add README.md
git commit -q -m "docs(retry): document backoff_jitter"

git checkout -q main
sed -i 's/max_retries/max_attempts/g' retry.py test_retry.py
sed -i 's/- `max_retries`: how many times to call the function./- `max_attempts`: how many calls in total, including the first./' README.md
git add retry.py test_retry.py README.md
git commit -q -m "refactor(retry): rename max_retries to max_attempts" -m "The count includes the first call, so every caller read max_retries as one more call than it makes. Refs RET-41."

git checkout -q feature
git rebase main >/dev/null 2>&1 || true
test -d .git/rebase-merge
git diff --name-only --diff-filter=U | grep -qx retry.py
