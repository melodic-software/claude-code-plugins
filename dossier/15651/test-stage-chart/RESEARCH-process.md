---
topic: test-stage-chart
section: process
abstract: Phase analyses, fetch log, conflicts, gaps, recency status and the run-owned outcome-gate result
claims: []
produced_by: phase-2
---

# Process

Effort: Source breadth medium (envelope), so Phases 0 to 2 ran and Phases 3 and 4 were skipped.
Research config: corroborators=2, recency 14/30/90 (envelope). Evidence use: publish (envelope).
Nested spawning unavailable, so Phase 2 ran sequentially.

## Phase 0

Corpus bounded: 42 chart entries from the talk digest's slide-31 transcription plus 5 named items;
ledger in `research-checklist.md`, written before any query. Narrowing, stated: the
current-practice note per technique is a one-line pointer, fetched for the two gap techniques the
lens decision turns on (contract, fuzz) and labeled judgment elsewhere.

## Phase 1 analysis

Tools: firecrawl scrape (direct fetch), firecrawl search (returned no web results), perplexity
search, curl plus image view, local find/grep/Read (Tier 0).

- Leading hypothesis: the chart is Sridharan 2018; most repo-applicable techniques are covered;
  production-stage techniques are out of a consumer repo's reach; a full lens is not worth adding.
- Gaps: (1) independent attribution of the chart; (2) who added the three slide-only entries;
  (3) verification plugin skill set; (4) current practice for contract tests; (5) current practice
  for fuzzing; (6) recency of the repository files cited.
- Conflicts: (1) Medium metadata reports published_time 2026-10-16 while the page prints
  Mar 25, 2018.
- Falsification candidate: the chart originated earlier than, or elsewhere than, the 2018 post.

## Phase 2 (one query per gap, plus falsification)

- Gap 1: perplexity search for the post title and stage names; sookocheff.com (2018-09-25) and
  Test Automation University credit the stage model to Sridharan.
- Gap 2: not closed; the 2026 tweet image was not viewed (see Gaps).
- Gap 3: verification skill listing, descriptions and grep, closed.
- Gap 4: perplexity search restricted to docs.pact.io, martinfowler.com, pactflow.io; excerpts only.
- Gap 5: perplexity search restricted to go.dev, google.github.io, llvm.org; excerpts only.
- Gap 6: `git log -1` on the cited files: c527c78 at 2026-11-12; HEAD ca041f2 at 2026-11-12.
- Conflict 1: resolved for the printed date; the metadata timestamp is a later page-modification
  time, and a printed date is what the dating rule accepts.
- Falsification query: perplexity search for an earlier origin of the chart. Result: no earlier
  chart by another author surfaced; the 2018 post itself names a Dec 2017 predecessor by the same
  author with an earlier chart. The hypothesis on authorship stands; the 2018 post is the
  deploy/release/post-release version, and the Dec 2017 chart was not viewed.

## Fetch log

| Claim | URL or command | artifact-ladder rung | tool used | outcome |
|---|---|---|---|---|
| O1 | https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1 | 1, author's own post | firecrawl scrape | carries the claim |
| O1 | perplexity search, post title plus stage names | corroboration | perplexity search | fetched and searched, does not carry the claim (excerpts confirm attribution only) |
| O2 | https://miro.medium.com/v2/resize:fit:1400/1*LFnVVlLrgrvXQ5ScrHVKjg.jpeg | 1, author's own image | curl plus Read (image) | carries the claim |
| O3 | https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1 | 1, author's own post | firecrawl scrape | carries the claim |
| R1 | plugins/testing/skills/plan/SKILL.md at ca041f2 | 1, the repository file | Read | carries the claim |
| R1 | git log -1 on the cited files | changelog | Bash git | carries the claim — ca041f2 (2026-11-12) — current |
| R2 | find plugins skills listing; grep descriptions; grep plugins/verification/skills | 1, the repository files | Bash | carries the claim |
| R2 | git log -1 on the cited files | changelog | Bash git | carries the claim — ca041f2 (2026-11-12) — current |
| R3 | grep over testing, verification, app-control, bugs/scan, review/security-review skills and autonomy/reference | 1, the repository files | Bash grep | carries the claim |
| R3 | git log -1 on the cited files | changelog | Bash git | carries the claim — ca041f2 (2026-11-12) — current |
| P1 | https://docs.pact.io/ | 1, vendor docs | perplexity search excerpt | unresolved |
| P2 | https://go.dev/doc/security/fuzz/ | 1, vendor docs | perplexity search excerpt | unresolved |
| P2 | Go release notes | changelog | none | unresolved — latest Go release not fetched — unresolved |

## Conflicts

1. Medium metadata timestamp (2026-10-16) against the printed date (Mar 25, 2018): resolved for
   the printed date.

## Gaps

- The two lens-sidecar claims on Pact and Go fuzzing (both MEDIUM): read as search excerpts; not fetched directly; no second
  independent corroborator. Checked: Pact docs and Go docs excerpts. Unchecked: direct fetch of
  either page, Go release notes, Fowler's contract-test page, fuzzers for .NET, TypeScript and
  Python.
- Who added formal verification, performance tests and soak tests (the 2026 tweet image or the
  talk's redraw): checked the 2018 image and the digest's slide transcription; unchecked the tweet
  image at x.com/copyconstruct/status/2118539184654938154.
- Current practice for the 38 rows other than contract and fuzz: labeled judgment in the coverage
  table; no source fetched.
- Applicability verdicts (repo or ops) and the lens recommendation are judgment, not claims.

## Recency status

- Sridharan 2018 post: a 2018 article with no release stream; its content claims carry no
  changelog entry.
- Repository files: last change c527c78 (2026-11-12), HEAD ca041f2 (2026-11-12); current.
- Pact docs: printed Aug 25, 2026 on the excerpt; Go fuzzing page undated; both Gaps.

## Outcome gate (run-owned rows)

- 1 PASS: each claim row has a Tier 0/1 source captured this run.
- 2 PASS: no claim row rests on Tier 2 sources alone.
- 3 PASS: each Phase 2 query maps to a numbered gap or conflict above.
- 5 PASS: the falsification query ran and is recorded.
- 6 PASS for accepted claims: repository claims carry a current changelog entry; the 2018 post has
  no release stream; the Go fuzzing claim carries an unresolved verdict and is a Gap.
- 9 PASS: accepted claims came from rung 1, the publisher's own artifact.
- 10 PASS: each absence names sources checked and unchecked.
- 11 and 13: script verdicts, cited in the index.
- 4, 7, 12, 14: verifier-owned; 8: parent-owned.
