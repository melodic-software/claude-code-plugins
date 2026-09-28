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

The shipped adapter is the MassTransit shape: `Publish<T>` is broadcast, `Send<T>` is
point-to-point, `IConsumer<T>` and `AddConsumer<T>` are consumers. Identity is the
namespace-qualified type. In-process calls are `/architecture:map-flow`. A cross-process hop in
that trace is a hand-off to this skill.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`
and reads `landscape_dialect`. It does not add a dialect key. Mermaid writes `events.md` (a
flowchart: dotted broadcast, solid point-to-point). Structurizr writes `events.dsl`.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"`.
Exit 0 means read `<home>/architecture/README.md` for `architecture_dir` and `landscape_dialect`.
Exit 1, 2, and 3 mean there is no declared home.

`--out <dir>` wins for this run. Then a declared `architecture_dir`. Then one question.
`landscape_dialect` falls back to `mermaid`. `architecture_dir` has NO default. An undeclared and
unconfirmed home, including every non-interactive run, STOPS and points at `/architecture:setup`.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-events.sh" \
  --repo "<subject-repo>" --out "<architecture_dir>/events.json"
```

The record is schema_version 1. Message lines start with `{"id":`. Edge lines start with
`{"from":`. Finding lines start with `{"kind":`. Findings include orphan publishers, orphan
consumers, fan-out past `fanout_threshold` (3), competing consumers on one queue, and unresolved
publishes. `fanout_threshold` is this plugin's limit, not the broker's.

A dynamic `Publish(` or `Send(` with no type argument is `resolution: unresolved`. It is never
omitted.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-events.sh" \
  --record "<architecture_dir>/events.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>"
```

Add `--unrouted-only` when the invocation asked for orphans and unresolved edges only. The findings
list is still written.

The script prints:
`events: messages=<n> publishers=<n> consumers=<n> unresolved=<n> orphans=<n> unrouted_only=<yes|no>`.

The artifact's Handoff section is the form `/architecture:map-flow` consumes:
`handoff: map-events contract=<type> direction=<publish|send> file=<path> line=<n>`.

Exit 1 means the record is unreadable or not one object per line. Nothing was written.

## Close with the report

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Messages**: `messages=` from the summary. Say that identity is the resolved type.
- **Edges**: `publishers=`, `consumers=`, `unresolved=`.
- **Findings**: `orphans=` and the other finding kinds present.
- **Filter**: `unrouted_only=` yes or no. Findings are listed either way.
- **Dialect**: `mermaid` or `structurizr`, from `landscape_dialect`.
- **Handoff**: that cross-process edges are in the Handoff section for `/architecture:map-flow`.

## What this skill does NOT do

- In-process synchronous calls. Those are `/architecture:map-flow`.
- Retry, dead-letter, or delivery guarantees.
- Broker hosts, replicas, or partitions. Those are a deployment view.
- Treat two types with the same short name as one message.
- Drop an unresolved publish.
- Add a dialect key. Events use `landscape_dialect`.
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
  stays unresolved rather than being joined.
- **An unresolved publish is a finding.** Dropping it would make an orphan-consumer finding
  wrong. The edge is listed with `resolution: unresolved`.
- **Findings are not the diagram.** `--unrouted-only` filters arrows. The findings list remains.
- **The two dialects share `landscape_dialect`.** Mermaid uses a dotted arrow for broadcast and a
  solid arrow for point-to-point. This skill does not add a key.
- **A reformatted record is refused.** `render-events.sh` exits 1 and writes nothing.
- **The scan is the MassTransit shape.** `Publish<T>`, `Send<T>`, `IConsumer<T>`, and
  `AddConsumer<T>` on one line. Another messaging library is not inferred from a method named
  Publish in a different shape.
