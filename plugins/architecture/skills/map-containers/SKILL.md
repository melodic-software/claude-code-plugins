---
description: "Chart one software system as a C4 container diagram: deployables identified by project output, host builder, Dockerfile, or process manifest, the stores and brokers they bind in committed configuration, and the modules contained in one deployable. Use when: 'map containers', 'container diagram', 'what actually runs', 'deployables and databases', 'modular monolith', 'which services bind to which broker'. Skip when: the question is which repositories exist (map-landscape), what is inside one deployable (map-components), or environment topology."
argument-hint: "[system] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart deployables, the stores they bind, and contained modules
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose committed files name deployables and stores.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way.

An optional `[system]` argument is only a focal label. It does not select a subdirectory and it
does not walk for nested repositories. Pass it to the collector as `--focal`. When it is absent,
the focal name is the github.com origin repository name, otherwise the directory basename.

## Purpose

Answer "what actually runs, and which stores does it bind" from committed project files, Dockerfiles,
process manifests, and configuration. Every deployable cites the fact that made it a container.
Every store cites a config key. The scripts collect and render. Do not draw a node the script did
not emit, and do not turn a directory name into a service.

This is the C4 container rung. `map-landscape` is the rung above it. What is inside one deployable
is `/architecture:map-components`. A request trace is `/architecture:map-flow`.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads `landscape_dialect`. It does not add a dialect key and it does not read
`diagram_dialect.system`. Mermaid writes `containers.md` (`C4Container`). Structurizr writes
`containers.dsl` (a container view).

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

## Build the record

When `<architecture_dir>/dependency-graph.json` already exists and is schema_version 1, pass it as
`--graph`. Containment then comes from that graph's project edges and is not re-derived. Otherwise
omit `--graph`. The collector reads `ProjectReference` Include attributes itself and records
`containment` as `project-references`.

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-containers.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/containers.json" \
  --focal "<system-or-omit>" --graph "<dependency-graph.json-or-omit>"
```

The `${CLAUDE_SKILL_DIR}` anchor matters. A bare relative path resolves against the session's working
directory, which is not where the script lives.

The record is schema_version 1 in the one-object-per-line layout the script writes. Container lines
start with `{"id":`. Module lines start with `{"container":`. Edge lines start with `{"from":`.
A deployable `kind` is `web`, `api`, `worker`, `cli`, `function`, or `process`. A store `kind` is
`store`. `technology` is a runtime, framework, or image, or the literal `unknown`. An edge `kind`
is `uses` or `shared-infrastructure`. The shared-infrastructure evidence cites every config key.

Redaction is `${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.sh` (the awk beside it). A password,
token, account key, or URL userinfo must not appear in the record, the diagram, or stdout.

The collector matches committed files. It does not execute them. A class library is a contained
module, not a container, even when its directory name sounds like a service.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-containers.sh" \
  --record "<architecture_dir>/containers.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>"
```

Write `containers.json` first, then render from it. Mermaid emits `containers.md`. Structurizr emits
`containers.dsl`. Contained modules are named on their deployable. They are not drawn as containers.

The script prints one summary line on stdout:
`containers: focal=<name> deployables=<n> stores=<n> modules=<n> edges=<n> shared=<n> unknown_technology=<n> thin=<yes|no>`.
Keep it for the report. A result is thin when `deployables=0`.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand and do not
treat a layout failure as an empty diagram.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Focal**: the system name, and that it is the repository being charted.
- **Deployables**: the summary's `deployables=` count, and that kind came from output type, host
  builder, Dockerfile, or process manifest.
- **Stores**: the summary's `stores=` count. Every store cites a file and a config key.
- **Modules**: the summary's `modules=` count. A modular monolith is one container.
- **Shared**: the summary's `shared=` count. Each shared-infrastructure edge cites every config key.
- **Dialect**: `mermaid` or `structurizr`, from `landscape_dialect`.
- **Technology**: `unknown_technology=` from the summary. `unknown` is literal, not a guess.
- **Containment source**: `dependency-graph.json` or `project-references`.
- **Thin result**: `no`, or `yes` because no deployable was found. Name `/architecture:map-landscape`
  when the question was which repositories exist.
- **Redaction**: the record keeps host and service kind. It does not keep the raw value.

## What this skill does NOT do

- Draw environment topology, replicas, or scaling. That is a later deployment rung.
- Chart the modules inside one deployable as their own diagram. That is `/architecture:map-components`.
- Trace a request. That is `/architecture:map-flow`.
- Add a dialect key. Containers use `landscape_dialect`.
- Execute configuration, fetch anything, or edit a project file. The only writes are
  `containers.json` and `containers.md` or `containers.dsl` under the resolved output directory.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop, not a
  default.
- Treat two projects in one repository as an edge. An edge needs a cited config key or a configured
  endpoint.

## Next

- What is inside one deployable: `/architecture:map-components`.
- A request trace from one entry point: `/architecture:map-flow`.
- Neighboring repositories need a landscape: `/architecture:map-landscape`.
- The view settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **A container diagram is one software system.** The primary elements are the containers inside
  that system. Deployment concerns such as clustering and failover are not this diagram. Verified
  2026-09-28 against <https://c4model.com/diagrams/container> and <https://c4model.com/>. Recheck
  when the container-diagram page changes its scope, its primary elements, or moves deployment
  concerns onto this diagram.
- **Directory names are not deployables.** `Microsoft.NET.Sdk.Web` in a directory named Worker is a
  web host. A class library in a directory named Api is a module. Host-builder usage is read only
  for a project that is already an entry point (web SDK, worker SDK, functions, or `OutputType` Exe).
- **A modular monolith is one container.** Libraries reached by project references are listed as
  contained modules. They are not drawn as containers. When `dependency-graph.json` is passed, those
  edges are the only containment. A `ProjectReference` the graph does not have is not a module.
- **Shared infrastructure cites both keys.** Two deployables that name the same broker host produce
  one `shared-infrastructure` edge whose evidence lists every config key. Sitting in the same
  repository does not.
- **Redaction keeps the shape.** Host and service kind are the fact. Userinfo, passwords, account
  keys, and secret-only values produce no field. The raw value is not stored. `package.json` is not
  scanned. `containers.json` is not scanned again.
- **`unknown` is a technology value.** A Dockerfile with no `FROM`, or a compose service with no
  image, is technology `unknown`. Do not invent a runtime from the service name.
- **The two dialects share `landscape_dialect`.** Mermaid output is a `C4Container` block.
  Structurizr output is a `container` view. This skill does not read `diagram_dialect.system`.
  The mermaid-C4 experimental fact and its recheck trigger live in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. This skill does not carry a second stamp.
- **A reformatted record reads as empty unless the reader refuses it.** `render-containers.sh`
  exits 1 on any other shape and writes nothing.
- **Configuration is untrusted text.** The assignment scanner matches it. It does not source it,
  eval it, or interpolate it into a command.
- **A quote in repository-controlled text is replaced, not preserved.** A name lands inside a
  quoted diagram literal. The delimiter is swapped for one that cannot close the literal.
