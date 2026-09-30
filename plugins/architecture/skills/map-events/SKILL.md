---
description: "Chart async message topology from committed C# publish, send, and consumer registrations. Orphan publishers and consumers are findings. Same short name in two namespaces is two messages. Use when: 'map events', 'who publishes this message', 'message topology', 'orphan consumer', 'publish subscribe'. Skip when: the question is an in-process call trace (map-flow) or broker hosts and replicas (a deployment view)."
argument-hint: "[--unrouted-only] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart publishers, consumers, and orphan messages
---

## Repository context

The current repository is both the CONSUMER and the DEFAULT SUBJECT. Collect the project root with
one Bash call, `git rev-parse --show-toplevel`. A failure is an unknown value; `${CLAUDE_PROJECT_DIR}`
is the root either way.

## Purpose

Answer "who publishes which message, and who consumes it" from committed C# call sites and handler
registrations. Every edge cites a file and a line. The scripts collect and render. Do not add an
edge the script did not emit, and do not drop a publish whose contract type did not resolve.

The shipped adapter is the MassTransit shape: `Publish<T>` or `Publish(new T(..))` is broadcast,
`Send<T>` or `Send(new T(..))` is point-to-point, `IConsumer<T>` consumes `T`. `AddConsumer<C>` and
`ConfigureConsumer<C>` register the consumer class `C`; they are not messages. Inside a
`ReceiveEndpoint("q", ..)` call, on its own line or in its block, they put `C`'s consume edges on
queue `q`; a registration outside it and every publish or send edge has no queue. A message is a type some
publish, send, or consume names; a service or consumer class is not one. Identity is the
namespace-qualified type. In-process calls are `/architecture:map-flow`. A cross-process hop in
that trace is a hand-off to this skill.

## Resolve home

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`.
It reads no dialect key and adds none: it always writes `events.md`, a mermaid flowchart (dotted
broadcast, solid point-to-point). The authoring-formats convention keys a dialect only for data
diagrams and C4 system views. A message-topology flowchart is neither, so it follows the unkeyed
mermaid rule, as `/planning:design`'s sequence flows do.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"`.
Exit 0 means read `<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean
there is no declared home.

`--out <dir>` wins for this run. Then a declared `architecture_dir`. Then one question.
`architecture_dir` has NO default. An undeclared and unconfirmed home, including every
non-interactive run, STOPS and points at `/architecture:setup`.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-events.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/events.json"
```

The record is schema_version 1. Message lines start with `{"id":`. Edge lines start with
`{"from":`. Finding lines start with `{"kind":`. A message line cites the file and line that
declare the type. An edge's `from` is the file of the publishing, sending, or consuming call site,
`to` is the resolved message (`-` when unresolved), and `kind` is `publish`, `send`, or `consume`. Findings include orphan publishers, orphan consumers, fan-out past
`fanout_threshold` (3), competing consumers on one queue, and unresolved edges.
`fanout_threshold` is this plugin's limit, not the broker's.

A short type name resolves through the file's namespace, its parent namespaces, and its `using`
directives, then through the one repo type with that name. A dotted name is tried as written, then
under each enclosing namespace and each `using`; `global::` allows only the as-written match. A
`Publish(` or `Send(` whose type does not resolve (a variable, an anonymous or target-typed `new`,
an undeclared or ambiguous name, a dotted name that matches no declared type) is an edge with
`resolution: unresolved` and an `unresolved` finding naming the kind, the type text or `-`, and
`file:line`. It is never omitted, and an unresolved consumer is never an orphan.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-events.sh" \
  --record "<architecture_dir>/events.json" --out "<architecture_dir>"
```

Add `--unrouted-only` when the invocation asked for orphans and unresolved edges only. The findings
list is still written.

The script prints:
`events: messages=<n> publishers=<n> consumers=<n> unresolved=<n> orphans=<n> unrouted_only=<yes|no>`.

The artifact's Handoff section lists one line per publish or send edge, keyed by `file:line` so it
matches a `/architecture:map-flow` hop cite; map-flow reads nothing from `events.md`:
`handoff: map-events contract=<type> direction=<publish|send> file=<path> line=<n>`.

Exit 1 means the record is unreadable or not one object per line. Nothing was written.

## Close with the report

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Messages**: `messages=` from the summary. Say that identity is the resolved type.
- **Edges**: `publishers=`, `consumers=`, `unresolved=`.
- **Findings**: `orphans=` and the other finding kinds present.
- **Filter**: `unrouted_only=` yes or no. Findings are listed either way.
- **Dialect**: mermaid flowchart. `landscape_dialect` was not read. No key was added.
- **Handoff**: that cross-process edges are in the Handoff section, keyed by `file:line` to match a map-flow hop cite.

## What this skill does NOT do

- In-process synchronous calls. Those are `/architecture:map-flow`.
- Retry, dead-letter, or delivery guarantees.
- Broker hosts, replicas, or partitions. Those are a deployment view.
- Treat two types with the same short name as one message.
- Drop an unresolved publish.
- Read `landscape_dialect` or add a dialect key. The flowchart is always mermaid.
- Invent a home.

## Next

- Trace one entry point up to the broker: `/architecture:map-flow <entry>`.
- The question is which deployables bind the broker: `/architecture:map-containers`.
- The view settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **Publish and send are different.** MassTransit `Publish<T>` is broadcast. `Send<T>` is
  point-to-point. `IConsumer<T>` is a consumer of `T`. Verified 2026-09-28 against
  <https://masstransit.io/documentation/concepts/consumers>. Recheck when that page stops using
  `IConsumer<T>` as the consumer contract, or when the producers page stops distinguishing
  publish from send.
- **Identity is the resolved type.** `Billing.Contracts.OrderPlaced` and
  `Shipping.Contracts.OrderPlaced` are different messages. A short name that matches two types
  stays unresolved rather than being joined, and a dotted name that matches no declared type
  (an external package's contract, for one) stays unresolved rather than being trusted.
- **An unresolved publish or send is a finding.** Dropping it would make an orphan-consumer
  finding wrong. The edge is listed with `resolution: unresolved` and satisfies no consumer.
- **A registered consumer is not a message.** `AddConsumer<C>` names the consumer class. The
  message is the `T` in `C`'s `IConsumer<T>`, so a registration never yields an orphan.
- **Findings are not the diagram.** `--unrouted-only` filters arrows. The findings list remains.
- **No dialect key.** The flowchart is mermaid whatever `landscape_dialect` says: a dotted arrow
  for broadcast, a solid arrow for point-to-point.
- **A reformatted record is refused.** `render-events.sh` exits 1 and writes nothing.
- **The scan is the MassTransit shape, one line at a time.** `Publish<T>`, `Send<T>`,
  `.Publish(new T`, `.Send(new T`, `IConsumer<T>`, `AddConsumer<C>`, and `ConfigureConsumer<C>`.
  A call split across lines is not joined. A `.Publish(` or `.Send(` from another library is
  still listed, not dropped.
- **Only `ReceiveEndpoint("literal", ..)` binds a queue.** A topic, exchange, subject, or
  configuration-file binding is not read, and neither is a queue name held in a variable. A
  consumer bound that way shows no queue, so no competing-consumer finding is raised for it.
