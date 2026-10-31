---
bump: patch
---

### Fixed

- `/planning:interview` requires a recommendation that reuses an existing value (an email address,
  account, subscription, region, secret name or repository) to state the literal value and where
  it was read; "the existing X" alone is not enough. Contact addresses and identities are
  owner-reserved: the user confirms the literal before anything is created with it.
- The assumption sweep flags an `unstated-value` item, a reference to an existing value whose
  literal the ledger never states, and asks the user to confirm the literal in a register row.
  The `--procedure` gate accepts the category and fails such an item that a fact line settles.
