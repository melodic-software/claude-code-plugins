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
argument is required. It is a route string or a method name, not a second repository.

## Purpose

Answer "what happens when this entry point runs" from call sites already in the tree. Every hop
traces to a line in a tracked file. The scripts collect and render. Do not add a hop the script
did not emit, and do not bind an interface call to a class that merely has the same method name.

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
`unresolved`), `sync` (`synchronous` or `asynchronous`), and `handoff`.

The shipped adapter reads tracked `*.cs` only. A route attribute or `MapGet`/`MapPost` string
selects the entry when the argument contains `/`. Otherwise the argument is a method name. Two
matches are a refusal that names every site. An entry with no block body (expression-bodied or
abstract) is a refusal. A repository with no C# file is a refusal. That is
the result. Do not fill it from another language.

A call whose receiver is declared as an interface (`I` plus an uppercase letter), or whose method
is `GetService`, `GetRequiredService`, or `CreateInstance`, is `unresolved` and names the
mechanism. It is never followed into a class that happens to implement the method. A unique method
in another file is `inferred`. A unique method in the same file is `statically-resolved`.
`Publish` and `Send` are hand-offs to a broker this skill does not read: the hop is `unresolved`
with mechanism `broker` (`dynamic-publish` when there is no type argument), `handoff` is `yes`,
and `sync` is `asynchronous` whether or not the call is awaited. Every other hop takes `sync` from
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

Consecutive hops that share a role pair, sync, resolution, and handoff collapse to one arrow.
The artifact says how many were collapsed. The table keeps every cited call.

The script prints one summary line on stdout:
`flow: entry=<name> hops=<n> truncated=<yes|no> unresolved=<n> handoffs=<n>`.
Keep it for the report.

When `truncated=yes`, the artifact names the depth and says the sequence stopped. Do not describe
that picture as the whole path.

Exit 1 means the record is unreadable, not schema_version 1, or not in the one-object-per-line
layout. Nothing was written. Report that message. Do not reformat the record by hand.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written` when the run stopped or refused.
- **Entry**: the string, the file, and the line, or the refusal reason when there was no record.
- **Flow**: `hops=`, `unresolved=`, `handoffs=`, `truncated=` quoted from the summary line.
- **Depth**: the number, and the stopping sentence when truncated.
- **Unresolved**: how many, and that none were bound to a guessed implementation.

## What this skill does NOT do

- Bind an interface, a service locator, or reflection to an implementation.
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
  the `Place` method on another class. The hop cites the call site and stops.
- **A truncated trace says so.** `--depth` counts followed callees. A callee that still contains
  a call is why `truncated=yes`. Do not narrate the diagram as complete.
- **A reformatted record reads as empty unless the reader refuses it.** Hops are one
  `{"from_role":` object per line, or the array is `[]` on its key's line. `render-flow.sh`
  exits 1 on any other shape and writes nothing.
- **Tracked C# only.** `git ls-files` is the file set. The adapter does not read project files,
  configuration, or other languages. A comment is not a call. A declaration line is not a hop.
- **ASP.NET route attributes are the entry grammar.** `[Route("...")]` and `[HttpGet("...")]`
  (and the Post, Put, Delete, and Patch attribute forms) match a route entry, as do the same
  quoted strings on `MapGet`/`MapPost` and the other `Map*` methods. Verified 2026-09-28 against
  <https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/routing>, which shows
  `[Route("...")]` and `[HttpGet("...")]` including `[HttpGet("/products3")]`. Recheck when that
  page drops those attribute names. The `Map*` form is the same quoted-route shape; recheck it
  when the minimal-APIs page stops using `MapGet` with a route string.
