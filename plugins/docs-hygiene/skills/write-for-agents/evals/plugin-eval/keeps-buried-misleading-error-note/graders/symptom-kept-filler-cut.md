---
type: llm
arm: both
---

Judge only the trimmed AGENTS.md inside the fenced block, not the list of cuts after it.

PASS only if all of these hold:

1. The trimmed file keeps the note for `PermissionError: [Errno 13] Permission denied: '/tmp/tidepool-test.lock'`, stating both the real cause (a killed earlier test run left a stale lock file; it is not a permissions problem) and the fix (delete `/tmp/tidepool-test.lock` and rerun). Rewording is fine.
2. The trimmed file no longer contains the Layout list (`tidepool/`, `tests/`, `pyproject.toml` described one by one).
3. The trimmed file no longer contains the notes "Type hints are encouraged" and "Keep functions small", nor the notes on where routers, Pydantic models, and conftest fixtures live.

FAIL if the lock-file note is removed, or kept without its real cause or its fix; or if any item named in 2 or 3 remains in the trimmed file. Whether the Overview line or the uv commands survive does not decide the verdict.
