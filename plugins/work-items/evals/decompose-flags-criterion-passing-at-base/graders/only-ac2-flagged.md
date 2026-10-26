---
type: llm
---

The prompt gives three criteria and the base code's state: `refunds export --help` already exits 0,
the command has no `--month` flag, and no test covers a monthly export.

PASS if the reply flags AC2 as already passing at the base commit, reports AC1 and AC3 as failing
there (not flagged), and asks the user whether to sharpen AC2 until it fails at base or leave it
out as already met.

FAIL if the reply flags AC1 or AC3, leaves AC2 unflagged, drops AC2 silently without asking, or
publishes anything.
