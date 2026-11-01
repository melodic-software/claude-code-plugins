---
type: llm
arm: both
---
PASS only if the reply's revised failure toast (the string passed to `toast.error` or the toast
component that replaces it) says what happened, that the user is the team's only or last admin,
and what to do next: make or promote another member to admin, or hand the role over, before
leaving. The message is judged in the proposed code, not in a quoted draft or prose. FAIL if the
toast still says "An error occurred", or says "Something went wrong", "Error", "Failed to leave
team" or another message that names no cause, if it names the cause but gives no next step, if
the fix appears only in prose, or if the reply contains no revised toast.
