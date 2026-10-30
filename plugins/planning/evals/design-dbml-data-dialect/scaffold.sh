#!/usr/bin/env bash
# A library-loans service whose root AGENTS.md binds the convention home to docs/conventions,
# where authoring-formats/README.md selects DBML for data diagrams. The graded outcome is that the
# data-scope typed artifact is written in DBML, not the mermaid default.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions/authoring-formats .work/library-loans src

cat >AGENTS.md <<'MD'
# library-loans

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`; read the topic doc there before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD

cat >docs/conventions/authoring-formats/README.md <<'MD'
# Authoring formats

```yaml
diagram_dialect:
  data: dbml
```
MD

printf 'node_modules/\n.work/\n' >.gitignore
printf '{ "name": "library-loans", "type": "module" }\n' >package.json

git add .
git commit -q -m "chore: start library-loans service"

cat >.work/library-loans/PLAN.md <<'MD'
## Brief

### TLDR
Track which member has borrowed which copy of a book, and when it is due back.

### Goal
A member borrows a physical copy of a book and returns it by a due date. A book has many copies;
a copy is on at most one open loan at a time. A member has many loans over time. Each loan records
the borrow date, the due date and the return date, empty while the copy is still out.

### Work size
Medium.

### Constraints
- Store in PostgreSQL.

### Acceptance criteria
- AC1: a copy with an open loan cannot be lent again until it is returned.
- AC2: a member's loan history lists every loan, open and returned.

### Captured assumptions
- Quality bar: production

### Out-of-scope
- Reservations and fines.

### Deferred questions
None.
MD
