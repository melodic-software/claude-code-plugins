---
bump: patch
---

### Changed

- `handoff-evidence.sh` reads the job listing a page at a time. Each read after the first sends
  each page that came with an `etag` as a conditional request, and a `304` reuses the page it
  already read. A `200` whose body was cut off or is empty is now a failed read, as it was under
  `--paginate`, not a listing of no jobs.
- A read that fails, whatever GitHub answered, no longer fails `pr-unblock-dispatch.yml`. A
  listing it cannot read dispatches nothing, and a PR whose reads fail is skipped, each with a
  warning, and the next tick reads them again. Before, a read held only on a `5xx`, or in some
  places a rate limit, and any other failed read ended the run red. A failed dispatch still does,
  and so does a rate limit, which the shared rate guard fails. `fix-ci` still dispatches under its
  caps when it cannot read its required run or the head's check runs for a reason other than a
  `5xx` or a rate limit, as before.
