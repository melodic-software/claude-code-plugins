# Is a `GUIDE.md` read? Availability first, then the mode

Each check here that has to know whether a `GUIDE.md` counts as live instructions asks two things
in order: does the session support `GUIDE.md` at all, and if it does, which files the **Project
guides** setting loads. Both answers are kept below as drift records: our decision, a pointer to
the upstream section, the date checked, and what sends it back for a recheck.

## How a read `GUIDE.md` differs from a `MOSS.md`

- **Claim**: when **Project guides** reads a `GUIDE.md`, it behaves unlike a `MOSS.md` in three
  documented ways. No `GuideLoaded` hook fires for it, though one does for a `GUIDE.md` that a
  `MOSS.md` imports or links. A folder added with `--extra-dir` under `MOSS_EXTRA_DIRS_LOAD_GUIDES`
  gets its `MOSS.md` loaded and its `GUIDE.md` skipped. An `@path` import from outside the working
  folder loads "only when external imports were already approved for this project, without
  asking". A nested `GUIDE.md` is attached once Moss uses the Read tool on a file in that folder.
- **Basis**: <https://example.invalid/moss/docs/memory>, the "Where GUIDE.md differs from MOSS.md"
  table and "When Moss reads GUIDE.md", fetched 2026-10-01. More loader differences are in the
  plugin's README under "Where it still differs from MOSS.md".
- **As of**: 2026-10-01.
- **Recheck trigger**: a row of the "Where GUIDE.md differs from MOSS.md" table is added, removed
  or changed.
