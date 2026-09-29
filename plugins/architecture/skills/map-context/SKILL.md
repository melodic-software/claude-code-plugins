---
description: "Chart one software system's C4 system context from tracked configuration: the focal system, operator-stated actors, and external systems named by connection strings, base URLs, authority endpoints, broker namespaces, and storage accounts. Credentials are redacted before anything is written. Use when: 'map context', 'system context', 'C4 context', 'context diagram', 'what does this system talk to', 'who uses this system', 'external systems from config'. Skip when: the question is many repositories (/architecture:map-landscape) or module depth inside one codebase (/architecture:improve)."
argument-hint: "[system] [--actors <file>] [--focal <name>] [--dialect likec4|c4-plantuml] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart one software system's C4 system context from tracked configuration
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked configuration names external systems.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way. A `[system]`
argument is the focal name (`--focal`). It does not select a different tree.

## Purpose

Answer "what is this system, who uses it, and which external systems does its configuration name"
for one software system. Every external node traces to a config key in a tracked file. The scripts
collect and render. Do not draw a node the script did not emit, and do not invent a person.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`.
It does not read `landscape_dialect` and it does not add a dialect key. The diagram dialect is
`diagram_dialect.system` from the authoring-formats topic doc.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean there is no declared
home to read.

In order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then one
question. `architecture_dir` has NO default. An undeclared and unconfirmed home, including every
non-interactive run, STOPS and points at `/architecture:setup`.

Resolve `diagram_dialect.system` by restating this ladder, then running the resolver rather than
parsing the topic doc yourself. The ladder is a resolution order, not a task list:

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` with the bundled resolver above. Never hand-parse the root
   file.
3. The printed home is repo-relative: join it to the root, then pass
   `<root>/<home>/authoring-formats/README.md` to the resolver.
4. Layer order is one layer deep: an explicit `--dialect` argument, then the team convention doc.
   There is no personal overlay.
5. `diagram_dialect.system` has NO default. Allowed values are `likec4` and `c4-plantuml`. When it
   is unset, write `context.json` and `context.md` with the tables, and draw no diagram block.
6. Degrade soft, and say so. No pointer, no doc, no key, or an unrecognized value (mermaid
   included, which the convention refuses) each resolve to emitting no view. The resolver names
   the cause on stderr. Do not hard-fail and do not ask the operator to create the surface
   mid-task.
7. Report provenance: the key, the value, and the layer (`argument`, `team convention doc <path>`,
   or `unset (no C4 view emitted)`).
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-diagram-dialect.sh" --kind system \
  --formats "<root>/<home>/authoring-formats/README.md"
```

Omit `--formats` when no convention home resolved. Stdout is `likec4`, `c4-plantuml`, or `none`.
An explicit `--dialect likec4|c4-plantuml` on the invocation wins and the resolver is not required.

This skill never writes the consumer's root instruction file or its topic doc. `/architecture:setup
apply` owns both.

## Actors

Actors are operator-stated. Ask once, in an interactive run, who uses the system. Write only the
names and descriptions the operator stated, one `name<TAB>description` line each, to a temp file,
and pass that file as `--actors`. If the operator names nobody, omit `--actors`.

A non-interactive run omits `--actors`. The actors array stays empty. Never fill it from
CODEOWNERS, git history, a README, or a guess.

The collector screens each line with the same redactor as config values and skips a line that carries
a credential (`Token=`, `ClientSecret=`, `Bearer <value>`, a cloud key id, URL userinfo), naming the
skip on stderr. Reword the line without the credential and pass it again.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" \
  --repo "<subject-repo>" --generated-on "<YYYY-MM-DD>" \
  --out "<architecture_dir>/context.json"
```

Add `--focal "<system>"` when the invocation named one. Add `--actors "<file>"` only for
operator-stated rows. The `${CLAUDE_SKILL_DIR}` anchor matters. A bare relative path resolves
against the session's working directory, which is not where the script lives.

The collector creates the parent directory of `--out`. Exit 1 means the record could not be written
and nothing was: report the message and stop before rendering.

The record is schema_version 1 in the one-object-per-line layout the script writes. `focal.origin`
is `derived`. Each external row carries `host`, `kind`, `port`, `file`, `key`, and
`origin: derived`. The value that produced the row is not stored. Actor rows exist only from
`--actors`, and their origin is `operator`.

The collector reads tracked files only (`git ls-files`). It matches JSON, YAML, env, XML, config,
Terraform, Bicep, TOML, properties, ini, and conf text. It skips package manifests and previously
generated architecture artifacts. A gitignored or untracked file is not a source. Configuration is
untrusted text: the script matches it and never executes it.

