# Defer GitBook as a knowledge-vault remote backend

- Status: accepted
- Date: 2026-07-14

## Context

The knowledge-vault seam (topic-docs contract, in flight on `feat/topic-docs-seam`) names remote documentation platforms as candidate `vault_backend` values, with GitBook via its MCP server as the worked example. GitBook was evaluated as the first remote backend: multi-agent research over official docs, the live OpenAPI spec, and community evidence, plus empirical tests against a sandbox space on the free plan (REST API and the official MCP server at `mcp.gitbook.com/mcp`).

What the evaluation established:

- Service strengths: free at solo scale (1 user, unlimited private spaces, no API metering), 5000 requests/hour per token, ~500 ms page reads, near-instant search indexing after merge, a writable MCP server whose `invoke_operation` tool reaches the full REST API, and publishing surfaces (`llms.txt`, per-site read-only MCP, and Git Sync). GitBook documents Git Sync as bidirectional; a future mirror would therefore be a consumer-enforced operating policy, not a one-way product mode.
- Storage disqualifiers, all reproduced empirically:
  - No concurrency control. Fifteen parallel writers against one page all reported success while the page became a silent concatenation of every version; merges of stale change requests report `result: "merge"` and append both versions. No ETag/If-Match/revision precondition exists anywhere in the API.
  - Non-idempotent writes. Every write demotes markdown headings one level (H1 is reserved for the page title; H4+ collapses to bold text), so read-modify-write cycles progressively corrupt structure.
  - Metadata loss. YAML frontmatter — including custom keys — is stripped on write. Artifact conventions built on frontmatter (type/date/topic/session chains) cannot round-trip. GitBook tags are beta and not searchable.
  - GFM normalization. Input is re-serialized to GitBook's canonical dialect (`-` → `*`, `---` → `***`, `*italic*` → `_italic_`, reference links inlined, blockquote line breaks collapsed), so strict markdownlint output fails and lint-clean GFM cannot survive.
  - No binary upload API. File endpoints are read-only; attachments enter only through the editor UI or Git Sync commits, with a 100 MB per-file cap.
- Vendor posture: no SLA on any plan, 60-day post-termination export window, 7-day space trash, and a 2024 repricing history that moved features behind per-site fees.

The alternative — git as the storage layer (in-repo `docs/` vault default; the LFS-backed `knowledge-corpus` corpus for ingest-pipeline outputs per the existing knowledge-integration design) — meets every bar the storage disqualifiers fail, and GitBook's genuine value (hosted browse, search, publishing, read MCP) remains capturable later through separately reviewed mirror automation that keeps git authoritative and prevents GitBook-originated edits from becoming source.

The evaluation also clarified why GitHub Issues succeed as an agent-written record store where GitBook fails: concurrency safety is a property of the data model, not the platform. Editing an issue body is the same unguarded lost-update write GitBook has, but the idiomatic Issues pattern is append-only — each record is a new issue or comment, and appends cannot conflict. GitBook offers no append primitive; every write mutates a page. Issues additionally keep GFM byte-exact and expose real metadata filters (labels, milestones, search qualifiers) that GitBook's beta tags lack, at zero cost — which is why the work-items edge binds to a tracker and the vault edge binds to git, and why neither binds to GitBook today. Issues remain wrong for curated long-form documentation (no hierarchy, no document model, no official attachment-upload API), so they complement rather than replace the vault. Other hosted stores evaluated and rejected for the same storage-layer reasons as GitBook: Notion and Confluence (proprietary block stores, normalized export), self-hosted Outline/Docmost (ops burden), GitHub wikis (git-backed rendering, no content API beyond git-cloning the `.wiki.git` repo) and Azure DevOps wikis (a content REST API exists — Create Or Update, Update, Get, Delete — but no PR/review flow) — both dominated by a plain repo. Large binaries that exceed LFS comfort belong in GitHub Releases assets, which are API-uploadable up to 2 GB per file.

## Decision

Git remains the storage layer for the knowledge-vault seam. GitBook is deferred as a `vault_backend` value rather than excluded; its acceptable role today is a consumer-enforced mirror of a git source of truth, under separately reviewed automation that prevents GitBook-originated edits from becoming source. It is never a write target for agents.

Revisit when any of these triggers fire:

1. GitBook ships optimistic concurrency for content writes (revision preconditions or equivalent compare-and-swap on change-request merge).
2. GitBook ships lossless metadata round-trip (frontmatter preservation or a queryable tag/metadata API out of beta).
3. A concrete need appears for zero-clone write access that a git-backed vault cannot serve.

Any future enablement must carry the write guardrails the evaluation produced: one logical writer per page, every write composed fresh in canonical form (never echoing read-back markdown), merge `result` checked and `"conflicts"` treated as an incident, and a separately controlled git-authoritative mirror as the backup path.

## Consequences

- The vault seam keeps zero external dependencies by default; no plugin gains a GitBook code path now, and the seam's degradation contract (unavailable backend falls back to `docs/`) stays untested against a real remote backend for the time being.
- Hosted browse/search/publishing for vault content is not available until a mirror is stood up; agents rely on git and local search.
- The evaluation evidence (bench harness, fixture round-trip results, API gotchas: `update_page` requires page IDs, explicit slugs are ignored) is preserved with this record for the next assessment rather than re-derived.
- Adopting the ADR convention here requires the `architecture-decisions` component to be added to this repository's managed list in `standards/distribution/sync-manifest.yml`, so the convention README and template arrive through a reviewed sync PR rather than a hand copy.

## Sources

- [GitBook API quickstart](https://gitbook.com/docs/developers/gitbook-api/quickstart) — the API explicitly reads and writes spaces/pages and uses user-scoped access tokens.
- [GitBook API reference](https://gitbook.com/docs/developers/gitbook-api/api-reference) and [hosted OpenAPI specification](https://api.gitbook.com/openapi.yaml) — the authoritative operation/schema inventory used for the API review.
- [GitHub & GitLab Sync](https://gitbook.com/docs/getting-started/git-sync) — GitBook documents Git Sync as bidirectional.
