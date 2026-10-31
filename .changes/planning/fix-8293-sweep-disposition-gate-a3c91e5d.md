---
bump: patch
---

### Fixed

- `/planning:interview` no longer lets a session settle an assumption-sweep `decision` item with an
  uncited fact and still pass the gate. Each sweep item is now recorded in the ledger's
  `## Assumption sweep` section with its disposition: a `Q<N>` register row, an `F<N>` fact whose
  basis quotes its source with a file:line or URL, or `deferred: <where>`. A fresh-context check
  confirms each quote before the item counts as settled. `check-open-questions.sh --procedure` now
  fails on an item with no disposition, a `decision` or `person` item settled outside the register,
  an unquoted fact, a non-hedged item whose `Q<N>` is not above the register's last row when that
  sweep ran (each sweep records it as `- sweep <M> | register through Q<N>`), and any unchecked
  `Step <N> exit` box. A skipped exit step is ticked with `SKIPPED: <reason>`.
