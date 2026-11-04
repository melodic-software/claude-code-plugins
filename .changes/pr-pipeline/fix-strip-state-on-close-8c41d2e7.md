---
bump: patch
---

### Fixed

- A closed issue loses its `status: confirmed`, `status: needs-decision`, `status: needs-info`
  and `host-run` labels too, not only the queue labels, whoever closed it. Where the lanes App
  closes the issue, these come off after the close, so a failed close leaves an open issue in its
  state. `attended` stays: only a listed human lifts it.
- The README says that only an issue a listed human opened gives work a Bot filed a spec: a
  listed human's comment on, or edit of, a Bot-filed issue never makes it trusted.