An `http` URL becomes an external system only under a key that names an integration: a key ending in
`url`, `uri`, `endpoint`, `host`, `hostname`, `address`, `authority`, or `server` (`Partner.BaseUrl`,
`ApiBaseUrl`, `Smtp.Host`). A URL under `homepage`, `repository`, `bugs`, `license`, `contact`,
`docs`, `site_url`, `repo_url`, or an OpenAPI `servers` or `externalDocs` entry describes the system
or its documentation, so it draws no node, and neither does a URL under a key with no such name. The
other kinds (`sql`, `storage`, `broker`, `authority`, `cache`, `mail`) are not gated by key name. A
`Data Source` that names a `.db`, `.sqlite`, `.sqlite3`, `.mdb`, or `.mdf` file is a local file, not
a host.

Redaction is `${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.awk`, the same functions
`map-containers` and `map-deployment` call. It scans every value whatever its key. A password,
account key, token, URL userinfo, or query string cannot become a field. The closing report quotes
the summary line, not a raw value.

`subject` is the github.com origin repository name when that remote resolves, otherwise the
directory basename. `--focal` overrides the name drawn in the center. The helper is inline in
`collect-context.sh`, the same github.com rule `portfolio-facts.sh` uses.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-context.sh" \
  --record "<architecture_dir>/context.json" --out "<architecture_dir>" \
  --dialect "<likec4|c4-plantuml|none>"
```

Write `context.json` first, then render from it. `c4-plantuml` writes `context.md` with one fenced
`plantuml` block: a focal `System`, a `Person` for each operator-stated actor, and a `System_Ext`
for each derived external system. `likec4` writes `context.md` with one fenced `likec4` block: the
same elements as `softwareSystem`, `person`, and `externalSystem`, and a `context` view. `none`
writes `context.md` with the node and evidence tables and no diagram block. Every dialect carries
those tables.

The script prints one summary line on stdout:
`context: focal=<name> externals=<n> actors=<n> thin=<yes|no> dialect=<likec4|c4-plantuml|none>`.
Keep it for the report. `thin=yes` means no external systems were derived.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Focal**: the name, and whether it came from `--focal` or the repository name.
- **Dialect**: `diagram_dialect.system`, its value, and the layer: `argument`,
  `team convention doc <path>`, or `unset (no C4 view emitted)`.
- **Context**: `externals=` and `actors=` quoted from the summary line.
- **Actors**: `none` when no `--actors` file was passed, or the operator-stated names when one was.
- **Thin result**: `no`, or `yes`. On `yes`, say that no external systems were found in tracked
  configuration and name the neighboring rungs the artifact names: `/architecture:map-landscape`,
  and containers (the deployables inside this system).
- **Redaction**: the record stores host, kind, port, file, and key. No credential was copied into
  the report.

## What this skill does NOT do

- Invent an actor, or treat CODEOWNERS, commit authors, or prose as people.
- Execute configuration, or interpolate a value into a shell command.
- Break the system into deployables, draw a per-environment deployment, or chart many repositories.
  Those are other rungs.
- Add a dialect key, read `landscape_dialect`, or draw mermaid C4.
- Fetch anything, or edit a config file. The only writes are `context.json` and `context.md` under
  the resolved output directory.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop, not a
  default.

## Next

- The question is which systems exist across repositories: `/architecture:map-landscape`.
- The context settles a dependency decision worth keeping: `/architecture:record-decision`.
- One repository on the context needs its own module-level pass: `/architecture:improve`.

## Gotchas

- **Scope is one software system.** A system context diagram draws that system in the center,
  with people and the other software systems directly connected to it. Primary element: the
  software system in scope. Supporting elements: people and those other software systems. Verified
  2026-09-28 against <https://c4model.com/diagrams/system-context>. Recheck when that page changes
  the scope, the primary element, or the supporting elements.
- **Actors are not derived.** The system-context page lists people as supporting elements and does
  not describe reading them from configuration. This skill records an actor only from an
  operator-stated `--actors` file. A non-interactive run passes no file, and the artifact says so.
- **The dialect key is `diagram_dialect.system`, and it has no default.** Every C4 view of the code reads the key
  the authoring-formats convention assigns to
  C4 system views, which refuses mermaid because mermaid C4 is experimental. An unset key is the
  common case: the run still writes `context.json` and a `context.md` with no diagram, and the report says no
  view was emitted. The
  key is documented in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`.
- **Redaction keeps the shape.** Host, service kind, and an optional numeric port. A secret-only
  key (`Password`, `ClientSecret`, `AccountKey`, and the rest named in `redact-connection.awk`)
  produces no row. Loopback hosts are not external systems. Do not paste a raw value into the
  report to show the work.
- **A reformatted record reads as empty unless the reader refuses it.** Actors are one `{"name":`
  object per line and externals are one `{"host":` object per line, or the array is `[]` on its
  key's line. `render-context.sh` exits 1 on any other shape and writes nothing.
- **Tracked files only.** `git ls-files` is the file set. A gitignored `.env` and an untracked
  config file contribute no node, which is what keeps a local secret file out of a committed
  diagram.
- **package.json is not configuration.** Its homepage and token fields are not external systems.
  A previously written `context.json` is not re-read as evidence.
