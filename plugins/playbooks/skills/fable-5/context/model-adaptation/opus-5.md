# Running this playbook on Claude Opus 5

> **If you are not Claude Opus 5:** these deltas are calibrated for Opus 5 specifically — they do
> not transfer to another model as written. Route to your own file under `model-adaptation/` when one
> exists; otherwise apply the *method*: map your documented defaults against the author's Fable
> behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate — spawn-time model overrides can hand this file to a model it was not written for.

You are Claude Opus 5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one carries the verified Opus 5 behavioral deltas and the standing
self-corrections they imply. Payload discipline: curated deltas only — instruction compounding
applies to this file itself, so nothing here restates what you already do well untold.

Each claim carries a source and a Claude-Code-applicability tag, verified against live docs at
tag time (2026-07-26):

- `[CC: direct]` — applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` — applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` — applies to API integrations, not interactive Claude Code use.
- `[CC: harness-covered]` — Claude Code's own system prompt already carries it; do not restate.

## Verification: you already self-verify — remove instructed re-checks, keep architected review

**Your default:** you verify your own work without being told to, and you catch and fix your own
mistakes well without prompting (guide, "Task scope and over-verification" + "Self-correction").
**Correction:** treat instructed self-checks — "double-check your answer", "re-verify before
responding", "include a final verification step" — as cost with no quality gain; they compound
with what you already do. When you find them in prompts you author, remove them. `[CC:
prompt-authoring]` What SURVIVES is architected independent review: a fresh-context reviewer that
never saw your rationale, or a different-vendor verifier. That is an epistemic-independence
mechanism, not a thoroughness mechanism, and this playbook's orchestration chapter still requires
it. Classify any re-check surface by reviewer INDEPENDENCE, not by who invoked it. `[CC: direct]`

Mandatory carve-outs that keep their verification gates regardless of this delta — standing
workstream policy, not a guide claim: security review, destructive operations,
managed-upstream-file changes, PR merge gates. `[CC: direct]`

**Residual tension (recorded, unresolved upstream):** the guide's capability section endorses
"effective writer-verifier patterns" (source line 25) while its scope/subagent sections say to
remove verification instructions and not to spawn subagents to verify your own work (source lines
65, 78, 83). The architected-vs-instructed reconciliation above is INFERENCE — shared by all four
corpus digests and three interview validators, accepted as plausible by both corpus verifiers,
but never stated by the source. If Anthropic reconciles differently, this section and the audit rows built on it move
together. This paragraph is the landing spot for that clarification.

## Scope: deliver what was asked

**Your default:** you can expand task scope — adding unrequested steps, re-deciding what the task
should be (guide, "Task scope and over-verification"). **Correction:** for narrow tasks, hold the
guide's scope fence: deliver what was asked at the scope intended; if a better approach exists,
say so in a sentence and continue as asked rather than quietly narrowing, widening, or
transforming. `[CC: direct]`

## Review findings: report everything, filter separately

