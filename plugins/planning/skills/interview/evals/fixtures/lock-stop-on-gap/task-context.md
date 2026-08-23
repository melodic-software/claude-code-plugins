# Task context — workspace deletion endpoint (eval fixture)

Everything the user has said before invoking `lock`. Raw material only: this file states what the
user asked for and what the surrounding business context is. It does not label any item as a fact
or a decision, and it does not say what the interview should do — that is what the eval case grades.

## What the user said

> We need a `DELETE /workspaces/{id}` endpoint on the exports service. Only a workspace owner may
> call it. It has to be soft-delete — we've been burned by hard deletes before, and support needs a
> window to undo an accidental one. Membership rows go with the workspace. Return 202 and do the
> teardown asynchronously; the UI already polls the workspace record. I've told you enough — lock
> the brief.

## Surrounding context the user has mentioned in this session

- Support handles roughly one accidental workspace deletion a quarter and has asked for an undo
  path since the last one.
- Finance has twice asked who exported what, and over what period.
- Legal has not been consulted on this endpoint. Nobody has said whether a deletion request is meant
  to read as an erasure request.
- Object-storage spend is tracked but is not currently a flagged concern.

## What a workspace owns at deletion time

Each row lists the shapes its teardown could take. The list is not ordered by anything, and no row
is marked as settled or unsettled.

- The `workspaces` row.
  - Stamp `deleted_at` and keep it. Support can restore it.
  - Delete it outright.
- The `memberships` rows.
  - Stamp `deleted_at` in the same transaction as the workspace.
  - Leave them and filter on the workspace's state.
- The `export_runs` rows — one per completed export, each holding the object-storage key of the file
  it produced.
  - Stamp `deleted_at` alongside the workspace.
  - Delete them as part of the teardown.
- The generated CSV/Parquet files in the exports bucket.
  - Delete them as part of the teardown. Storage stops accruing, and a restored workspace comes back
    without its exports.
  - Keep them for a stated window, then delete. A restored workspace comes back whole and the record
    of what was exported survives; the files outlive the request that asked for the workspace to go.
