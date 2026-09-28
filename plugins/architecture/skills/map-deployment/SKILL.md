---
description: "Chart committed infrastructure as a C4 deployment view: which containers sit on which declared nodes, per environment, and what differs between two environments. Use when: 'map deployment', 'deployment diagram', 'what is different in production', 'IaC topology', 'where does this container run'. Skip when: the question is a live cloud inventory, cost, or runtime health."
argument-hint: "[environment] [--diff <env-a> <env-b>] [--live] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart IaC deployment topology per environment, with a diff
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked IaC declares the topology.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way.

## Purpose

Answer "where does this run, and what is different about that environment" from committed
infrastructure as code. Every node traces to a named file. The scripts collect and render. Do not
draw a node the script did not emit, and do not describe a live cloud.

This is the C4 deployment view. One diagram is one deployment environment.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads `landscape_dialect`. It does not add a dialect key. Mermaid writes one `C4Deployment`
block per environment inside `deployment.md`. Structurizr writes `deployment.dsl` with one
deployment view per environment.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir` and `landscape_dialect`. Exit 1, 2, and 3
mean there is no declared home.

Per key, in order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then
one question. `landscape_dialect` falls back to `mermaid`. `architecture_dir` has NO default. An
undeclared and unconfirmed home, including every non-interactive run, STOPS and points at
`/architecture:setup`. Do not invent a directory.

This skill never writes the consumer's root instruction file or its topic doc.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-deployment.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/deployment.json" \
  --generated-on "<YYYY-MM-DD|unknown>" \
  --containers "<architecture_dir>/containers.json"
```

Pass `--generated-on` from `git -C <root> log -1 --format=%cs`, or `unknown` when that fails.
Omit `--containers` when `containers.json` is not already in the architecture directory. When it is
present it must be schema_version 1. An unreadable catalog refuses the run. Pass `--live` only when
the invocation asked for live state. The script does not call a cloud API.

Shipped readers, both when both are present:

- Docker Compose (`compose.yaml`, `docker-compose.yml`, and `compose.<env>.yaml`). The environment
  is the filename suffix, or the parent directory when the file sits under `deploy/<env>/`.
- Kubernetes manifests whose `kind` is Deployment, StatefulSet, DaemonSet, Service, or Ingress.
  The environment is the namespace, otherwise the parent directory.

Terraform, Pulumi, Bicep, CloudFormation, Helm, and Kustomize are recognized. If any of them is
present, the record is refused, including when Compose or Kubernetes is also present. A diagram of
only the shipped tool would be a partial read. A repository whose only IaC is an unshipped tool is
refused as `adapter-not-shipped`, not drawn empty.

Redaction is `${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.sh` for connection-shaped values, and the
collector drops any value whose key or text is secret-shaped. A password must not appear in the
record, the diagram, or stdout. A diff of two secret values says that the parameter differs and
does not print either value.

When `<architecture_dir>/containers.json` exists, container names that the IaC does not place are
listed. When it does not exist, the artifact says container names came from the IaC.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-deployment.sh" \
  --record "<architecture_dir>/deployment.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>" --env "<environment>" --diff "<env-a>" "<env-b>"
```

Omit `--env` to draw every collected environment, one diagram each. Omit `--diff` when the
invocation did not ask for a comparison. The diff table is the first section after the tools. An
unknown `--env` writes a refusal that lists the environments and exits 3. In a non-interactive run,
stop there.

The script prints one summary line. Keep it:

`deployment: status=<drawn|refused> reason=<reason|none> tools=<list> environments=<n> placements=<n> diffs=<n> dialect=<mermaid|structurizr>`

Exit 1 means the record is unreadable or not schema_version 1 in the one-object-per-line layout.
Nothing was written. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Status**: `drawn` or `refused`, and the reason when it is a refusal.
- **Tools**: which IaC tools were shipped readers and which were recognized and declined.
- **Environment**: the one drawn, or each environment, and the file that declared it.
- **Diff**: the summary's `diffs=` count, or that `--diff` was not requested.
- **Dialect**: `mermaid` or `structurizr`, from `landscape_dialect`.
- **Containers**: `map-containers` output was used, or it was absent and names came from the IaC.
- **Secrets**: redacted. No secret value was written.
- **Live**: not requested, or requested and refused. No cloud API was called.

## What this skill does NOT do

- Call a cloud API, use credentials, or compare live state to the declaration.
- Cost, scaling, capacity, or runtime health.
- Apply Helm templates or Kustomize. Those tools are a refusal, not a guessed render.
- Add a dialect key. Deployment reuses `landscape_dialect`.
- Invent a home, a network, or a node the script did not emit.

## Next

- The topology settles a decision worth keeping: `/architecture:record-decision`.
- The question is which systems the repository sits among: `/architecture:map-landscape`.

## Gotchas

- **A deployment diagram is one environment.** Scope is one or more software systems within a
  single deployment environment. Deployment nodes are where instances run, and they nest.
  Infrastructure nodes such as networks and ingress are supporting elements. Verified 2026-09-28
  against <https://c4model.com/diagrams/deployment>. Recheck when that page changes the scope or
  the primary elements. This skill draws one diagram per environment so a diff does not become a
  single mixed picture.
- **The deployment view reuses `landscape_dialect`.** Mermaid output is `C4Deployment`.
  `Deployment_Node` is the deployment element on Mermaid's C4 page. Verified 2026-09-28 against
  <https://mermaid.js.org/syntax/c4.html>. Recheck when that page drops `C4Deployment` or
  `Deployment_Node`. The experimental banner and its recheck trigger live in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. This skill does not carry a second stamp and it
  does not add a key.
- **Compose without a `networks` entry joins the default network.** A service that declares none
  is recorded on `default`. A service that names a network is recorded on that network.
- **A required secret is not a topology fact.** The value is dropped. The diff can say the
  parameter differs. It cannot show the value.
- **Two tools are not half-read.** Seeing Terraform beside Compose refuses the whole record.
- **`--live` is a refusal.** Committed files are not silently substituted for a live comparison.
- **A reformatted record is refused.** Render exits 1 and writes nothing.
- **Tracked files only.** `git ls-files` is the source list.
