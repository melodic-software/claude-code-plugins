# Anthropic docs queue (recorded, not dispatched)

Recorded pages for `/knowledge:docpage-digest` runs against Anthropic documentation properties.
Read when the user asks what is recorded or deferred for this publisher. This is a record, never
a dispatch list: a run starts because the user named that page. Verify each URL live at fetch
time, and remove an entry as its slice completes.

Ranked (recorded, no dispatch):

- <https://code.claude.com/docs/en/permissions>
  — first. Gates the hooks-at-project-scope security question (plugins-reference D3) and two
  memory-slice questions.
- <https://code.claude.com/docs/en/self-hosted-environments>
  — second.

Thinking (completes the set's custody map — troubleshooting first):

- <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
  — the harness documents this page's specific assertions on its own pages (`errors.md` documents
  thinking-configuration 400s; `prompt-caching.md` documents cache-miss causes), which is
  claim-level transfer under the falsifying rule in
  [anthropic-docs-profile.md](anthropic-docs-profile.md), not topical overlap; the digest still tags
  each claim against those pages individually — this entry pre-classifies none of them
- <https://platform.claude.com/docs/en/build-with-claude/thinking-tool-workflows>
  — the last uncovered page of the thinking doc set; two already-digested slices defer to it by
  anchor, so the marginal cost of the last page is the lowest it will ever be

Retention and ZDR (one topic slice, two lanes, drained as three page runs — one page per run, per
the engine; retention is org-level policy and the one topic queued here carrying compliance
weight, and both properties are already in scope):

- <https://platform.claude.com/docs/en/manage-claude/api-and-data-retention>
  — the API lane
- <https://code.claude.com/docs/en/data-usage>
  — the harness lane
- <https://code.claude.com/docs/en/zero-data-retention>
  — the harness lane's enterprise posture: ZDR is scoped to qualified accounts on Claude for
  Enterprise, which is the commitment a consuming setup needs stated rather than inferred

Agent SDK (one page — SDK docs are canonically harness docs, but queueing the rest of that doc set
is a separate scope decision nobody has taken):

- <https://code.claude.com/docs/en/agent-sdk/agent-loop>

Models:

- <https://platform.claude.com/docs/en/about-claude/models/overview>
  — the canonical model-fact freshness source; re-fetching this one page *is* the freshness check,
  where a release-notes corpus would grow monotonically and age entry by entry
- <https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5>
  — the launch source the corpus's own Fable 5 / Mythos 5 positioning claims rest on, and linked
  from the harness model-config doc's "Work with Fable 5"
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5>
  — enqueued on custody grounds, not on a fleet-lane trigger that has not fired: the `playbooks`
  Opus 5 model-adaptation chapter cites this page as sole authority for three shipped claims —
  thinking on by default, the 400 returned when thinking is disabled above effort `high`, and the
  live effort-level enumeration that establishes the upstream Opus 5 prompting guide's own ladder
  statement as truncated — none of which the models `overview` page carries, so "the overview covers
  it canonically" is false for exactly the facts already cited. A custody fact about this one page,
  not a decision to start a release-notes corpus; `whats-new-sonnet-5` carries no such citations and
  stays deferred

Claude Code companion docs (digest in this order):

- <https://code.claude.com/docs/en/features-overview>
- <https://code.claude.com/docs/en/memory>
- <https://code.claude.com/docs/en/how-claude-code-works>

Blog posts:

- <https://claude.com/blog/the-advisor-strategy>
  — the harness advisor doc cites this post as its own "why"; digest it alongside
  <https://code.claude.com/docs/en/advisor> and
  <https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool> so one slice covers
  the concept's three surfaces
- <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns>
  — the designated deep-dive for prompting the Claude 5 generation, already being read by local
  work without a custody record, applicability tags, or an attestation pass

Engineering posts:

- <https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>
  — the cited best-practices source for custom agent evaluations, and methodology input to the
  deferred re-pin checklist and the eval-set gap

Deferred with trigger (not queued):

- <https://platform.claude.com/docs/en/build-with-claude/task-budgets> — api-only (the page
  states task budgets are not supported on Claude Code or Cowork; verified 2026-07-27); enqueue
  when harness support lands
- <https://code.claude.com/docs/en/context-window> — read against the 2026-07-31 harness snapshot
  rather than left untested: it documents behavior as the limit approaches (Claude Code compacts
  automatically) but never the `model_context_window_exceeded` stop reason, so it does not move the
  claim it was checked for; enqueue if the page starts documenting that stop reason's handling
- <https://platform.claude.com/docs/en/build-with-claude/fallback-credit> — the two API-side claims
  it would settle carry a weak, openly disclosed absence basis that nothing is built on; enqueue
  when an artifact actually depends on fallback-credit behavior
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-sonnet-5> — release notes for a
  model the models `overview` page already covers canonically; enqueue when Sonnet 5 enters or
  materially changes a fleet lane
- <https://claude.com/blog/complete-guide-to-building-skills-for-claude> — a vendor-voice
  restatement of a schema whose first-party canons are already reachable, so digesting it adds
  attestation cost and no authority; enqueue for the first artifact that needs schema detail no
  first-party canon states
