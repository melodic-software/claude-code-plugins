# Worked example — one consumer's standards index

A repository with C# services, a docs lane, and a pre-existing
engineering-philosophy document it did not want to relocate. Standards
root is the default `docs/standards/` (no `.claude/standards.yaml`
needed).

## The index — `docs/standards/README.md`

```markdown
---
standards-contract: 1.0.0
---

# Standards index

Team standards for this repository. Rows route tasks to standards files;
content lives in the files, never here.

| Surface | Applies when | File |
|---|---|---|
| csharp | **/*.cs; C# design, implementation, or review tasks | csharp.md |
| testing | test strategy, writing or reviewing tests | testing.md |
| commits | commit messages, PR titles | commits.md |
| engineering-philosophy | any non-trivial design decision | docs/engineering-philosophy.md |
```

- The first three rows are **in-root**: paths relative to
  `docs/standards/`.
- The last row is **external**: a repo-relative path (forward slashes,
  from the git top-level) to content adopted where it already lives — no
  reorg required. Setup validates the path on every run; a skill that
  finds it broken surfaces the break and offers the fix.

## On disk

```text
docs/standards/
  .gitignore                  # setup-owned; contains *.local.md
  README.md                   # the index above
  csharp.md                   # pure prose, one concern per file
  testing.md
  commits.md
  testing.local.md            # personal overlay — gitignored, never indexed
docs/engineering-philosophy.md  # external row target, tracked as-is
```

## The overlay note

`testing.local.md` overlays `testing.md` by filename convention. It might
ADD "also run mutation tests on touched files" (applied, with the
personal layer named as provenance) or attempt to RELAX a team rule —
which loses: on direct conflict the team-tracked file wins. It is
glob-discovered at load time; the tracked index never lists it.
