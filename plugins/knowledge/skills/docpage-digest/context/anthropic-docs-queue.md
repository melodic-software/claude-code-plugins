# Anthropic docs queue (recorded, not dispatched)

Recorded pages for `/knowledge:docpage-digest` runs against Anthropic documentation properties.
Read when the user asks what is recorded or deferred for this publisher. This is a record, never
a dispatch list: a run starts because the user named that page. Verify each URL live at fetch
time, and remove an entry as its slice completes.

Ranked (recorded, no dispatch):

- <https://code.claude.com/docs/en/permissions>
  First. Gates the hooks-at-project-scope security question (plugins-reference D3) and two
  memory-slice questions.
- <https://code.claude.com/docs/en/self-hosted-environments>
  Second.

Thinking (completes the set's custody map, troubleshooting first):

- <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
  The harness documents this page's specific assertions on its own pages (`errors.md` documents
  thinking-configuration 400s; `prompt-caching.md` documents cache-miss causes), which is
  claim-level transfer under the falsifying rule in
  [anthropic-docs-profile.md](anthropic-docs-profile.md), not topical overlap. The digest still tags
  each claim against those pages individually, and this entry pre-classifies none of them
- <https://platform.claude.com/docs/en/build-with-claude/thinking-tool-workflows>
  The last uncovered page of the thinking doc set; two already-digested slices defer to it by
  anchor, so the marginal cost of the last page is the lowest it will ever be

Retention and ZDR (one topic slice, two lanes, drained as three page runs, one page per run, per
the engine; retention is org-level policy and the one topic queued here carrying compliance
weight, and both properties are already in scope):

- <https://platform.claude.com/docs/en/manage-claude/api-and-data-retention>
  The API lane
- <https://code.claude.com/docs/en/data-usage>
  The harness lane
- <https://code.claude.com/docs/en/zero-data-retention>
  The harness lane's enterprise posture: which accounts ZDR covers is the commitment a consuming
  setup needs stated rather than inferred

Agent SDK (one page; SDK docs are canonically harness docs, but queuing the rest of that doc set
is a separate scope decision nobody has taken):

- <https://code.claude.com/docs/en/agent-sdk/agent-loop>

Models:

- <https://platform.claude.com/docs/en/about-claude/models/overview>
  The canonical model-fact freshness source; re-fetching this one page *is* the freshness check,
  where a release-notes corpus would grow monotonically and age entry by entry
