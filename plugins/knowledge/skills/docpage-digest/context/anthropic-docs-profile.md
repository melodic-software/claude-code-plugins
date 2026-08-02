# Publisher profile — Anthropic docs

Publisher-specific configuration for `/knowledge:docpage-digest` runs against Anthropic
documentation properties (`platform.claude.com`, `code.claude.com`, `claude.com/blog`). The
pipeline engine in `SKILL.md` stays generic; everything here is this publisher's own contract.
A second publisher joins as a sibling profile file; engine extraction waits for the third
(Rule of Three).

## Fetch channel

- **Docs pages (`platform.claude.com/docs/...`, `code.claude.com/docs/...`):** append `.md` to
  the page URL for clean raw markdown. Channel verified working for the Opus 5 prompting guide
  (2026-07); **re-verify per doc** — precedent, not a guarantee. Fallback: fetch the rendered
  page and record the degradation.
- **Blog posts (`claude.com/blog/...`):** no raw-markdown channel known; fetch rendered and
  extract. Record the channel used. **Two extraction artifacts reproduce on this channel; record
  them, never repair them** — `source.*` is immutable, so the fix belongs in whatever reads the
  snapshot, not in the snapshot. (a) The animated hero heading collapses every space in the H1.
  Reconstruct the title from the canonical URL slug, which the checklist already records — but the
  slug recovers word boundaries only, never punctuation or casing
  (`claude-models-explained-choosing-the-best-model-for-your-use-case` cannot yield the colon in
  "Claude models explained: choosing the best model for your use case"), so a title recovered that
  way is labelled reconstructed. When the run also retained the rendered HTML, that file's
  `<title>`/`<h1>` carries the exact form — but nothing in the pipeline contracts such a file, so
  it is a bonus, not the method. (b) The reading-time widget splits its value and its unit onto
  separate physical lines, so neither line reads as a duration on its own. (Both observed identically in two runs, at each slice's `source.md:7`:
  `# Claudemodelsexplained:choosingthebestmodelforyourusecase` with the reading time at lines
  83/87, and `# BuildingverificationloopsinClaudeCodewithskills` with it at lines 45/49.)
- **PDFs (model/system cards):** download the original binary as `source.pdf` plus a text
  extraction as `source.txt`; both are originals, the extraction tooling is named in the
  checklist.
