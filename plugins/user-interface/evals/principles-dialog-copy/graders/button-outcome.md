---
type: llm
arm: both
---
PASS only if the reply's revised JSX gives the button that calls `leaveTeam` a label that names
the outcome, leaving the team (for example "Leave team", "Leave Acme" or "Leave this team"). The
label is judged in the proposed JSX, not in a quoted draft, a before block or prose. FAIL if that
button still says "OK", or says "Yes", "Submit", "Confirm", "Continue" or "Proceed", if the label
names the outcome only in prose while the JSX keeps a generic label, or if the reply contains no
revised JSX for the dialog.
