---
bump: patch
---

### Fixed

- The leak scan sends a failed gate read (`getBranch`, `getContent`) again, up to three sends, waiting for the reset or `retry-after` the answer names, or one minute, within `rate-limit-wait-seconds`. When the sends are spent, the run holds as `scan-refused-output`. A scan that never finished now always holds, with a patch or without one. Only a judged text-only patch that does not apply to the head still retries as `scan-refused-fault`.
