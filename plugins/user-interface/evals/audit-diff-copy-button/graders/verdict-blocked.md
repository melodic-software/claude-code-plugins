---
type: llm
arm: both
---
PASS only if the review states a one-line verdict before its first finding, and that verdict is
Blocked: the copy button has no accessible name, which breaks the accessibility floor. A heading or
a short line naming what was reviewed may come before the verdict; a finding may not. FAIL if the
review has no verdict, if the verdict is "Ship it", "Approve with changes", "Looks good" or another
verdict that lets the diff merge as it is, or if the verdict comes only after the findings.
