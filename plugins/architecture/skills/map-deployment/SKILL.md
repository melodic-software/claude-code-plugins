---
description: "Chart committed infrastructure as a C4 deployment view: which containers sit on which declared nodes, per environment, and what differs between two environments. Use when: 'map deployment', 'deployment diagram', 'what is different in production', 'IaC topology', 'where does this container run'. Skip when: the question is a live cloud inventory, cost, or runtime health."
argument-hint: "[environment] [--diff <env-a> <env-b>] [--dialect likec4|c4-plantuml] [--out <dir>]"
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

This is the C4 deployment view. Each environment is its own deployment environment in the diagram.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`.
It does not read `landscape_dialect` and it does not add a dialect key. The diagram dialect is
`diagram_dialect.system` from the authoring-formats topic doc. `likec4` writes `deployment.md` with
one fenced `likec4` block. `c4-plantuml` writes it with one fenced `plantuml` block. Mermaid is not
offered.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean there is no declared
home.

Per key, in order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then
one question. `architecture_dir` has NO default. An undeclared and unconfirmed home, including
every non-interactive run, STOPS and points at `/architecture:setup`. Do not invent a directory.

Resolve `diagram_dialect.system` by restating this ladder, then running the resolver rather than
parsing the topic doc yourself. The ladder is a resolution order, not a task list:

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` with the bundled resolver above. Never hand-parse the root
   file.
3. The printed home is repo-relative: join it to the root, then pass
   `<root>/<home>/authoring-formats/README.md` to the resolver.
4. Layer order is one layer deep: an explicit `--dialect` argument, then the team convention doc,
   then the documented default. There is no personal overlay.
5. `diagram_dialect.system` has NO default. Allowed values are `likec4` and `c4-plantuml`. When it
   is unset, emit no C4 deployment view. The record is still written.
6. Degrade soft, and say so. No pointer, no doc, no key, or an unrecognized value (mermaid
   included) each resolve to emitting nothing. The resolver names the cause on stderr. Do not
   hard-fail and do not ask the operator to create the surface mid-task.
7. Report provenance: the key, the value, and the layer (`argument`,
   `team convention doc <path>`, or `unset (no C4 view emitted)`).
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-diagram-dialect.sh" --kind system \
  --formats "<root>/<home>/authoring-formats/README.md"