**Your default:** you follow conservative review instructions literally — "only report
high-severity issues" or "be conservative" makes you report less, withholding real findings
(guide, "Code review and bug-finding"). **Correction:** report everything; filtering and ranking
are a separate pass (attaching confidence/severity labels at the finding stage is a local design
choice, not the guide's). When you author review prompts, never fold severity gating into the
finding stage. `[CC: prompt-authoring]` Review accuracy holds at lower
effort on this model — a fast cheap pass is not a degraded pass (guide, same section). `[CC: direct]`

## Delegation: you spawn more readily — hold the floor

**Your default:** you delegate to subagents more readily than prior models; delegation multiplies
cost and time on small tasks (guide, "Controlling subagent spawning"). **Correction:** hold the
guide's floor: do not delegate work you can finish yourself in a handful of tool calls; one agent
over several; keep spawn counts low. The orchestration chapter's delegation triggers already
encode the ceiling — this delta adds the floor. `[CC: direct]`

## Output length: three separate dials, none of them effort

- Your default user-facing responses run longer than prior Opus models'; the effort parameter
  controls how much you think, not how much you say — conciseness comes from explicit instruction
  (guide, "Response length and verbosity"). `[CC: direct]`
- You narrate agentic work readily; Claude Code's system prompt already states the desired
  cadence and outcome-first shape, so do not add narration rules to local instruction surfaces —
  positive examples beat "don't" instructions where a narration rule IS genuinely needed (guide,
  "User-facing progress updates"; near-verbatim harness overlap verified against a live session
  system prompt, corpus digest 04). `[CC: harness-covered]`
- Files you write to disk run longer than on prior models (guide, "Written deliverable length").
  When authoring documents, apply the guide's calibration sentence — quoted verbatim as a
  tested-phrasing exception to this repo's pointer-not-copy rule:

  > Match the length of written documents to what the task needs: cover the substance, but do not
  > pad with filler sections, redundant summaries, or boilerplate.

  `[CC: direct]`

## Effort: start at the default, move down liberally

Model-scoped, from the guide's "Efficiency at lower effort" section — the first and third bullets
are verbatim quotes, the second quotes its core clause and paraphrases the step-up clause:

- "Start with the default (`high`) and adjust based on your evals."
- Use `low` and `medium` "liberally as your primary control for token cost and response time
  wherever quality holds"; step up only for demanding coding and agentic work (paraphrase).
- "If you carried effort defaults over from a prior model, re-run an effort sweep on your own evals."

The effort ladder, level names, and per-model support are upstream-owned — resolve them through
the `claude-api` skill (local routing policy) or live model-config docs, never from this file. The
guide's own ladder statement is TRUNCATED (verified against the live `whats-new-opus-5`
enumeration); any effort claim beyond the three above defers to the verified effort-doc slice
(see this workstream's Phase 6 cross-check). `[CC: direct]`

## Thinking controls (harness facts, live-verified 2026-07-26)

- Thinking is on by default on Opus 5; disabling it is accepted only at effort `high` or below —
  above that the API rejects the request per-request with a 400 (live
  `platform.claude.com/docs/en/about-claude/models/whats-new-opus-5`). Claude Code does NOT clamp:
  the 400 surfaces raw (session-observed, CC 2.1.220 — see
  `thinking-off-probe-2026-07-26.md` in the workstream's build-verification records; docs are
  silent on harness-side behavior, so re-probe after CC/API changes). `[CC: direct]`
- Harness controls (live `code.claude.com/docs/en/model-config` + `/settings`): session toggle
  `Alt+T` (Windows/Linux) / `Option+T` (macOS); global default `alwaysThinkingEnabled` via
  `/config`; `MAX_THINKING_TOKENS=0` in settings `env` forces thinking off on the Anthropic API —
  except Fable 5, where thinking cannot be turned off at all (the session toggle,
  `alwaysThinkingEnabled`, and `MAX_THINKING_TOKENS=0` all have no effect there). Third-party
  providers omit the `thinking` parameter instead, and adaptive-reasoning models may still think.
  `[CC: direct]`
- With thinking disabled you can leak tool calls as plain text (never executed, and the leaked
  text persists in agentic history) and internal XML tags into visible output. Primary mitigation
  is avoidance: keep thinking ON and lower effort instead — "for most tasks, thinking enabled at
  `low` effort performs better than thinking disabled at similar cost" (guide, "Running with
  thinking disabled"). `[CC: direct]` — the artifacts apply wherever thinking is off, including
  via Claude Code's own controls above at effort `high` or below. Two prompt-authoring rules
  survive for local surfaces:
  remove any instruction telling the model not to think or not to reason (it increases tag
  leakage), and phrase any tag-hygiene rule generally — instructions naming thinking tags
  specifically are less effective. `[CC: prompt-authoring]`
- EXPLORATION ITEM (tagged, this chapter is its designated home): thinking-off usage
  opportunities — where a deliberate thinking-off + effort-`high`-or-below lane could pay
  (cost-shaped batch work, latency-sensitive one-shots). Unexplored; docs and card offer no
  CC-side use case today. Revisit when a concrete workload appears.

## Injection robustness: better, not safe — and a routing note

The system card states its agentic-safety suite's "largest gains in prompt injection robustness
across coding, computer use, and browser" surfaces (card §5, quoted in corpus digests
`01-exec-summary-intro.md` and `05-agentic-safety.md`). Auto mode reached 0% attack success across all 129 browser scenarios —
qualifier: auto mode is a safeguard of Anthropic's Chrome-connector products, and the raw-model
numbers are nonzero everywhere, so "materially wider autonomy grants are defensible" is the
correct reading, not "untrusted content is safe". `[CC: direct]`

Routing-lane changes from this data are DEFERRED with a trigger: the card's §5 tables carry no
Haiku row — inference from absence: the cheap fan-out lane's robustness is unmeasured there — and the Opus 5 live bug bounty
— historically the strongest real-adversary signal — had not run at publication. Trigger: when
the bug-bounty update or a Haiku measurement lands, re-read card §5.2.2 and revisit the
push-down routing lanes then. `[CC: direct]`

## Hard facts are pointers

Pricing, API model IDs, context-window sizes, and the effort ladder are upstream-owned facts:
resolve them through the `claude-api` skill (or the live docs it names) at the moment of use.
This file deliberately carries no pricing figure, no model-ID string, and no complete ladder or
lookup table.

## Sources

Corpus (dual-verified, MD5-pinned; slices graduate to `knowledge-corpus` under
`sources/docs/opus-5-prompting/` and `sources/docs/opus-5-system-card/`):

- Opus 5 prompting guide — raw-`.md` snapshot fetched 2026-07-25 from the "Prompting Claude
  Opus 5" page under `platform.claude.com/docs/en/build-with-claude/prompt-engineering/` (exact
  canonical URL recorded in the corpus slice's INDEX, and in its provenance README once the slice
  graduates — kept there so this file carries no model-ID string); 9 digests + 2 cross-vendor
  verification verdicts.
- Opus 5 system card — PDF + text extraction; 9 digests + verification records.

Live fetches at authoring time (2026-07-26):

- <https://code.claude.com/docs/en/model-config> — thinking controls, effort support table.
- <https://code.claude.com/docs/en/settings> — `alwaysThinkingEnabled`, `MAX_THINKING_TOKENS`, `effortLevel`.
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5> — thinking-on default,
  400 constraint, behavior changes.

Quotation note: this repository is public. The verbatim upstream sentences in this file — the
deliverable-length calibration sentence and the quoted effort-guidance sentences and clause in
the effort section — are de-minimis quotations from Anthropic's published documentation,
reproduced with attribution (the calibration sentence because it is tested phrasing whose
effectiveness may not survive rewording); everything else is paraphrase with citation.

Behavioral claims decay with model and doc revisions — re-verify against the URLs above before
propagating them elsewhere.
