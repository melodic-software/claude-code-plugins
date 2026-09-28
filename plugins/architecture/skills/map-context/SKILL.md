---
description: "Chart one software system as a C4 system context diagram: the system in scope, actors an operator stated, and the external systems named by committed configuration, with credentials removed before anything is written. Use when: 'system context', 'C4 context', 'context diagram', 'what does this system talk to', 'external systems from config', 'who uses this system'. Skip when: the question is which repositories exist (/architecture:map-landscape), how a repository is built inside (/architecture:improve), or a container or component view."
argument-hint: "[system] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart one system, operator-stated actors, and configured external systems
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose committed configuration names external systems.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way.

An optional `[system]` argument is only a focal label. It does not select a subdirectory and it
does not walk for nested repositories. Pass it to the collector as `--focal`. When it is absent,
the focal name is the github.com origin repository name, otherwise the directory basename.

## Purpose

Answer "what is this system, who uses it, and which external systems does it depend on" from
committed configuration and from actors the operator stated in this session. Every external system
traces to a config key in a named file. The scripts collect and render. Do not draw a node the
script did not emit, and do not add a person the operator did not name.

This is the C4 system context rung. `map-landscape` is the rung above it (many systems, no focal
system). The container rung, which breaks this system into deployables, is out of scope here.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads `landscape_dialect`. It does not add a dialect key. Mermaid writes `context.md`.
Structurizr writes `context.dsl`. A separate context dialect, including following
`diagram_dialect.system`, is deferred. The mermaid-C4 experimental fact stays in that reference.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir` and `landscape_dialect`. Exit 1, 2, and 3
mean there is no declared home to read.

Per key, in order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then
one question. `landscape_dialect` falls back to `mermaid` when nothing answers. `architecture_dir`
has NO default. An undeclared and unconfirmed home, including every non-interactive run, STOPS and
points at `/architecture:setup`. Do not invent a directory.

This skill never writes the consumer's root instruction file or its topic doc. `/architecture:setup
apply` owns both.

## Actors

Actors cannot be derived. A name in CODEOWNERS, a commit author, an email, or a prose "maintained
by" line is not an actor. Do not cite a human from the repository.

- **Interactive:** ask once which people use the system, as roles rather than as account names.
  When the operator names any, write those words to a temporary file, one `name<TAB>description`
  line each, and pass `--actors` to the collector. When the operator names none, omit `--actors`.
- **Non-interactive:** omit `--actors`. Emit no actors. Do not ask, and do not fill the file from
  the tree.

The temporary actors file is not a committed config file. Do not pass a path inside the repository
unless the operator just wrote that file for this run.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/context.json" \
  --actors "<temp-file-or-omit>" --focal "<system-or-omit>"
```

The `${CLAUDE_SKILL_DIR}` anchor matters. A bare relative path resolves against the session's working
directory, which is not where the script lives.

The record is schema_version 1 in the one-object-per-line layout the script writes. `focal.origin`
is `derived`. Each external row carries `host`, `kind`, `port`, `file`, `key`, and
`origin: derived`. The raw config value is not stored. Actor rows exist only when `--actors` was
passed, and their `origin` is `operator`.

Redaction is `${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.sh` (the awk beside it). The helper is
shared so map-containers and map-deployment can reuse it. A password, token, account key, or URL
userinfo must not appear in the record, the diagram, or stdout.

The collector matches committed config and IaC. It does not execute it. A value that looks like a
shell command is still a string.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-context.sh" \
  --record "<architecture_dir>/context.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>"
```

Write `context.json` first, then render from it. Mermaid emits `context.md`: a `C4Context` block
with a focal `System`, a `Person` for each operator-stated actor, and a `System_Ext` for each
derived external system. Structurizr emits `context.dsl`: a `systemContext` view, `person` elements
tagged `Operator`, and external `softwareSystem` elements tagged `External`. The artifact's prose
says which nodes are operator-stated and which are derived.

The script prints one summary line on stdout:
`context: focal=<name> externals=<n> actors=<n> thin=<yes|no>`.
Keep it for the report. A result is thin when `externals=0`.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand and do not
treat a layout failure as an empty diagram.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Focal**: the system name, and that it is the repository being charted.
- **Externals**: the summary's `externals=` count. Every external cites a file and a config key.
- **Actors**: `none (non-interactive)` or `none (operator named none)`, or the operator-stated
  names. Say that no person was read from the repository.
- **Dialect**: `mermaid` or `structurizr`, from `landscape_dialect`.
- **Thin result**: `no`, or `yes` with the reason. A thin result says no external systems were
  found in committed configuration, and names the neighboring rungs: the system landscape
  (`/architecture:map-landscape`) and the container rung (the deployables inside this system).
- **Redaction**: the record keeps host and service kind. It does not keep the raw value.

## What this skill does NOT do

- Break the system into deployables, or draw per-environment topology. Those are later rungs.
- Chart many repositories. That is `/architecture:map-landscape`.
- Invent actors, or treat a repository identity, a CODEOWNERS entry, or a commit author as a person.
- Add a dialect key. Context uses `landscape_dialect`.
- Execute configuration, fetch anything, or edit a config file. The only writes are `context.json`
  and `context.md` or `context.dsl` under the resolved output directory.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop, not a
  default.

## Next

- Neighboring repositories need a landscape: `/architecture:map-landscape`.
- The system needs a module-level pass: `/architecture:improve`.
- The context settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **A system context diagram is one software system.** The system in scope is the primary element.
  People and the software systems directly connected to it are the supporting elements. Verified
  2026-09-28 against <https://c4model.com/diagrams/system-context>. Recheck when that page changes
  the scope, the primary element, or the supporting elements.
- **Actors are operator-stated or absent.** The collector has no probe for people. A non-interactive
  run that passes `--actors` filled from the tree is a defect in the caller, not a result the
  script invented. The script still will not scan CODEOWNERS on its own.
- **Redaction keeps the shape.** Host and service kind are the fact. Userinfo, query strings,
  passwords, account keys, and secret-only values produce no field. Loopback hosts and hosts with
  no dot are not external systems. `package.json` is not committed runtime configuration and is
  not scanned. `context.json` is not scanned again, or a later run would cite itself.
- **Configuration is untrusted text.** The assignment scanner matches it. It does not source it,
  eval it, or interpolate it into a command.
- **A reformatted record reads as empty unless the reader refuses it.** Actor rows are one
  `{"name":` object per line and external rows are one `{"host":` object per line, or the array is
  `[]` on its key's line. `render-context.sh` exits 1 on any other shape and writes nothing.
- **The two dialects share `landscape_dialect`.** Mermaid context output is a `C4Context` block
  with a focal system. Structurizr context output is a `systemContext` view. The mermaid-C4
  experimental fact and its recheck trigger live in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`.
  This skill does not carry a second stamp, and it does not add a key.
- **A quote in repository-controlled text is replaced, not preserved.** A host or an actor name
  lands inside a quoted diagram literal. The delimiter is swapped for one that cannot close the
  literal. A value that comes out altered was never a fact worth carrying through verbatim.