- **Absence-establishing fetches must be complete.** Any fetch that will support a negative claim —
  an `api-only` basis, a "no harness surface states this" finding — goes through the raw `.md`
  channel with `curl` and records the retrieved length; a rendered `WebFetch` of a long page returns
  a silent prefix with no truncation signal. The asymmetry is what makes this binding: a truncated
  fetch cannot fabricate a PRESENCE, only an ABSENCE. (Two runs asserted a false absence exactly
  this way. In the steering-thinking slice the orchestrator's *resolution* re-fetched the same page
  through the same channel and reproduced the blind spot instead of testing it —
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` sits at line 277 of a 451-line, 316-row page whose rendered fetch
  surfaced only roughly its first fifth.)
- **The publisher's own index picks which pages such a check reads — never a guessed slug.**
  <https://platform.claude.com/llms.txt> enumerates the platform property's pages and
  <https://code.claude.com/docs/llms.txt> the harness property's; fetch the index raw with `curl`,
  record the retrieved length as for any other absence-establishing fetch, and let it select the
  pages. **A non-zero hit in the index, or in a snapshot page that turns out to be rendered HTML
  rather than doc prose, is READ at its match site and never treated as a count** — such a page's
  hits are its markup, and no reader of the number can detect that. The sampled-scope disclosure in
  the applicability filter's non-zero-result rule below stays the one sanctioned way to fall short
  of reading a hit set in full. (Both indexes
  verified live 2026-08-02: 616 lines / 56,941 bytes and 180 lines / 38,847 bytes. The
  page-chrome counter-fact is measured, not hypothetical — one campaign snapshot of nine platform
  pages held two that begin `<!DOCTYPE html>`, and two of the three terms a slice probed that
  directory with matched in those two files and nowhere else. Narrow guessed slugs, the practice
  this index replaces, are what produced absence bases that never reached the page stating the
  claim.)

## Claude-Code-applicability filter (with teeth)

Anthropic docs mix API-surface guidance with harness-relevant guidance. Every digest tags each
claim's applicability (`cc-applicable` / `api-only` / `mixed`), with evidence scaled to what
the tag asserts:

- **`cc-applicable` / `mixed` (positive claims):** verified against live code.claude.com docs at
  tag time — cite the URL consulted in the digest row. A positive tag assigned by inference,
  without a live-doc check, is additionally recorded as `unverified-inference` and becomes an
  interview question, never a silent fact. (This rule exists because inference has already produced a
  wrong tag once — the failure mode is real.)
- **`api-only` (a negative claim — "no harness surface exists" for the claim's own specific
  assertion; see the graded rule below):** absence cannot be proven from one page. Record the basis (the harness doc section(s) checked, or `unverified-inference` when
  none was); a contested or load-bearing `api-only` tag escalates to the interview rather than
  standing on an absence citation. **The basis records the exact command run and its raw result
  count**, not a prose summary of what was checked — an attested zero is not a reproducible zero,
  and a row that both performs an absence search and certifies its own result leaves a verifier
  nothing to replay. (One run produced eight fabricated absence bases before this rule was imposed;
  every one was caught against the corpus rather than by the producing agent — `llms.txt` asserted
  absent while present in 174 files, `thumbs` while `data-usage.md:28` states it, `knowledge cutoff`
  while `changelog.md:4820` states it.)
- **Every non-zero result names its match site(s).** A recorded count plus a filename histogram is
  still unfalsifiable: a reader who replays the command gets the same number and still cannot tell
  whether anyone read the matching lines. A row whose hit set was **sampled** rather than read in
  full states that scope at the row. (Adopted slice-wide as a ruling in the system-prompts run and
  still the most-violated rule in that slice; the cost is documented, not hypothetical — an
  undisclosed `settings.md:727` near-miss was exactly what the unread portion of a 199-line hit set
  contained.)
- **What falsifies `api-only`, and what only comes close — one graded rule, because the whole class
  of defects here is the boundary being re-derived per row.** `api-only` asserts no harness surface
  for **the claim's own specific assertion**, so only the corpus documenting *that assertion*
  falsifies it; topical overlap never does. Two grades sit below the falsifying line, and the tag
  survives both:
  - **Near-miss — a harness page covers the row's subject without stating the row's specific
    rule.** The row MUST name it by page and line (the term this profile already uses of
    `settings.md:727` above), and an affirmative "no surface" or "undisclosed" phrasing in such a
    row is simply false and goes. Silence here was the largest MINOR class in the slice that
    measured it: one release-notes unit disclosed 24 near-miss rows on its own, and two sibling
    units in that slice raised the same boundary independently, one of them asking outright for a
    standing notation so a reader can tell "no surface at all" from "adjacent surface exists".
  - **Weaker than a near-miss, and often mistaken for one.** A counterpart artifact on the *other*
    property (a harness `llms.txt` beside a claim about the platform's own `llms.txt`) and a
    workload named only as an example beside a guide that teaches it (an SDK hosting page naming
    "a customer support agent") do not cover the row's subject at all. Neither falsifies
    `api-only`: the tag scopes to the specific artifact or surface the row names. (Both were
    contested escalations on the resources-hub slice, and both verification arms adjudicated them
    the same way.)
- **`cc-applicable`/`mixed` boundary:** a claim that names an API surface (parameter, endpoint,
  SDK call) tags `mixed` even when its guidance transfers to the harness; `cc-applicable` is
  reserved for claims naming no API surface.
- **Row-local, tag always present:** the evidence (a positive tag's live-doc URL, an `api-only`
  basis) appears in the claim's own row — "same basis as claim N" does not satisfy the contract —
  and every claim carries exactly one vocabulary tag: `unverified-inference` is an additional
  uncertainty marker, never a substitute for the tag. (Both rulings from the sonnet-5 guide
  slice's cross-vendor verification, where citation-by-reference and marker-as-tag were the
  dominant correction class.)
- **A positive tag's row answers two questions as two bullets, never as one merged sentence.** They
  are separate questions with separate answers, and merging them is what leaves a tag unauditable:
  - *Is the assertion itself documented?* — the live-doc citation for the assertion, or the
    attestation marker saying no doc states it.
  - *Does the harness have the surface the guidance operates on?* — the live-doc citation the
    positive tag itself rests on.
  A row that answers only the first reads as "nothing to cite" and silently drops the second. The
  collapse is most tempting where the assertion is blog-only and the surface is well documented,
  but the requirement is on **every** positive-tag row. (Both verification arms independently filed
  the same finding against one unit — 12 positive-tag rows with no row-local live URL, 6 with no
  applicability evidence at all — and the corrector who repaired those rows diagnosed this collapse
  as their cause and asked for it to be carried into the profile.)
- **Row-local reachability — a cited site no recorded command produces has been asserted, not
  disclosed.** A `file.md:NN` in a row's evidence counts as disclosed only when some command
  recorded in that same row produces it; otherwise the row says so explicitly, and an explicit
  read-not-grepped note is the sanctioned form. Two corollaries the evidence forces: a `| wc -l`
  count produces no sites and cannot support a citation, and a site named from a sampled set records
  the narrower command that reaches it. (Three independent auditors raised this class separately — a
  corrector and both verification arms, each with its own instrument; arm A measured 57 citations
  across ~35 rows in one slice produced by no command in their own rows. Every cited line was read
  and found true, so the claims survived and the defect was the audit trail — which is precisely why
  no verifier's spot-check substitutes for the rule.)
- **Harness docs are their own live basis:** when the digested page is itself a live
  code.claude.com harness doc, intrinsic harness-guidance claims cite the canonical page URL +
  section as their row-local basis; the boundary rule still routes claims naming an API surface
  to `mixed`, and third-party APIs (e.g. the GitHub API) count as API surfaces — no vendor
  exemption. (From the best-practices slice: the third-party-API ruling is its cross-vendor
  finding; the own-basis rule was applied there and ratified by both re-verifications.)
- **Vendor-blog attestation:** a `claude.com/blog` page is marketing-adjacent vendor voice, not
  reference documentation. Any assertion of fact that exists ONLY in the blog (no harness or
  platform doc states the same assertion) — behavioral, performance, figure/percentage,
  comparative, frequency, methodological/definitional, positioning, or any other class; the
  list is illustrative, not exhaustive — additionally carries
  `vendor-claimed (blog, <fetch date> fetch)` beside its vocabulary tag — assertion-specific
  (related-property citations never exempt it), never co-occurring with a live-doc citation for
  the same assertion, and never deferred to the interview. The marker is an attestation note
  that composes with the tag and, where applicability itself is inferred, with
  `unverified-inference`. (Shape recommended by the context-engineering blog slice's handoff,
  exercised end-to-end and enforced by both verifiers on the models-explained slice.)
- **The attestation follows the vendor voice, not the containing page.** Vendor-voice material
  EMBEDDED in a non-blog page — a blog passage a system prompt quotes, an announcement excerpt
  inside a release note — carries the same marker on the same terms, sourced to the embedded
  material rather than to the host page. The marker exists to stop an unverifiable vendor
  assertion being read as documented fact, and that risk does not change with the type of page the
  assertion happens to sit inside. (A release-notes system prompt embedded a blog passage whose
  "less than 5% of sessions" trigger-rate figure no harness doc restates; the digest disclosed the
  gap in prose but the row carried no marker, because the rule was scoped to blog *sources*.)

## Digest-agent model matching

A model-specific guide digests on the model it describes — the subject model recognizes its own
behavioral descriptions:

| Doc subject | Digest-agent model |
|---|---|
| Guide/card about a specific Claude model | The exact model version the doc describes, resolved to a full model ID — never a bare family alias, which resolves to the current family model and would digest a historical guide on the wrong version. When no exact-version ID is resolvable, omit the override (session default) |
| Cross-model or harness doc (best practices, effort, guardrails) | Session default (no override) |
| Non-Claude subject | Session default (no override) |

Every model-pinned spawn brief uses the conditional framing contract from `SKILL.md` Phase 3
("this brief assumes model X; if you are not X, note the mismatch and continue").

## Doc queue

Pending Anthropic docs for this pipeline. Verify each URL live at fetch time; remove entries as
their slices complete.

Deferred with trigger (not queued):

- <https://platform.claude.com/docs/en/build-with-claude/task-budgets> — api-only (the page
  states task budgets are not supported on Claude Code or Cowork; verified 2026-07-27); enqueue
  when harness support lands

## Artifact targets

Interview-handoff dispositions for this publisher typically route to: per-model doctrine
chapters (a playbooks-style model-adaptation seam), instruction-audit rule rows (a
model-delta audit class), or corpus graduation (a knowledge-corpus repository). The handoff
records the candidate target per finding; the interview decides.
