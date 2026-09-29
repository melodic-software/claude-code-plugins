---
description: "Draw an entity-relationship diagram from committed schema declarations, with no database connection. Prisma models win over Entity Framework fluent mappings, which win over SQL migrations, and a disagreement is reported. Use when: 'map data', 'ERD', 'entity relationship', 'schema diagram', 'cardinality from mappings', 'which tables relate'. Skip when: the question is deployment topology, runtime state, or data volume."
argument-hint: "[--scope module|all|<module>] [--include-columns] [--dialect mermaid|dbml] [--live] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Draw an ERD from a committed schema, offline
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked files declare the schema.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way.

## Purpose

Answer "what are the entities and how do they relate" from declarations already in the tree. Every
entity and every cardinality traces to a named file. The scripts collect and render. Do not draw a
box the script did not emit, and do not invent a cardinality the script did not record.

This is not a C4 diagram. The C4 set is system context, containers, components, and code, plus
system landscape, dynamic, and deployment. An entity-relationship diagram is none of those.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`.
It does not read `landscape_dialect` and it does not add a dialect key. The diagram dialect is
`diagram_dialect.data` from the authoring-formats topic doc.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean there is no declared
home.

Per key, in order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then
one question. `architecture_dir` has NO default. An undeclared and unconfirmed home, including
every non-interactive run, STOPS and points at `/architecture:setup`. Do not invent a directory.

Resolve `diagram_dialect.data` by restating this ladder, then running the resolver rather than
parsing the topic doc yourself. The ladder is a resolution order, not a task list:

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` with the bundled resolver above. Never hand-parse the root
   file.
3. The printed home is repo-relative: join it to the root, then pass
   `<root>/<home>/authoring-formats/README.md` to the resolver.
4. Layer order is one layer deep: an explicit `--dialect` argument, then the team convention doc,
   then the documented default `mermaid`. There is no personal overlay.
5. Default: `diagram_dialect.data` is `mermaid`. Allowed values are `mermaid` and `dbml`.
6. Degrade soft, and say so. No pointer, no doc, no key, or an unrecognized value each resolve to
   `mermaid`. The resolver names the cause on stderr. Do not hard-fail and do not ask the operator
   to create the surface mid-task.
7. Report provenance: the key, the value, and the layer (`argument`, `team convention doc <path>`,
   or `default`).
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-diagram-dialect.sh" --kind data \
  --formats "<root>/<home>/authoring-formats/README.md"
```

Omit `--formats` when no convention home resolved. Stdout is `mermaid` or `dbml`. An explicit
`--dialect` on the invocation wins and the resolver is not required.

This skill never writes the consumer's root instruction file or its topic doc.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-data.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/data-model.json" \
  --generated-on "<YYYY-MM-DD|unknown>"
```

Pass `--generated-on` from `git -C <root> log -1 --format=%cs`, or `unknown` when that fails.
Pass `--live` only when the invocation asked for a live connection. The script does not open one.
It writes a refusal and does not read the schema.

The record is schema_version 1, one object per line. `status` is `drawn` or `refused`. A refusal
names `reason` and writes no relationships. Shipped tiers, first present wins the diagram:

- **model / prisma.** `*.prisma` model blocks.
- **orm / ef-fluent.** A C# chain `Entity<T>().HasOne<U>().WithMany().HasForeignKey("Column").IsRequired()`,
  or `HasMany<U>().WithOne()`, or `WithOne` for one-to-one, with `IsRequired(false)` when the
  foreign key is optional.
- **migration / sql-migration.** `*.sql` under a `migrations` directory, replayed in path order,
  including `DROP TABLE`.

A second shipped tier that disagrees becomes a mismatch row. The diagram stays on the winning tier.
Django models, SQLAlchemy columns, EF `[ForeignKey]` annotations, an EF lambda chain, and a Prisma
many-to-many with no `fields:` list refuse the record (`partial-read` or a named reason). A shipped
diagram beside an unread mechanism would be a partial read.

A module is the first path segment of the declaring file, or `.` at the repository root.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-data.sh" \
  --record "<architecture_dir>/data-model.json" --out "<architecture_dir>" \
  --dialect "<mermaid|dbml>" --scope "<module|all|id>"
