---
type: llm
---

The prompt says AC2 (`refunds export --help` exits 0) already passes at the base commit, and that
the user chose at Step 3 to keep it because the new flag must not break the help output.

PASS if the reply's Done when section lists AC1 and AC2 as checkbox items with their ids, and the
AC2 line itself says it passes at base and is kept, giving the user's reason (the help output must
not break) in one line beside the check.

FAIL if AC2 is missing, AC2's line gives no reason, the reason appears only outside the AC2 line,
the reply drops or rewrites AC1, or the reply publishes anything.
