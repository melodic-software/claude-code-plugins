---
description: "Chart one software system's deployables and the stores they bind, from committed project files, IaC, and configuration. Use when: 'map containers', 'container diagram', 'what actually runs', 'which deployables', 'shared broker', 'modular monolith', 'C4 container view'. Skip when: the question is which repositories exist (map-landscape), modules inside one deployable (map-components), or environment topology (map-deployment)."
argument-hint: "[system] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart deployables and the stores they bind as a C4 container view
---

## Repository context

The current repository is the subject. Collect its root with one Bash call,
`git rev-parse --show-toplevel`. A failure is an unknown root; ask for a path.
Do not walk the working directory for nested repositories.

## Purpose

Answer "what actually runs, and which stores does it bind" from committed
files. A container is one deployable or one data store. A library shipped
inside a deployable is containment, not another container. Two projects in
the same repository are not an edge.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. Run
`bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"`
and follow the exit code. Exit 0 means read `<home>/architecture/README.md` for
`architecture_dir`. The C4 view dialect is `diagram_dialect.system` in
`<home>/authoring-formats/README.md` (`likec4` or `c4-plantuml`). Absent, the
dialect is unset.

`--out <dir>` wins for this run alone. Then a declared `architecture_dir`.
With neither, including every non-interactive run, stop and point at
`/architecture:setup`. This skill never writes the topic doc.

`mermaid` is not a value of `diagram_dialect.system`. Do not pass it.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-containers.sh" \
  --repo "<root>" --out "<architecture_dir>/containers.json" \
  --generated-on "<YYYY-MM-DD|unknown>" --system "<name>"
```

Pass `--generated-on` from `git -C <root> log -1 --format=%cs`, or `unknown`
when that fails. The script reads git HEAD only. Untracked files are not
evidence. Output kind comes from the project SDK, `OutputType`,
`AzureFunctionsVersion`, or a Dockerfile image. A directory name is not read.
A library referenced by a deployable is a module.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-containers.sh" \
  --record "<architecture_dir>/containers.json" \
  --out "<architecture_dir>" \
  --dialect "<likec4|c4-plantuml|unset>"
```

Unset writes `containers.md` and no C4 view file. `c4-plantuml` also writes
`containers.puml`. `likec4` also writes `containers.likec4`. Modules are named
inside the deployable. They are not drawn as containers.

The summary line is the report's counts. Keep it.

## Close with the report

- **Artifacts**: each path written, or `none written` when the run stopped
  before a home existed.
- **Deployables**: `deployables=`, `modules=`, quoted from the summary line.
- **Stores**: `stores=`, `brokers=`, `binds=`, `shared=`.
- **Thin result**: `no`, or `yes`. A thin result names the component rung for
  what is inside one deployable, `/architecture:map-landscape` for which
  repositories exist, and the deployment rung for environment topology.
- **Dialect**: `unset`, `c4-plantuml`, or `likec4`.
- **Technology**: how many nodes are the literal `unknown`.

## What this skill does NOT do

- Read source, including host-builder calls. Output kind is the project file
  or the image.
- Treat a directory name as an output kind.
- Draw a modular monolith as several services. Libraries are modules.
- Draw an edge because two deployables share a repository.
- Emit mermaid C4. That value is refused by `diagram_dialect.system`.
- Environment topology, message choreography, or the inside of one deployable.
- Fetch, or write outside `<architecture_dir>` (or `--out`).
- Invent a home.

## Next

- A binding is a seam to deepen: `/architecture:improve`.
- The question is which repositories exist, not what runs inside one:
  `/architecture:map-landscape`.
- The view settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **A container is an application or a data store.** Claim: the C4 container
  diagram scopes to one software system, and its primary elements are the
  containers inside that system (a server-side web application, a client
  application, a database, a file store). It does not show clustering or
  failover. Basis: <https://c4model.com/diagrams/container> and
  <https://c4model.com/>. As of: 2026-09-28. Recheck when the container-diagram
  page changes the definition of a container, the scope, or says the diagram
  should show deployment topology.
- **Only committed files are cited.** The collector reads `git HEAD`. A secret
  in an untracked appsettings file is not evidence and is not copied. A
  password, key, or token inside a committed value is removed before write.
  The host remains.
- **Same repository is not an edge.** A shared-infrastructure edge exists when
  two deployables' committed config names the same store host. The edge cites
  both keys.
- **The C4 file follows `diagram_dialect.system`.** Unset means the fact
  report only. The refusal of mermaid and its recheck trigger live in the
  authoring-formats convention, not restated here.
- **24 nodes is this plugin's threshold.** Past it the view aggregates and
  says so. The record stays at container grain.
