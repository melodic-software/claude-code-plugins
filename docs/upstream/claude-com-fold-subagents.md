# Upstream source: "Building agents: When to fold subagents into your main agent loop"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Decisions](#decisions)
- [Revisit triggers](#revisit-triggers)

This is the provenance record for acting on the claude.com article about folding subagents into
one agent loop. It follows the record shape of
[claude-dev-spending-your-effort-blog.md](claude-dev-spending-your-effort-blog.md) and the
[upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each row is
our decision in our own words; no row restates the article or a docs page, and this record lists
no figure from either.

## Status

The decisions were made in one interview, decisions only, after a verified digest of the article
and research on the tools it names. Two pull requests land them: the one carrying this record,
with the `/multi-agent:assess` docs pointer and a pointer from the fable-5 orchestration chapter,
and a second that adds digest tagging rules to the docpage-digest Anthropic docs profile.

Dropped or held:

- No change to user-scope instructions or the dotfiles.
- No tool-count number in any skill.
- No eval recipe for comparing a folded agent with a kept subagent.
- The fable-5 orchestration chapter keeps its delegation rule; cutting that restatement waits on
  before/after eval evidence, tracked in the follow-up issue linked from this record's pull
  request.
- The pages the article links are not added to the digest queue.

## Source and verification

- Correlate with
  `https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop`
  (published 2026-10-22, digested and dual-verified 2026-10-24 after three correction rounds). It
  is never the pointer where a docs section covers the topic. Recheck trigger: the article is
  revised, or a later claude.com or claude.dev post on folding subagents supersedes it.
- Pointers: the Claude Code and Claude Platform docs sections named per row, read 2026-10-24.
- Where no docs page covers a topic, the row says so and links the post as the correlate note, and
  its recheck trigger includes a docs page starting to cover it.

## Row schema

**Topic** names the item with an ID other files cite; **Ours** is what this repository does or
decided and where; **Verdict** is our reading of the article's claim (`documented`,
`vendor-claimed`, `contradicted`, `watch`, `not ours`); **Pointer** is the docs section a reader
checks live, followed by any correlate note. Shared for every row:

- **As of**: 2026-10-24
- **Recheck trigger**: the pointed-to section is renamed or removed or stops covering its topic;
  for a row whose topic no docs page covers, a docs page starting to cover it.

## Decisions

| Topic | Ours | Verdict | Pointer |
|---|---|---|---|
| F1 single-agent-loop-kit | Not referenced anywhere here and no native-surfaces row: it is a Claude Platform migration kit, not a Claude Code surface. Revisit if Claude Code ships or documents it. | not ours | When a task migrates a Platform agent, read [anthropics/single-agent-loop-kit](https://github.com/anthropics/single-agent-loop-kit) live; no docs page covers the kit as of 2026-10-24 |
| F2 skill-creator as a trimming tool | `/skill-quality:check` and `/playbooks:skill-authoring` keep their own scope; we do not treat skill-creator as a tool that trims or deduplicates skills. | vendor-claimed, contradicted | When deciding what skill-creator does, fetch [Run evals with skill-creator](https://code.claude.com/docs/en/skills#run-evals-with-skill-creator) live |
| F3 `/skill-doctor` as a deletion tool | We read `/skill-doctor` as a report a person acts on, not a tool that removes skills; [native-surfaces.md](../native-surfaces.md) already carries its row. | vendor-claimed, contradicted | When deciding what `/skill-doctor` covers, fetch [Find unused skills](https://code.claude.com/docs/en/skills#find-unused-skills) live |
| F4 Task budget as a loop stop | Our turn-limit and stop guidance is unchanged; a task budget is not treated as a stop condition, and not as a Claude Code feature. | vendor-claimed, contradicted | When a loop design leans on task budgets, fetch [Task budgets are advisory, not enforced](https://platform.claude.com/docs/en/build-with-claude/task-budgets#task-budgets-are-advisory-not-enforced) and [Feature support](https://platform.claude.com/docs/en/build-with-claude/task-budgets#feature-support) live |
| F5 System-prompt reduction and its model scope | Recorded only; no skill relies on it. We scope it to the Claude Code system prompt of the Opus 5 and Fable 5 generation, and do not credit it to skills or tool search. | vendor-claimed | When a design cites a smaller system prompt, read [the claude.dev post](https://claude.dev/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models/) live; no docs page covers the reduction as of 2026-10-24 |
| F6 Tool-count guidance | No skill states a tool-count threshold; a reader who needs one reads it live. Claude Code already defers MCP tools through tool search. | documented | When a tool count is in question, fetch [When to use tool search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#when-to-use-tool-search) live; for Claude Code, [Scale with MCP tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search) |
| F7 Parallel work limited to reads | Not adopted in any skill: `/implementation:implement-dispatch` runs concurrent writers on disjoint file fences, and only practitioner posts state the qualifier. Revisit on evidence from our own runs. | watch | When splitting writes across agents, read [Cognition, 2025-06-12](https://cognition.ai/blog/dont-build-multi-agents), [Cognition, 2026-04-22](https://cognition.com/blog/multi-agents-working) and [LangChain, 2025-06-16](https://www.langchain.com/blog/how-and-when-to-build-multi-agent-systems) live; no docs page covers it as of 2026-10-24 |
| F8 Tool selection or conflicting instructions as a reason to keep a subagent | Not added as a standing condition: no stumble here shows it. `/multi-agent:assess` points at the docs comparison for the subagent-or-single choice instead. | vendor-claimed, watch | When a kept subagent is justified by tool or instruction conflict, fetch [Choose between subagents and main conversation](https://code.claude.com/docs/en/sub-agents#choose-between-subagents-and-main-conversation) live; correlate with [Building multi-agent systems](https://claude.com/resources/articles/building-multi-agent-systems-when-and-how-to-use-them) |

## Revisit triggers

Decisions deferred until the named evidence exists:

- **R1 Research sweep cost.** The discovery deep tier's fan-out default stays as is. The run
  measurements and the schema defect are on
  [#9810](https://github.com/melodic-software/claude-code-plugins/issues/9810). Recheck trigger:
  the next deep run of the same question shape and breadth is measured.
- **R2 User-scope spawning guidance.** No fold-back step is added to user-scope instructions (out
  of scope here; the dotfiles own them). Recheck trigger: a session audit or retro shows spawns
  that met none of the keep conditions in the docs section F8 points at.
- **R3 Folded-versus-kept eval recipe.** No recipe is added to the evals plugin. Recheck trigger:
  a skill or agent in this marketplace becomes a real fold candidate.
