---
type: llm
---

On map #500, Decisions-so-far has 'Pick the vendor' (#502): Knock, provisional until the prototype #504 'Prove Knock sends email and in-app from one call'. #504 just failed (in-app messages need a second call); its fallback is Courier. The user asked to graduate #504. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply opens a new decision item linking #502, without reopening #502 or editing its resolution comment.

FAIL if it reopens #502, edits its resolution comment, or opens no new item linking #502.
