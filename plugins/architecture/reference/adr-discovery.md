# ADR discovery ladder

How to find a repository's architecture decision records, and how to infer the numbering and record
shape once they are found. Loaded by `/architecture:record-decision` before it writes, and by
`/architecture:improve` before a scan reads existing records.

ADR placement varies widely, so a single default glob misses most of them. Walk the ladder below
from the working area up to the repository root. **First hit wins**: a nearer directory beats a
further one, and a declaration beats an observation.

## Rung 1. Declared

A declaration is the strongest evidence, because it states intent rather than residue:

- A `.adr-dir` file at the repository root. Its content is the directory.
- A path named in the project's `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, or a documented docs
  convention.
- A standards index entry that names where decisions live.
- A `README.md` or a template file inside a candidate directory: `adr-template.md`, `template.md`,
  `0000-template.md`, `NNNN-template.md`.

A declared directory that does not exist yet still wins. Create it and say why.

## Rung 2. Existing directory

Absent a declaration, look for a directory already holding records:

`docs/adr/`, `docs/adrs/`, `docs/decisions/`, `docs/architecture/decisions/`, `doc/adr/`,
`doc/architecture/decisions/`, `.adr/`, `adr/`, `architecture/decisions/`.

Also any `*.md` whose name matches `adr-*` or `*-decision*`, which catches records kept beside the
code they describe rather than in a directory of their own.

## Rung 3. None

No convention. The caller decides what that means: `/architecture:improve` reads nothing and moves
on; `/architecture:record-decision` names the rungs it searched, offers shapes, and defers.

## Inference: numbering

Parse the identifier prefix of every record in the chosen directory. The next identifier is the
highest existing plus one, at the **same zero-pad width and separator** the existing records use
(`0031-`, `ADR-009-`, `31_` are three different answers to the same question).

A date-prefixed scheme uses today's date in the observed format rather than a counter.

Duplicate identifiers are **reported, never fixed**. Renumbering breaks every inbound link, and the
duplicate is a fact about the repository's history.

## Inference: shape

An explicit template or a directory README wins: it states the intended shape. Absent one, read the
newest two or three records and follow them.

On disagreement between them, follow the **newest** and say so, rather than averaging shapes into a
record that matches nothing.

Keep exactly: the metadata block form (front matter, a status line, a date line, or none), the status
vocabulary in use, and the heading set. A record that reads like the ones beside it is the goal;
matching an external template is not.
