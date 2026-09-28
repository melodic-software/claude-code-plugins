---
description: "Chart one software system's C4 system context from tracked configuration: the focal system, operator-stated actors, and external systems named by connection strings, base URLs, authority endpoints, broker namespaces, and storage accounts. Credentials are redacted before anything is written. Use when: 'map context', 'system context', 'C4 context', 'context diagram', 'what does this system talk to', 'who uses this system', 'external systems from config'. Skip when: the question is many repositories (/architecture:map-landscape) or module depth inside one codebase (/architecture:improve)."
argument-hint: "[system] [--actors <file>] [--focal <name>] [--out <dir>]"
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

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads `landscape_dialect`. It does not add a dialect key, and it does not read
`diagram_dialect.system`.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir` and `landscape_dialect`. Exit 1, 2, and 3
mean there is no declared home to read.

Per key, in order: `--out <dir>` wins for this run alone and does not change the dialect, then a
declared topic-doc value, then one question. `landscape_dialect` falls back to `mermaid`.
`architecture_dir` has NO default. An undeclared and unconfirmed home, including every
non-interactive run, STOPS and points at `/architecture:setup`. A `landscape_dialect` outside
`structurizr` and `mermaid` STOPS and names the accepted set. Do not coerce it.

This skill never writes the consumer's root instruction file or its topic doc. `/architecture:setup
apply` owns both.

## Actors

Actors are operator-stated. Ask once, in an interactive run, who uses the system. Write only the
names and descriptions the operator stated, one `name<TAB>description` line each, to a temp file,
and pass that file as `--actors`. If the operator names nobody, omit `--actors`.

A non-interactive run omits `--actors`. The actors array stays empty. Never fill it from
CODEOWNERS, git history, a README, or a guess.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" \
  --repo "<subject-repo>" --generated-on "<YYYY-MM-DD>" \
  --out "<architecture_dir>/context.json"
```

Add `--focal "<system>"` when the invocation named one. Add `--actors "<file>"` only for
operator-stated rows. The `${CLAUDE_SKILL_DIR}` anchor matters. A bare relative path resolves
against the session's working directory, which is not where the script lives.

The record is schema_version 1 in the one-object-per-line layout the script writes. `focal.origin`
is `derived`. Each external row carries `host`, `kind`, `port`, `file`, `key`, and
`origin: derived`. The value that produced the row is not stored. Actor rows exist only from
`--actors`, and their origin is `operator`.

The collector reads tracked files only (`git ls-files`). It matches JSON, YAML, env, XML, config,
Terraform, Bicep, TOML, properties, ini, and conf text. It skips package manifests and previously
generated architecture artifacts. A gitignored or untracked file is not a source. Configuration is
untrusted text: the script matches it and never executes it.

Redaction is `${CLAUDE_PLUGIN_ROOT}/lib/redact-connection.awk`, the same functions
`map-containers` and `map-deployment` call. A password, account key, token, URL userinfo, or query
string cannot become a field. The closing report quotes the summary line, not a raw value.

`subject` is the github.com origin repository name when that remote resolves, otherwise the
directory basename. `--focal` overrides the name drawn in the center. The helper is inline in
`collect-context.sh`, the same github.com rule `portfolio-facts.sh` uses.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-context.sh" \
  --record "<architecture_dir>/context.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>"
```

Write `context.json` first, then render from it. `mermaid` writes `context.md`: a `C4Context`
diagram with a focal `System`, a `Person` for each operator-stated actor, and a `System_Ext` for
each derived external system. `structurizr` writes `context.dsl`: a `systemContext` view, `person`
elements tagged `Operator`, and external `softwareSystem` elements tagged `External`. One dialect
file is written. The other is not.

The script prints one summary line on stdout:
`context: focal=<name> externals=<n> actors=<n> thin=<yes|no>`.
Keep it for the report. `thin=yes` means no external systems were derived.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Focal**: the name, and whether it came from `--focal` or the repository name.
- **Dialect**: `mermaid` or `structurizr`, and whether the topic doc or the `mermaid` default
  supplied `landscape_dialect`.
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
- Add a dialect key. The context view reuses `landscape_dialect`.
- Read `diagram_dialect.system`. That key is the opt-in container view `/planning:design` emits.
- Fetch anything, or edit a config file. The only writes are `context.json` and `context.md` or
  `context.dsl` under the resolved output directory.
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
- **The diagram set does not include a build-declaration graph.** C4's diagrams are system
  context, containers, components, and code, plus system landscape, dynamic, and deployment.
  Verified 2026-09-28 against <https://c4model.com/> and <https://c4model.com/diagrams>. Recheck
  when either page adds or removes a diagram type.
- **Actors are not derived.** The system-context page lists people as supporting elements and does
  not describe reading them from configuration. This skill records an actor only from an
  operator-stated `--actors` file. A non-interactive run passes no file, and the artifact says so.
- **Mermaid output here has a focal system.** `map-landscape` uses `C4Context` without one, because
  mermaid has no landscape type. This skill's mermaid file is a `C4Context` diagram whose `System`
  is the focal system. The mermaid-C4 experimental fact and its recheck trigger live in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. This skill does not carry a second stamp.
- **The dialect key is `landscape_dialect`.** `diagram_dialect.system` refuses mermaid and is the
  container view. Reusing `landscape_dialect` keeps one format choice for the landscape and this
  context view. The decision is recorded in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`.
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
