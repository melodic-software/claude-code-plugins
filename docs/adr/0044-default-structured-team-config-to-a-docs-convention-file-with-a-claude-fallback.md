# Default a structured surface's team layer to a docs convention file, with `.claude/<name>` as the fallback

- Status: accepted
- Date: 2026-10-01
- Supersedes, for structured surfaces only: the clause of [ADR 0018](0018-express-team-shared-conventions-as-consumer-convention-docs.md)
  Decision 1 that keeps structured data in dedicated files under `.claude/`. The rest of ADR 0018
  stands.

## Context

[ADR 0018](0018-express-team-shared-conventions-as-consumer-convention-docs.md) Decision 1 expresses
team-shared prose as a convention doc and keeps per-operator-keyed surfaces, structured data,
policy-floor surfaces, and state as dedicated files at `${CLAUDE_PROJECT_DIR}/.claude/<name>`. A
structured surface's team layer therefore lives in `.claude/`, and `.claude/` is not a shared
location: other agents and tools do not read it, and a tool that writes there meets edit
restrictions. The same rules apply to every agent and tool working in the repository, so the team
layer belongs where those readers already look: the repository's convention docs.

A script or hook cannot follow a `CLAUDE.md` or `AGENTS.md` pointer. The `testing` plugin's
scanner and `test-scan` hook run on every test-file write under a 150 ms p95 budget, so they need a
machine-readable block at a known path.

## Decision

1. **The team layer of a structured surface defaults to `docs/conventions/<concern>.md`.** The path
   is fixed relative to the repository root. `<concern>` is the stem of the surface's
   `.claude/<name>` file (`testing` for `.claude/testing.yaml`). The file holds the prose rules for
   the concern plus exactly one fenced config block carrying the same keys as the `.claude/<name>`
   file would.
2. **The block has one form.** Its opening line is three backticks at column 0 followed by the
   language of the `.claude/<name>` file and the word `config`, such as ` ```yaml config ` or
   ` ```json config `. The block body ends at the first line that is exactly three backticks. Rules
   a reader honors:
   - The reader finds the block with one line-by-line pass over the file: no Markdown parser, only
     the opening line above, the closing line, and skipping lines inside any other fenced block, so
     a prose example of the block sits inside a longer outer fence (four backticks) and never counts.
   - The body parses exactly as the `.claude/<name>` file does, and errors name the `.md` file and
     that file's own line numbers.
   - No such block means the docs file does not supply the team layer. An empty block is a block.
   - Two such blocks is an invalid layer, never first-wins: the error names the file and both lines,
     and the layer degrades per the resolution algorithm's malformed-layer rule.
3. **Precedence for the team layer.** The docs block wins. `.claude/<name>` is read as the team
   layer only when the docs file is absent or holds no block. When both exist, the resolver uses the
   docs block and prints one warning line that names both paths and the one it used.
4. **The pointer is a load hint for the model, not a binding for scripts.** A line in `CLAUDE.md` or
   `AGENTS.md`, for example "if testing, read `docs/conventions/testing.md`", loads the doc on
   demand. It sits in the consumer's own prose, not in the marked machine-owned region that binds a
   prose convention home under ADR 0018, and no script reads it. A script reads the fixed path.
5. **The other layers do not change.** The user-global layer stays at `~/.claude/<name>` and the
   gitignored overlay at `.claude/<stem>.local.<ext>`. The merge semantics, the tracked-team and
   gitignored-overlay verdicts, and the root classification of the resolution algorithm apply to the
   docs file as the team layer.
6. **Scope of the supersession.** Only the structured-data category of ADR 0018 Decision 1 changes.
   Per-operator-keyed surfaces, policy-floor surfaces, and mutable state stay dedicated files, and
   the `testing` `run-e2e` surface stays at `.claude/testing/e2e.md`. A surface already expressed
   as a convention doc under ADR 0018 is unaffected.
7. **Adoption is per surface, in that surface's own change.** `testing` adopts first: its resolver
   reads the docs block and falls back to `.claude/testing.yaml`, with the read timed inside the
   hook. The config-cascade README lists every other plugin's `.claude/*` consumer config surface for
   later adoption; none migrates with this decision.

`.claude/<name>` is a supported location, not a retired file. Its fallback read carries no
retirement record and is not the sanctioned dual-read window of ADR 0018 Decision 5. When both
files exist the docs block wins, so a consumer who adds the docs block changes behavior from that
moment, and the warning is how they see it.

## Alternatives considered

- **`.claude/<name>` wins when both exist.** Existing consumers keep their current behavior, and
  the docs file takes effect only where no `.claude` file is present. Rejected: the docs file is the
  location other agents and tools read, so a stale `.claude` file would override the document the
  team maintains.
- **Keep ADR 0018 Decision 1 unchanged.** Structured config stays in dedicated files and only prose
  moves to convention docs. Rejected: it leaves the team layer where other agents and tools do not
  look.
- **Wait for the pending testing plans to settle.** Rejected: those plans add no new `.claude/*`
  config file, so they do not constrain the testing change.

## Consequences

- The config-cascade README gains a location axis and the precedence above, revises its Expression
  doctrine, and lists the surfaces left for later adoption. A change to what the team layer is
  falls under its Versioning rule, so shipping bumps `contract_version` and records it in the
  README's `CHANGELOG.md`.
- A script that reads the block carries its own small reader. The format is fixed so a second
  surface's reader matches the first.
- A consumer who runs both locations sees the warning on every run until they delete one.
- The `testing` hook's added read cost is measured in the testing change, against the 150 ms p95
  budget on WSL.

Recheck when a surface needs a repository-configurable docs location. The pointer file that roots
`standards` ([ADR 0042](0042-ratify-consumer-config-location-outliers-in-place.md)) is the
sanctioned mechanism for it.
