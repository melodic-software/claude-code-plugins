## Problem

Merged and abandoned branches pile up in this repository. Nobody sees them until the branch list is
hundreds long, and the weekly maintenance run says nothing about them.

## Requested behavior

- [ ] The weekly maintenance run reports every stale branch: its name, its last commit date, and its
      open pull request, if any.
- [ ] The report deletes nothing. It only lists.

## Open questions

1. Where does the report go: a new issue each week, or one pinned issue that the run edits in place?
2. When is a branch stale: no commit for 30 days, or for 90 days?
