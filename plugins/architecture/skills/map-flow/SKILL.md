---
description: "Trace one C# entry point into a mermaid sequence diagram. Each hop cites a tracked call site. An interface, service-locator, or reflection hop stays unresolved, and Publish or Send is a hand-off to map-events. Use when: 'map flow', 'sequence diagram', 'trace this request', 'walk me through what happens', 'dynamic diagram from this endpoint'. Skip when: the question is who publishes which message (/architecture:map-events) or which repositories exist (/architecture:map-landscape)."
argument-hint: "<entry point> [--depth N] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Trace one C# entry point into a sequence diagram with a citation on every hop
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked C# contains the entry point.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way. The `<entry point>`
argument is required. It is a route (with an optional leading HTTP verb), `Type.Method`, or a
method name, not a second repository.

## Purpose

Answer "what happens when this entry point runs" from call sites already in the tree. Every hop
traces to a line in a tracked file. The scripts collect and render. Do not add a hop the script
did not emit, and do not bind a call to a class that merely has a method of the same name.

## Resolve home

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads no dialect key: the picture is always a mermaid `sequenceDiagram`.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean there is no declared
home to read.

In order: `--out <dir>` wins for this run alone, then a declared topic-doc value, then one
question. `architecture_dir` has NO default. An undeclared and unconfirmed home, including every
non-interactive run, STOPS and points at `/architecture:setup`.

This skill never writes the consumer's root instruction file or its topic doc. `/architecture:setup
apply` owns both.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-flow.sh" \
  --repo "<subject-repo>" --entry "<entry point>" --depth N \
  --generated-on "<YYYY-MM-DD>" --out "<architecture_dir>/flow.json"
```

`--depth` defaults to 5 when the invocation omits it. The `${CLAUDE_SKILL_DIR}` anchor matters. A
bare relative path resolves against the session's working directory, which is not where the script
lives.

Exit 3 is a refusal. The message states the reason. Nothing was written. Report that reason and
stop. Do not draw a sequence from the files you can see.

The record is schema_version 1 in the one-object-per-line layout the script writes. Each hop
carries `file` and `line` of the call site, `resolution` (`statically-resolved`, `inferred`, or
`unresolved`), `mechanism` (why a hop is unresolved), `sync` (`synchronous` or `asynchronous`),
and `handoff`.

The shipped adapter reads tracked `*.cs` only. The entry is one of:

| Entry | Selects |
| --- | --- |
| `/orders/{id}` | the handler whose `[Route]`, `[HttpGet]`-family attribute, or `MapGet`-family call carries that exact string; a route entry contains `/`, so a template without one (`[HttpGet("{id}")]`) is reached through `Type.Method` |
| `GET /orders/{id}` | the same route, where the handler takes that verb: GET, POST, PUT, DELETE or PATCH in any case, read from an `Http*` attribute beside the route or from the `Map*` name; a handler that names no verb takes any |
| `OrdersService.Handle` | the method `Handle` declared in the class `OrdersService` (the last two names of a dotted entry) |
| `Handle` | every declaration named `Handle` |

A `Map*` call is traced through the method it names as its handler, `MapGet("/x", Handle)` or
`MapGet("/x", Type.Handle)`, declared in the class that holds the call, an enclosing class, or
`Type`. A lambda, or a name that is not exactly one declaration in the tree, is a refusal that
points at `Type.Method`.

More than one match is a refusal that names every site and lists these forms. Nothing else
narrows a match: overloads and same-named types in different namespaces stay ambiguous. A
`[Route(...)]` above a class is not composed with the routes of its methods (a limit): it names no
handler, so a route entry matches only a string written whole on one handler. An entry with no
block body (expression-bodied or abstract) is a refusal. A repository with no C# file is a
refusal. That is the result. Do not fill it from another language.

A call is followed only through its receiver's declared type. The script reads that type from a
parameter or local of the enclosing method, then a field, property or primary-constructor
parameter of the enclosing class, then its in-tree base classes; a type name written at the call
(`Repository.Save`) is its own evidence. It follows the call, and walks the callee, only when the
type is a class in the tree that declares the method. Never bind a call by method name alone.
`resolution` records the evidence:

- `statically-resolved`: the type came from a declaration in the enclosing method or class, or is
  written at the call. The callee may be in another file.
- `inferred`: the type came through a base class or a declaration in another file (a partial
  class), or the method is declared on a base class.
- `unresolved`: anything else, and never followed. `mechanism` says why:

| `mechanism` | Cause |
| --- | --- |
| `interface` | the receiver's type is an interface: one the tree declares, or a name of `I` plus an uppercase letter that no class in the tree declares |
| `dependency-injection` | the call is `GetService` or `GetRequiredService` |
| `reflection` | the call is `CreateInstance` |
| `broker` | `Publish<T>` or `Send<T>`, a hand-off |
| `dynamic-publish` | `Publish` or `Send` with no type argument, a hand-off |
| `external-call` | the receiver's type is outside the tree: a declared type no tracked file declares (`Dictionary`, `Logger`), or a type name written at the call (`Console.WriteLine`, `string.IsNullOrWhiteSpace`) |
| `receiver-type-unknown` | no declaration of the receiver is in reach (a lambda parameter, a `var` initialized from a call), or the call is chained on a result (`.ToList()`) |
| `callee-not-in-tree` | the receiver's type is a class in the tree, but neither it nor an in-tree base class declares the method (an external base class, an extension method, a delegate, a constructor the class does not declare) |
| `ambiguous-method` | the type is declared more than once in the tree, or declares the method more than once (overloads) |

`Publish` and `Send` are hand-offs to a broker this skill does not read: `handoff` is `yes` and
`sync` is `asynchronous` whether or not the call is awaited. Every other hop takes `sync` from
`await`. Neither hand-off is dropped.