```

Add `--include-columns` only when the invocation asked for columns. The default scope is `module`:
one module is drawn; several modules write a refusal that lists them and the script exits 3. Draw
nothing until the operator passes `--scope <id>` or `--scope all`. In a non-interactive run, stop
after that refusal. Do not pick a module.

Mermaid writes an `erDiagram` inside `data-model.md`. DBML writes `data-model.dbml` and points at
it from `data-model.md`. Column names and types appear in the diagram only with `--include-columns`.
The relationship list and the mismatch list are not a column dump.

The script prints one summary line. Keep it:

`data: status=<drawn|refused> reason=<reason|none> tier=<tier> tool=<tool> modules=<n> entities=<n> relationships=<n> mismatches=<n> columns=<yes|no> dialect=<mermaid|dbml> scope=<id|all|unresolved|none>`

Exit 1 means the record is unreadable or not schema_version 1 in the one-object-per-line layout.
Nothing was written. Report that message. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Status**: `drawn` or `refused`, and the reason when it is a refusal.
- **Source**: the tier and the tool, quoted from the summary, or `none` on a refusal.
- **Dialect**: `mermaid` or `dbml`, and the layer it came from.
- **Scope**: the module, `all`, or `unresolved` with the module list.
- **Columns**: omitted, or included.
- **Mismatches**: the count. A mismatch is reported, not silently resolved.
- **Live**: not requested, or requested and refused. No connection was opened.

## What this skill does NOT do

- Open a database connection, read production data, or compare live rows to the declaration.
- Indexes, data volumes, query plans, lineage, or ETL.
- A C4 view, or a new dialect key. The dialect is the existing `diagram_dialect.data`.
- Adapters other than Prisma models, the EF fluent subset above, and SQL migrations. Other
  mechanisms refuse.
- Guess a cardinality the declaration does not state. Implicit Prisma many-to-many refuses.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop.

## Next

- The schema settles a decision worth keeping: `/architecture:record-decision`.
- The question is which systems the repository sits among: `/architecture:map-landscape`.

## Gotchas

- **The picture is not a C4 diagram.** C4's diagrams are system context, containers, components,
  and code, plus system landscape, dynamic, and deployment. None of those is an
  entity-relationship diagram, so this skill adds no C4 dialect key and reads
  `diagram_dialect.data` (`mermaid` or `dbml`). Verified 2026-09-28 against <https://c4model.com/>.
  Recheck when that page adds a diagram type whose subject is entities and their relationships.
- **A Prisma one-to-many stores the foreign key on the many side.** The scalar named by
  `@relation(fields:, references:)` is the foreign key. The list side does not store a column.
  Required means both the relation field and the scalar omit `?`. Verified 2026-09-28 against
  <https://www.prisma.io/docs/orm/prisma-schema/data-model/relations/one-to-many-relations>.
  Recheck when that page stops using `fields` and `references` to name the foreign key.
- **The EF reader is a subset of the documented fluent chain.** The one-to-many page shows
  `HasMany`/`HasOne`, `WithOne`/`WithMany`, `HasForeignKey`, and `IsRequired`, including the lambda
  form. Verified 2026-09-28 against
  <https://learn.microsoft.com/en-us/ef/core/modeling/relationships/one-to-many>. Recheck when that
  page drops those methods. This adapter reads `HasOne<T>()`, `HasMany<T>()`, and
  `HasForeignKey("Column")` plus `IsRequired()` or `IsRequired(false)`. A lambda chain does not
  name the other entity, so it is refused rather than drawn.
- **A required relationship does not mean the principal has at least one dependent.** The diagram
  uses `||--o{` for a required foreign key. That matches both Prisma and EF: the many side may be
  empty. The same EF page states there is no standard way to require a minimum number of
  dependents. Do not draw `||--|{` from a required foreign key.
- **A reformatted record reads as empty unless the reader refuses it.** Render exits 1 on any
  layout other than one object per line and writes nothing.
- **Tracked files only.** `git ls-files` is the source list. An untracked schema is not a
  declaration. A directory that is not a git repository is a refusal.
- **`--live` is a refusal.** No connection string is read and no client is invoked. Offline tiers
  are not silently substituted.
- **Two mechanisms are not half-read.** Django, SQLAlchemy, and EF data annotations are recognized
  and then the run stops, even when a Prisma schema is also present.
