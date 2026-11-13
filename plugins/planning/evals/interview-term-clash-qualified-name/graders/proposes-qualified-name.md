---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply says that "account" already means something else here: one person's sign-in identity,
   in the code or the glossary.
2. The reply recommends a specific qualified name for the paying group that it proposes itself
   (for example "household account", "billing account" or "family account"), asked as a question
   the user can accept or change.

FAIL if the reply uses the bare word "account" for the paying group without raising the clash,
raises the clash but asks the user to choose or invent a name with no recommended name of its own,
or proposes renaming the existing sign-in Account as its recommendation.
