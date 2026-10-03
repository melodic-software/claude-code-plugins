---
type: llm
arm: both
---

PASS if the answer says `expectations` should be an array (list) of strings rather than a single string. Mentioning other fields as well (for example a missing `name` or `files`) is fine.

FAIL if the answer says the JSON is fine as is, says a string works for `expectations`, flags only other fields, or later contradicts or retracts this.
