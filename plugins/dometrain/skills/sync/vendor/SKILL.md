---
name: dometrain-grounding
description: Use when implementing, designing, reviewing, or debugging anything a Dometrain course covers (C#/.NET, ASP.NET Core, EF Core, testing, design patterns, architecture, messaging, databases, cloud/DevOps, TypeScript, AI development) — ground the approach in how the course teaches it via the Dometrain MCP server and cite lessons with timestamped deep links.
---

<!-- Vendored from https://github.com/Dometrain/mcp, MIT licensed. Source: skills/dometrain-grounding/SKILL.md. See ../context/update.md for the sync protocol. -->

# Dometrain Grounding

The Dometrain MCP server exposes curated documents for Dometrain's video-course lessons:
summaries, key concepts, cleaned lesson notes, and the exact code shown on screen — each
with a deep link into the moment of the video it came from. Use it so your implementation
matches how the user's courses teach the topic, and so the user can jump to the source.

## When to consult Dometrain

Search Dometrain BEFORE settling on an approach when the task touches something its
courses cover. Coverage is deepest across the .NET ecosystem — C# language internals,
ASP.NET Core (REST and minimal APIs, gRPC, GraphQL, SignalR, Blazor, authentication),
EF Core and Dapper, testing (unit, integration, TDD), design patterns and SOLID, clean
code and refactoring — plus software architecture (microservices, modular monoliths,
DDD, clean/vertical slice, event-driven, event sourcing), messaging (MassTransit,
NServiceBus), databases (SQL Server, PostgreSQL), cloud and DevOps (Azure, AWS,
Kubernetes, Docker, GitHub Actions, OpenTelemetry, Aspire), Git, TypeScript, and
AI-assisted development (AI agents, MCP, RAG).

Skip it for topics clearly outside the catalog (call `list_courses` with a topic filter
if unsure whether something is covered).

## Tool workflow

1. **Conceptual queries** → `search_dometrain(query, tech?, max_results?)` with a
   natural-language description of what you are implementing (e.g. "validate JWT tokens
   in ASP.NET Core minimal APIs"). Ranking is hybrid keyword + semantic, so phrase the
   query naturally rather than keyword-stuffing. Results are ranked lesson excerpts; a
   note tells you when hits are partial-term or semantically related rather than exact
   keyword matches.
2. **Code-shaped queries** → `search_code(query, language?, max_results?)` with an
   identifier, API name, or short code fragment (e.g. `AddAuthentication`,
   `IAsyncEnumerable`). Returns the on-screen code with a deep link to the exact moment
   it appears.
3. **Drill in** → `get_lesson(lesson_id)` for the full curated lesson document before
   writing nontrivial code based on a search hit.
4. **Explore** → `list_courses(topic?)` and `get_course(course_id_or_slug)` to see what
   exists and which lessons have documents (`has_document`).

## Citing lessons

When lesson content shapes your code or explanation, cite the deep link so the user can
watch the source, e.g.:

> Following the approach from [Design Patterns in C#: Builder — Implementing the Classic
> Builder](https://dometrain.com/take/course/design-patterns-in-csharp-builder-2845456/implementing-the-classic-builder-pattern-57337052/?t=135)

Use the `deep_link` values returned by the tools verbatim (the `?t=<seconds>` fragment
jumps to the right moment). Name the course using the returned `course` field.

## Quota etiquette

Requests are limited per calendar month per account (all keys share the pool) with a
short per-minute burst cap.

- Do not repeat an identical search in the same session — reuse what you already fetched.
- Prefer one `get_lesson` over re-searching for more snippets of the same lesson.
- Responses include a `quota_note` once ≥90% of the monthly quota is used; slow down when
  you see it. On a 429, the response carries the reset date — call `get_usage()` if the
  user asks where they stand, and do not retry until reset (burst-cap 429s can be retried
  after a short pause).
