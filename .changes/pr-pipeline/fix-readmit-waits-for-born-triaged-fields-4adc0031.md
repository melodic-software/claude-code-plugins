---
bump: patch
---

### Fixed

- work-unblock's readmit sweep no longer parks a born-triaged issue whose Size or Uncertainty is still unset: it waits, with no label, comment or `readmit-per-run` spend, until the filer sets the fields. A field set to a refused value, any other refusal reason, a mid-body marker or an unlisted author still refuses. `check-born-triaged.mjs` exports `notBornTriaged`, so intake and work-unblock share one detection rule.
