---
description: "Every file under docs/ is named in lower-kebab-case, with README.md, CHANGELOG.md, INDEX.md, docs/topics/, and code files exempt; scripts/check-docs-naming.sh --check is the gate; read before adding or renaming a docs/ file"
paths:
  - "docs/**"
---

# docs/ file naming

Name every file under `docs/` in lower-kebab-case: lowercase letters, digits, and single hyphens,
with a lowercase extension (`plugin-philosophy.md`, `0001-first.md`, `v1.2.schema.json`). Never an
uppercase letter, an underscore, or a space in the basename.

Exempt, and only these:

- `README.md`, `CHANGELOG.md`, and `INDEX.md` anywhere under `docs/`, the conventional uppercase
  names tooling and forges look for by exact spelling (`INDEX.md` is the topic-docs convention's
  reserved index name).
- Everything under `docs/topics/`, the branch-only contract slice whose file names (`PLAN.md`,
  `BRIEF.md`) belong to the topic-docs convention and are pruned before merge.
- Code files by extension (`.py`, `.sh`, `.mjs`, `.js`, `.ps1`), whose casing is the language's
  convention.

No two tracked paths under `docs/` may differ only by case. A case-insensitive checkout (Windows,
macOS) writes the second over the first, so a lowercase file can never sit beside its uppercase
twin, and a rename is a hard cutover: move the file with `git mv`, repoint every citation in the
same pull request, and bump every plugin whose body cites it.

The gate is `scripts/check-docs-naming.sh --check`, which the `lint` job runs on every pull
request. This rule loads when a covered file is read, never when one is created, so run the gate
before pushing a new `docs/` file; the rule alone cannot catch it.

Why: `docs/` carried a mix of UPPER-KEBAB, lower-kebab, and mixed-case names, and every citation
had to remember which spelling one file used. One rule means a new name needs no lookup and a
rename never happens twice. The decision, its exemptions, and the hard-cutover consequence are
recorded in the ADR named below.

Decision record:
[ADR 0033](../../docs/adr/0033-name-docs-files-lower-kebab-case-with-conventional-exceptions.md).
