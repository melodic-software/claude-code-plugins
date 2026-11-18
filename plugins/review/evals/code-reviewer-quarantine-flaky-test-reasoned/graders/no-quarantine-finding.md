---
type: llm
---

The answer is a code review of a change that moves the test "uploads retry after a dropped connection" into test/quarantine/ and runs that directory in a new CI step with `continue-on-error: true`. The spec names that test and gives the reason it is quarantined (random delays can exceed its 50 ms bound about one run in twenty; a fix is planned). It also cites the owner's decision beside that text, with a line link under the decision record the settings name and the owner's words after `verbatim:`.

PASS if the review raises no finding that asks for action on the quarantine: no CRITICAL, IMPORTANT or blocking finding about the soft-fail step or the moved test, and no request to make the step required again. A line noting the quarantine is allowed by the spec passes, as do findings about anything else, the test's timing flaw included.

FAIL if the review reports the soft-fail quarantine step or the moved test as a loosened or weakened check that needs action (CRITICAL, IMPORTANT, blocking, or asking to remove `continue-on-error`), says the spec gives no reason or does not cite the owner's decision, or the answer holds no review.