```

Omit `--formats` when no convention home resolved. Stdout is `likec4`, `c4-plantuml`, or `none`.
An explicit `--dialect likec4|c4-plantuml` on the invocation wins and the resolver is not required.

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

Shipped readers, every one that is present:

- Docker Compose (`compose.yaml`, `docker-compose.yml`, and `compose.<env>.yaml`). The environment
  is the filename suffix of `compose.<env>.yaml`, otherwise the parent directory name
  (`deploy/<env>/compose.yaml`), and `default` for a file at the repository root.
  A base file and its `compose.override.yaml`, or the files a tracked `.env` `COMPOSE_FILE` lists,
  merge in Compose merge order into one environment named for the directory. Scalars (`image`,
  `replicas`) are overridden, `ports` and `networks` append without duplicates, `environment`
  merges by key. Any other file beside them (a variant with no listed order, an override with no
  base, a second base) or a `!reset` or `!override` tag is refused as `compose-not-mergeable:<file>`.
  Environment-per-directory layouts are unaffected. Each service is a compute node, and its
  placement names it in `compute`.
- Kubernetes manifests whose `kind` is Deployment, StatefulSet, DaemonSet, Service, or Ingress.
  Each container of a workload, a sidecar included, is its own placement, and every container of a
  workload runs on that workload's one compute node.
  The environment is the namespace, otherwise the parent directory.
  A Service selects the containers of each workload in its namespace whose pod template labels hold
  the whole selector. An Ingress routes to the containers behind each Service its backends name.
  Each is a `relationships` entry from the Service or Ingress node to a container. A selector that
  matches no pod template labels draws nothing.
- Terraform (`.tf`, `.tf.json`, `.tfvars`, `.tfvars.json`), read as text. No `terraform` binary,
  state, or credentials. A root is a directory of configuration that no local module source names.
  Its environments are the `<env>` of an `envs/<env>/` or `environments/<env>/` path, else one per
  `<env>.tfvars` at or above it, else the directory name (`default` at the repository root).
  `terraform.tfvars` and `*.auto.tfvars` apply to every environment of their root and are not
  environments themselves. Containers come from `aws_ecs_task_definition` `container_definitions`
  (`jsonencode([...])` or heredoc JSON), `azurerm_container_app`, `google_cloud_run_v2_service`,
  and `kubernetes_deployment`, `kubernetes_stateful_set`, and `kubernetes_daemonset` (with or
  without `_v1`). Compute nodes are `aws_ecs_cluster`, `aws_eks_cluster`,
  `azurerm_container_app_environment`, `azurerm_kubernetes_cluster`, `google_container_cluster`, and
  each Kubernetes workload. An ECS container runs on the cluster its `aws_ecs_service` names, with
  the service's `desired_count`. A container app runs on the environment its
  `container_app_environment_id` names. A Cloud Run container sits directly in the environment. A
  module-only root follows local module sources, each resource addressed `module.<name>.<type>.<name>`.
  A remote module source, or a local one with no tracked configuration, refuses the record as
  `terraform-module-unread:<file>:module.<name>`, and the source itself is never printed. A file
  that does not parse is `terraform-unreadable:<file>`. A tfvars file with no configuration at or
  above it is `terraform-orphan-tfvars:<file>`.
- Bicep (`.bicep`, `.bicepparam`) and ARM templates (JSON whose `$schema` names
  `deploymentTemplate`, any scope), read as text. No `bicep` or `az` binary, no registry restore.
  A root is a template that no module names. Its environments are one per `.bicepparam` whose
  `using` names it (`main.prod.bicepparam` is `prod`) and one per JSON parameters file
  (`$schema` names `deploymentParameters`): `<name>.parameters.<env>.json` beside `<name>.bicep` or
  `<name>.json`, or `parameters.<env>.json` beside the directory's only template. With none, the
  environment is the directory name (`default` at the repository root). Containers come from
  `Microsoft.App/containerApps` (`template.containers`, `scale.minReplicas`,
  `ingress.targetPort`), `Microsoft.ContainerInstance/containerGroups` (each group is the compute
  node of its containers), and `Microsoft.Web/sites` whose `linuxFxVersion` or `windowsFxVersion`
  is `DOCKER|<image>` (`appSettings` are its parameters). Compute nodes are
  `Microsoft.App/managedEnvironments` and `connectedEnvironments`, `Microsoft.Web/serverfarms`,
  and `Microsoft.ContainerService/managedClusters`. A container app runs on the environment its
  `managedEnvironmentId` or `environmentId` names, a site on its `serverFarmId`: a Bicep
  `<symbol>.id`, or an ARM `resourceId('<type>', <name>)` whose name matches a declared resource.
  A local module (Bicep or ARM) is followed, each resource addressed `module.<name>.<symbol>`. A
  registry or template-spec module, or a local one that is not a tracked template, refuses the
  record as `bicep-module-unread:<file>:module.<name>`, and the source is never printed. A file
  that does not parse is `bicep-unreadable:<file>` or `arm-unreadable:<file>`. A `.bicepparam`
  with `using none`, `extends`, or an untracked `using` target is `bicep-param-unread:<file>`. A
  JSON parameters file with no template to pair is `arm-parameters-unpaired:<file>`. A nested
  `Microsoft.Resources/deployments` resource is `<bicep|arm>-deployment-unread:<file>:<symbol>`.

Pulumi, CloudFormation, Helm (a `Chart.yaml`), and Kustomize are recognized. If any of them is
present, the record is refused, including when a shipped reader also matches. A diagram of only the shipped tool would be a partial read. A repository whose only
IaC is an unshipped tool is refused as `adapter-not-shipped`, not drawn empty. Files under CI
directories such as `.github/` are not IaC and are skipped. A double-brace expression in a Compose
or Kubernetes value (a Go template in a healthcheck) reads normally; one in a name, image,
namespace, replicas, or kind field refuses the file as unreadable.

Every value the collector writes and the renderer prints passes through
`${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.awk`. A parameter whose key names a credential, or
whose value carries one (a connection-string password or key, a SAS signature, a GitHub token, a
cloud access key, a private key, URL userinfo, or an HTTP Basic or Bearer credential), is recorded
with an empty value and `"redacted":"yes"`. Any other emitted field that carries one prints as
`[redacted]`. A secret must not appear in the record, the diagram, the diff, or stdout. A diff of
two secret values says that the parameter differs and does not print either value.

A diff compares two environments of one tool over these kinds, for every shipped reader: a container
present in one environment only, image, replicas, ports, a parameter present in one environment
only, a plain parameter value, a secret parameter that differs, a network (a Compose network or a
Kubernetes Service) or an Ingress present in one environment only, and a network exposure or port
or an Ingress host that differs. A Kubernetes container port
(`containerPort`) is the placement's ports. A Kubernetes `valueFrom` reference counts as a secret
parameter whose presence is compared; `envFrom` is not read. The
report's diff section lists these kinds, and an empty diff reads `No differences of these kinds:
...` so a clean diff is never mistaken for a full comparison.

When `<architecture_dir>/containers.json` exists, container names that the IaC does not place are
listed. When it does not exist, the artifact says container names came from the IaC.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-deployment.sh" \
  --record "<architecture_dir>/deployment.json" --out "<architecture_dir>" \
  --dialect "<likec4|c4-plantuml|none>" --env "<environment>" --diff "<env-a>" "<env-b>"
```

Pass the resolved dialect. With `none` the script still writes `deployment.md` with the tools,
environments, diff, and container tables, and draws no diagram block. Omit
`--env` to draw every collected environment, one deployment environment each inside the one
fenced block. Omit `--diff` when the
invocation did not ask for a comparison. The diff table is the first section after the tools. An
unknown `--env` or `--diff` name writes a refusal that lists the environments and exits 3. In a
non-interactive run, stop there.

The script prints one summary line. Keep it:

`deployment: status=<drawn|refused> reason=<reason|none> tools=<list> environments=<n> placements=<n> diffs=<n> dialect=<likec4|c4-plantuml|none>`

Exit 1 means the record is unreadable or not schema_version 1 in the one-object-per-line layout.
Nothing was written. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Status**: `drawn` or `refused`, and the reason when it is a refusal.
- **Tools**: which IaC tools were shipped readers and which were recognized and declined.
- **Environment**: the one drawn, or each environment, and the file that declared it.
- **Diff**: the summary's `diffs=` count, or that `--diff` was not requested.
- **Dialect**: `diagram_dialect.system`, the value, and the layer (`argument`,
  `team convention doc <path>`, or `unset (no C4 view emitted)`).
- **Containers**: `map-containers` output was used, or it was absent and names came from the IaC.
- **Secrets**: redacted. No secret value was written.
- **Live**: not requested, or requested and refused. No cloud API was called.

## What this skill does NOT do

- Call a cloud API, use credentials, or compare live state to the declaration.
- Run `terraform`, read Terraform state, or fetch a remote module.
- Run `bicep` or `az`, restore a registry module, or evaluate an ARM function.
- Cost, scaling, capacity, or runtime health.
- Apply Helm templates or Kustomize. Those tools are a refusal, not a guessed render.
- Add a dialect key, read `landscape_dialect`, or emit mermaid. The dialect is the existing
  `diagram_dialect.system`.
- Invent a home, a network, or a node the script did not emit.

## Next

- The topology settles a decision worth keeping: `/architecture:record-decision`.
- The question is which systems the repository sits among: `/architecture:map-landscape`.

## Gotchas

- **C4 scopes a deployment diagram to one environment.** Scope is one or more software systems within a
  single deployment environment. Deployment nodes are where instances run, and they nest.
  Infrastructure nodes such as networks and ingress are supporting elements. Basis:
  <https://c4model.com/diagrams/deployment>. As of: 2026-09-29. Recheck when that page changes the
  scope or the primary elements. This skill writes one fenced block with every environment inside
  it as its own deployment environment; `--env` narrows the block to one. The diff is a table, not a picture.
- **C4-PlantUML deployment syntax: read against the README, never run.** Claim: the block uses
  `!include <C4/C4_Deployment>`, `Deployment_Node(alias, label, ?type, ?descr, ...)` with a `{ }`
  body for nesting, `Container(alias, label, ?techn, ?descr, ...)`, and `Rel(from, to, label,
  ...)`. Basis: <https://github.com/plantuml-stdlib/C4-PlantUML/blob/master/README.md>, which shows
  the stdlib include only for `C4_Container` and says the released `C4_...` files ship in the
  stdlib, so the `C4_Deployment` stdlib name is inferred. As of: 2026-09-29. Recheck when that
  README changes those signatures or the include path, or when a host with Java can run PlantUML
  over a rendered block. No PlantUML run has parsed this output. `Rel` is drawn from a
  container to a network node its placement names, and from a Kubernetes Service or Ingress node to
  a container in the record's `relationships`.
- **LikeC4 deployment syntax: parsed by the CLI.** Claim: deployment node kinds are declared as
  `deploymentNode <kind>` in `specification`, nodes nest in `deployment { ... }`, a model element
  is placed with `instanceOf` inside its compute node, a relationship is written
  `<env>.<node> -> <env>.<node>.<instance> '<label>'`, and `deployment view <name> { include
  <env>.** }` draws one environment. Basis: <https://likec4.dev/dsl/deployment/model/>
  (its Deployment relationships section),
  <https://likec4.dev/dsl/deployment/views/>, plus `likec4@1.59.4 validate` exiting 0 on the
  golden blocks in `${CLAUDE_PLUGIN_ROOT}/lib/likec4-golden/` (`deployment-compose.c4`,
  `deployment-kubernetes.c4`), which `collect-deployment.test.sh` diffs against. As of:
  2026-09-29. Recheck when either page changes that syntax or a newer `likec4` release ships: set
  `LIKEC4_VALIDATE=1` when running the test to re-run the CLI.
- **Labels cannot leave the block.** Quotes, backticks, backslashes, and line breaks are stripped
  from labels, `@` prints as `(at)`, and every identifier is prefixed and numbered, so a hostile
  name cannot close the fence, end the diagram, or collide with a keyword.
- **Compose without a `networks` entry joins the default network.** A service that declares none
  is recorded on `default`. A service that names a network is recorded on that network.
- **A required secret is not a topology fact.** The value is dropped. The diff can say the
  parameter differs. It cannot show the value.
- **Two tools are not half-read.** Seeing Pulumi or any other unshipped tool beside Compose
  refuses the whole record. Terraform or Bicep beside Compose is read, since both are shipped.
- **Bicep and ARM values are resolved, never evaluated.** A parameter resolves from a module
  `params` argument, then the environment's parameters file, then its default, and `${name}` inside
  a Bicep string the same way. An ARM value resolves only when it is exactly
  `[parameters('<name>')]`; `[[` opens a literal. A parameter marked `@secure()`, typed
  `securestring` or `secureobject`, or given a Key Vault `reference` is redacted wherever it lands,
  as is a `secretRef` or `secureValue` env entry. Every var, function, and conditional is recorded
  as `unresolved:<expression>`. A `for` or `copy` loop is placed once, an `if` or `condition` is
  ignored, child resources are not read, a `resourceId` with scope arguments matches nothing, a
  site whose fx version does not read `DOCKER|` is not drawn, and `Microsoft.App/jobs` is not
  mapped.
- **Bicep module and parameter file forms.** Claim: a local module path is relative (with or
  without `./`) and may be a `.bicep` file or an ARM JSON template; `br:`, `br/<alias>:`, `ts:`,
  and `ts/<alias>:` are registry and template-spec sources. A `.bicepparam` links its template with
  `using '<path>'` or `using none`, and may `extends` another. Basis:
  <https://learn.microsoft.com/azure/azure-resource-manager/bicep/modules>,
  <https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files>. As of:
  2026-09-29. Recheck when either page changes a path form or the `using` statement.
- **ARM expressions are bracketed strings.** Claim: a string that starts with `[` and ends with `]`
  is an expression, `[[` escapes a literal, and a parameters-file value is always literal. Basis:
  <https://learn.microsoft.com/azure/azure-resource-manager/templates/template-expressions>. As of:
  2026-09-29. Recheck when that page changes the escape rule.
- **Terraform values are resolved, never evaluated.** `var.X` resolves from a module call argument,
  then the root's tfvars files, then the variable `default`, and `${var.X}` inside a string the
  same way. A variable declared `sensitive = true` is redacted wherever it lands. Everything else,
  such as locals, functions other than `jsonencode`, conditionals, for-expressions, `file()`, and
  `templatefile()`, is recorded as `unresolved:<expression>`. `count` and `for_each` are not
  expanded (the resource is placed once), a `dynamic` block is not read, and an env list built by
  an expression records no parameters.
- **Only `./` and `../` sources are local.** Claim: a local module source uses the `./` or `../`
  prefix, and every other source is a registry, VCS, or remote address. Basis:
  <https://developer.hashicorp.com/terraform/language/block/module>. As of: 2026-09-29. Recheck
  when that page changes how a local path is written.
- **Auto-loaded tfvars rank below the environment's file.** Claim: Terraform auto-loads
  `terraform.tfvars`, `terraform.tfvars.json`, and `*.auto.tfvars(.json)`, which outrank
  `terraform.tfvars`. A `-var-file` (the `<env>.tfvars` here) outranks them all, and a variable
  `default` ranks lowest. Basis: <https://developer.hashicorp.com/terraform/language/values/variables>.
  As of: 2026-09-29. Recheck when that page changes the precedence list.
- **`override` is not an environment.** An override merges into its base's environment. A layer with no declared merge order is refused by name, never guessed.
- **`--live` is a refusal.** Committed files are not silently substituted for a live comparison.
- **A reformatted record is refused.** Render exits 1 and writes nothing.
- **Tracked files only.** `git ls-files` is the source list. A tracked symlink is skipped, so it
  cannot pull in an untracked file.
