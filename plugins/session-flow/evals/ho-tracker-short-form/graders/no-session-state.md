---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply's resume is two lines: an instruction to `/clear` and then run a command, and the
   command `/planning:wayfind work https://example.com/acme/booking/issues/40 https://example.com/acme/booking/issues/43`.
2. The resume carries no session state: no restated findings or decision from item 42, no goal
   quote, no list of remaining actions, and no reference to a handoff file.
3. Nothing follows the two lines.

FAIL if the reply writes or points at a handoff file, restates the item's findings in the resume,
uses a bare issue number in place of the full URL, or keeps working on item 43.