- <https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5>
  The launch source the corpus's own Fable 5 / Mythos 5 positioning claims rest on, and linked
  from the harness model-config doc's
  [Work with Fable](https://code.claude.com/docs/en/model-config#work-with-fable)
- <https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5>
  and <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
  The release notes and prompting guide for Opus 5.5, the current Opus, and the first-party
  sources for the `playbooks` Opus 5.5 model-adaptation chapter. Both resolved to their titled
  pages on 2026-10-01; one page per run

Claude Code companion docs (digest in this order):

- <https://code.claude.com/docs/en/features-overview>
- <https://code.claude.com/docs/en/memory>
- <https://code.claude.com/docs/en/how-claude-code-works>

Blog posts (each a digest target, never a pointer: a slice built on one points at the docs page
named with it and keeps the post as a correlate):

- <https://claude.dev/blog/getting-the-most-out-of-opus-5-5/> (not a pointer; correlate only)
  The vendor usage guide for Opus 5.5, the current Opus. The `playbooks` Opus 5.5
  model-adaptation chapter and this repository's instruction surfaces apply it without a custody
  record, applicability tags, or an attestation pass; its model-behavior claims are
  vendor-reported. Docs pointer:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
- <https://claude.com/blog/the-advisor-strategy> (not a pointer; correlate only)
  The harness advisor doc links this post for its rationale; digest it alongside the docs
  pointers <https://code.claude.com/docs/en/advisor> and
  <https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool> so one slice covers
  the concept's three surfaces
- <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns> (correlate only)
  The designated deep-dive for prompting the Claude 5 generation, already being read by local
  work without a custody record, applicability tags, or an attestation pass. Docs pointer:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- <https://claude.com/blog/getting-started-with-loops> (not a pointer; correlate only)
  Linked from the claude.ai performance post
  (<https://claude.dev/blog/how-we-made-claude-ai-faster>, correlate only). A summary-level fetch
  on 2026-09-29 confirmed its topic: Claude Code's loop types and when to use each. That the
  `performance` plugin's measure, change, and verify cycle and the `playbooks` orchestration
  chapter's narrow threads assume these loops is our reading, not the post's claim. Pointer: when
  a digest needs how Claude Code repeats a prompt, fetch
  <https://code.claude.com/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-/loop> live, the
  post as correlate. As of: 2026-10-02. Recheck trigger: that section leaves the page.
- <https://claude.com/blog/code-review> (not a pointer; correlate only)
  The automated-review gate the claude.ai performance post names as a safety mechanism set up
  before the fast phase; the `review` plugin's CI lanes are its local counterpart, with no custody
  record against it. A summary-level fetch on 2026-09-29 confirmed its topic: the launch of Claude
  Code's Code Review. Pointer: when a digest needs whether Code Review findings gate a merge, fetch
  <https://code.claude.com/docs/en/code-review#check-run-output> live, the post as correlate.
  As of: 2026-10-02. Recheck trigger: that section leaves the page.
- <https://claude.com/blog/agentic-coding-is-straining-ci-heres-how-we-scaled-test-impact-analysis-at-anthropic> (correlate only)
  The basis the claude.ai performance post cites for wins decaying in a fast-moving codebase,
  which the `performance` plugin's ratchet guardrails rest on. A summary-level fetch on 2026-09-29
  confirmed its topic: test-impact analysis in Anthropic's CI. Pointer: when a digest needs
  test-impact analysis as a CI technique, fetch this post live; no docs page covers test-impact
  analysis as of 2026-10-01. As of: 2026-10-01. Recheck trigger: a docs page starts covering it.
- <https://claude.dev/blog/spending-your-effort/> (not a pointer; correlate only)
  "Using Claude Code: Spending your effort", which `docs/upstream/opus-5-5-task-cost.md` (Q34)
  and the `playbooks` model-adaptation chapters already cite as a correlate without a custody
  record; its standfirst is a vendor claim. Resolved to its titled page on 2026-10-02. Docs
  pointer: <https://code.claude.com/docs/en/model-config#adjust-effort-level>
- <https://claude.dev/blog/lessons-from-building-claude-code-prompt-caching-is-everything/> (not a pointer; correlate only)
  "Lessons from building Claude Code: Prompt caching is everything", queued by the same record
  (Q34); its standfirst is a vendor claim. Resolved to its titled page on 2026-10-02. Docs
  pointer: <https://platform.claude.com/docs/en/build-with-claude/prompt-caching>

Engineering posts:

- <https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents> (correlate only)
  The cited best-practices source for custom agent evaluations, and methodology input to the
  deferred re-pin checklist and the eval-set gap. Docs pointer:
  <https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>

Deferred with trigger (not queued):

- <https://platform.claude.com/docs/en/build-with-claude/task-budgets>: tagged api-only on a
  2026-07-27 check of the page's harness-support statement; enqueue when harness support lands
- <https://code.claude.com/docs/en/context-window>: read against the 2026-07-31 harness snapshot
  rather than left untested: it never named the `model_context_window_exceeded` stop reason, so it
  does not move the claim it was checked for; enqueue if the page starts documenting that stop
  reason's handling
- <https://platform.claude.com/docs/en/build-with-claude/fallback-credit>: the two API-side claims
  it would settle carry a weak, openly disclosed absence basis that nothing is built on; enqueue
  when an artifact actually depends on fallback-credit behavior
- <https://claude.com/blog/complete-guide-to-building-skills-for-claude> (correlate only): a
  vendor-voice restatement of a schema whose first-party canons are already reachable (docs
  pointer: <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>), so
  digesting it adds attestation cost and no authority; enqueue for the first artifact that needs
  schema detail no first-party canon states
