# Observability by default

Read this before writing or changing code that runs at runtime: a service, an API handler, a
worker or job, a CLI, a hook or a script someone else runs. The rules below hold in every
language and stack. This file names no library, API or configuration format: those come from the
repository and from current research, by the step that follows.

## Resolve the stack first

Before writing the block's logging, telemetry or error handling:

1. Find the project's own logging and telemetry libraries, its configuration layer (where
   settings live, which are committed and which stay local) and its conventions, by the steps in
   `ecosystem-resolution.md` in this folder. The repository's rules, conventions and agent
   instructions win over this file where they differ, and add to it where they say more.
2. When the repository does not settle how one of the rules below is written in its stack (the
   library's current API for templates, scopes or compile-time logging, how its exporter reads
   the environment, where untracked local settings go), invoke `/discovery:research` for the
   current idiomatic form when it is among the available skills (enabled); otherwise read the
   library's own current documentation before writing the code. Never write the form from memory.

## Rules

| Situation | Do | Reason |
|---|---|---|
| Writing a log line | Log a constant message template with named fields for the values (an "order cancelled" event with the order id as a field), never a string built by concatenation or interpolation | The fields stay queryable, and one template groups every occurrence of the event |
| Values every line in a unit of work shares (request id, order id, tenant) | Attach them once with a logging scope or a child logger, not by repeating them in each call | Each line carries the context without each call site having to remember it |
| A log call on a hot path (a loop, a per-request or per-message path) | Use the stack's compile-time or allocation-free logging form, and skip building costly arguments when the level is off | Logging that costs work while disabled taxes every call |
| Sending traces, metrics or logs to a collector | Read the exporter endpoint, headers and service name from the environment (the OpenTelemetry `OTEL_EXPORTER_OTLP_ENDPOINT` family of variables, or the platform's configuration layer), never a literal in code | One build runs in every environment, and no endpoint or key is committed |
| Logging or timing that every request, handler or command needs | Put it in one cross-cutting place: middleware, a decorator, a pipeline behavior, an interceptor | One owner for the concern, and handlers keep only their own logic |
| A method with its own decision worth recording (a branch taken, a retry, a fallback) | Log it inside that method, at the level the event deserves | The cross-cutting layer cannot see the method's own decisions |
| More detail needed while developing | Raise the level locally through untracked config: an environment variable, a git-ignored local settings file, a per-user secret store. Committed config keeps the quiet default | Teammates and deployed environments keep their level; a raised level is never merged by accident |
| Catching an error | Catch where the code can act on it, and record it with the error object (stack included) and the fields that identify the operation; rethrow or return a failure the caller can see | A message without the error loses the stack, and a swallowed error leaves no trace |

Never log secrets, tokens or personal data in a field or a message; redact at the logging layer
when the platform offers it. An error object can carry them too (a client error holding request
headers or a connection string), so log it through a serializer that keeps the type, message,
stack and code and drops the rest.
