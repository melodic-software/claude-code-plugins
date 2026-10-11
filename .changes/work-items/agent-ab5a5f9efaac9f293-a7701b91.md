---
bump: patch
---

### Fixed

- filter list reads in the provider and order work by created_at

  The tracker seam's list reads now count only matching items against
  limits.list_items_max, and work-loop orders admitted items without a
  GitHub-only flag.

  - Linear sends the state filter (and an optional label) in its GraphQL
    query, so a team with many closed issues lists its open ones complete.
  - list-items is a core verb, and list-items and list-frontier take
    --label. Adapters that declare features.list_items_label_filter (all
    five bundled ones) filter in the provider query; core keeps exact
    matches afterward either way.
  - Every normalized item carries created_at (UTC, or null). work-loop and
    work's oldest-first pick sort on it; a null timestamp sorts last, with
    item number as a fixed tie-break.
  - work-loop passes --scope to both snapshot reads as --label.

- report a labeled GitHub listing at the search cap as truncated

  gh serves a labeled issue list from the search API, which returns at most
  1000 results, so a labeled read reaching 1000 now reports truncated. Jira
  answers a whitespace label with an empty, complete listing instead of a
  usage error, and the adapter generator's list-items guidance names the
  state-in-query and created_at rules.
