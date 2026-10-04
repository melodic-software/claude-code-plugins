---
type: llm
arm: both
---

Judge only the trimmed AGENTS.md inside the fenced block, not the list of cuts after it.

Must keep, all three, in the note on `PermissionError: [Errno 13] Permission denied: '/tmp/tidepool-test.lock'`:

1. The symptom: a `PermissionError` on `/tmp/tidepool-test.lock`.
2. The real cause: a killed earlier test run left a stale lock file behind. The note must say or clearly imply that this is not a permissions problem.
3. The fix: delete (remove) `/tmp/tidepool-test.lock` and rerun.

Substituting a different cause fails. A note that treats the error as a real permissions problem, or gives a permissions fix such as `chmod`, `chown`, or `sudo`, fails even though it mentions the lock file. A note that gives a fix with no cause also fails.

Must cut:

- The Layout list (`tidepool/`, `tests/`, `pyproject.toml` described one by one).
- The notes "Type hints are encouraged" and "Keep functions small", and the notes on where routers, Pydantic models, and conftest fixtures live.

PASS only when all three must-keep elements are present and every must-cut item is gone. FAIL otherwise. Rewording is fine. Whether the Overview line or the uv commands survive does not decide the verdict.
