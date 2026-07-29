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
  extract. Record the channel used.
- **PDFs (model/system cards):** download the original binary as `source.pdf` plus a text
  extraction as `source.txt`; both are originals, the extraction tooling is named in the
  checklist.

## Claude-Code-applicability filter (with teeth)

Anthropic docs mix API-surface guidance with harness-relevant guidance. Every digest tags each
claim's applicability (`cc-applicable` / `api-only` / `mixed`), with evidence scaled to what
the tag asserts:

- **`cc-applicable` / `mixed` (positive claims):** verified against live code.claude.com docs at
  tag time — cite the URL consulted in the digest row. A positive tag assigned by inference,
  without a live-doc check, is recorded as `unverified-inference` and becomes an interview
  question, never a silent fact. (This rule exists because inference has already produced a
  wrong tag once — the failure mode is real.)
- **`api-only` (a negative claim — "no harness surface exists"):** absence cannot be proven from
  one page. Record the basis (the harness doc section(s) checked, or `unverified-inference` when
  none was); a contested or load-bearing `api-only` tag escalates to the interview rather than
  standing on an absence citation.
- **`cc-applicable`/`mixed` boundary:** a claim that names an API surface (parameter, endpoint,
  SDK call) tags `mixed` even when its guidance transfers to the harness; `cc-applicable` is
  reserved for claims naming no API surface.

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

Per-model guides:

- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5>

Guardrail guides:

- <https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations>
- <https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/increase-consistency>

Model selection (special handling — vet/validate/correct the consuming setup's existing
model-routing configuration against the doc, rather than only digesting):

- <https://platform.claude.com/docs/en/about-claude/models/choosing-a-model>
  — routing vet executed 2026-07-29 (melodic-software/claude-code-plugins#1697); digest slice
  still pending

Thinking (two overlapping docs — two runs, one page per run by contract):

- <https://platform.claude.com/docs/en/build-with-claude/thinking>
- <https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost>

Deferred with trigger (not queued):

- <https://platform.claude.com/docs/en/build-with-claude/task-budgets> — api-only (the page
  states task budgets are not supported on Claude Code or Cowork; verified 2026-07-27); enqueue
  when harness support lands

Supplementary references:

- <https://platform.claude.com/docs/en/resources/overview>
- <https://platform.claude.com/docs/en/release-notes/system-prompts>

Applies across all of the above:

- <https://code.claude.com/docs/en/best-practices>

Blog posts:

- <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>
  — likely cross-cuts every slice
- <https://claude.com/blog/claude-models-explained-choosing-the-best-model-for-your-use-case>
  — pair with the choosing-a-model slice for the routing vet
- <https://claude.com/blog/building-verification-loops-in-claude-code-with-skills>
  — pairs with any verification-loop or loop-engineering work the consuming setup already tracks

## Artifact targets

Interview-handoff dispositions for this publisher typically route to: per-model doctrine
chapters (a playbooks-style model-adaptation seam), instruction-audit rule rows (a
model-delta audit class), or corpus graduation (a knowledge-corpus repository). The handoff
records the candidate target per finding; the interview decides.