Hops are recorded in call order: a followed callee's hops come right after the call that leads to
it, before the caller's next call. An access modifier marks a declaration only as a whole word
at the start of the line, so `_internalService.Run(x)` and `publicUrl = Build(x)` are calls.

`subject` is the github.com origin repository name when that remote resolves, otherwise the
directory basename. The helper is inline in `collect-flow.sh`.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-flow.sh" \
  --record "<architecture_dir>/flow.json" --out "<architecture_dir>"
```

Write `flow.json` first, then render from it. The script writes `flow.md`: a `sequenceDiagram`
whose participants are architectural roles (transport, application, domain, infrastructure, or the
directory name), not every class. Asynchronous hops use `-->>`. Synchronous hops use `->>`. A
handoff names `/architecture:map-events`.

Consecutive hops that share a role pair, sync, resolution, mechanism, and handoff collapse to one
arrow. The artifact says how many were collapsed. The table keeps every cited call.

The script prints one summary line on stdout:
`flow: entry=<name> hops=<n> truncated=<yes|no> unresolved=<n> external=<n> di=<n> handoffs=<n>`.
`unresolved` counts every unresolved hop. `external` counts the `external-call`,
`receiver-type-unknown` and `callee-not-in-tree` hops, `di` the `interface` and
`dependency-injection` hops; the rest are `ambiguous-method`, `reflection` and broker hops. Keep
the line for the report.

When `truncated=yes`, the artifact names the depth and says the sequence stopped. Do not describe
that picture as the whole path.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand.

When `/visualization:mermaid-gate` is enabled, run it on `flow.md` before the report and quote any
failing block's line and error. A failing block is a defect in the render script: report it and
do not repair `flow.md` by hand. When the skill is not enabled, say the diagram was not checked.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped or refused.
- **Entry**: the string, the file, and the line, or the refusal reason when there was no record.
- **Flow**: `hops=`, `unresolved=`, `external=`, `di=`, `handoffs=`, `truncated=` quoted from the
  summary line.
- **Depth**: the number, and the stopping sentence when truncated.
- **Unresolved**: `unresolved=` split into `external=` (framework and other calls outside the
  tree, or on a receiver of unknown type), `di=` (interface and service-locator hops), and the
  remainder, and that none were bound to a guessed implementation.

## What this skill does NOT do

- Bind an interface, a service locator, or reflection to an implementation, or bind any call by
  method name alone.
- Import graphs, timing, or an exhaustive call graph of every class.
- Message topology. A `Publish` or `Send` is a hand-off, not a consumer list. That is
  `/architecture:map-events`.
- Read or add a dialect key.
- Fetch anything, or edit a source file. The only writes are `flow.json` and `flow.md` under the
  resolved output directory.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop, not a
  default.

## Next

- A hop leaves the process at Publish or Send: `/architecture:map-events`.
- The trace settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **A dynamic diagram is one feature, not the structure.** Claim: a C4 dynamic diagram shows how
  elements collaborate at runtime for one feature, story, or use case. Scope is that feature.
  Primary and supporting elements are the author's choice of software systems, containers, or
  components. The sequence style and the collaboration style show the same information. Basis:
  <https://c4model.com/diagrams/dynamic>, fetched 2026-09-28, and the supporting-diagram list at
  <https://c4model.com/diagrams>. As of: 2026-09-28. Recheck when the dynamic-diagram page changes
  the scope or the element rule, or the diagrams index adds or removes dynamic.
- **The picture has no dialect key.** The authoring-formats convention keys only data diagrams
  and C4 system views. A traced sequence is neither, so it stays an unkeyed mermaid
  `sequenceDiagram`, as `/planning:design` draws its sequence flows. The decision is recorded in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`.
- **Participants are roles.** A controller directory is transport, `Application` is application,
  `Domain` is domain, and `Infrastructure` is infrastructure. Other directories keep their own
  name. The artifact says when consecutive hops inside one role pair were collapsed.
- **Unresolved is not a search.** `IOrders _orders` followed by `_orders.Place` does not become
  the `Place` method on another class, and `_cache.Add(x)` does not become the one `Add` method
  in the tree: its receiver is a `Dictionary`, so the hop is `external-call` and is not walked.
  The hop cites the call site and stops.
- **A truncated trace says so.** `--depth` counts followed callees. A callee that still contains
  a call is why `truncated=yes`. Do not narrate the diagram as complete.
- **A reformatted record reads as empty unless the reader refuses it.** Hops are one
  `{"from_role":` object per line, or the array is `[]` on its key's line. `render-flow.sh`
  exits 1 on any other shape and writes nothing.
- **Tracked C# only.** `git ls-files` is the file set. The adapter does not read project files,
  configuration, or other languages. Read: C#. Declined: Node, Go, Python, Rust, JVM, Ruby, and
  PHP; their files are never read, and a tree with no C# file is refused. A comment is not a call. A declaration line is not a hop.
- **ASP.NET route attributes are the entry grammar.** `[Route("...")]` and `[HttpGet("...")]`
  (and the Post, Put, Delete, and Patch attribute forms) match a route entry, as do the same
  quoted strings on `MapGet`/`MapPost` and the other `Map*` methods. Verified 2026-09-28 against
  <https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/routing>, which shows
  `[Route("...")]` and `[HttpGet("...")]` including `[HttpGet("/products3")]`. Recheck when that
  page drops those attribute names. The `Map*` form is the same quoted-route shape; recheck it
  when the minimal-APIs page stops using `MapGet` with a route string. A verb prefix on the entry
  (`GET /orders/{id}`) is matched against the `Http*` attribute names beside the route, or the
  `Map*` name. The script does not compose a class-level `[Route(...)]` with a method route; that
  is a limit of this adapter.
