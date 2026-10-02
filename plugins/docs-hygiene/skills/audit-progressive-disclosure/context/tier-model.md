# Load-tier cost model, thresholds, and pointer-quality criteria

## Contents

- [The three tiers](#the-three-tiers)
- [Size guidance (all advisory: targets and tips, not validation errors)](#size-guidance-all-advisory-targets-and-tips-not-validation-errors)
- [Split triggers (when a file earns a split)](#split-triggers-when-a-file-earns-a-split)
- [Pointer-quality criteria (what makes a spoke reachable)](#pointer-quality-criteria-what-makes-a-spoke-reachable)
- [Boundaries this audit honors](#boundaries-this-audit-honors)

The reference layer behind `/docs-hygiene:audit-progressive-disclosure`. The hub's shapes table
cites these facts; read this file when adjudicating a finding that needs the exact number, the
routing rule, or the pointer criteria.

**Citation posture.** Every number and rule below is this audit's own setting, in our words; the
pages behind them are pointed at, never quoted. Items marked *(Anthropic-prescribed)* are settings
we take from official Anthropic pages: cite them as Anthropic's prescription, not as independently
verified consensus, and read the wording at the pointer. Items marked *(corroborated)* carry
independent first-hand corroboration (practitioner measurement, independent implementations,
cross-vendor convergence). Items marked *(community)* come from a single non-official source and
are advisory color only.

## The three tiers

| Tier | Surfaces | Cost model this audit grades with |
|---|---|---|
| **always-loaded** | `CLAUDE.md` / `AGENTS.md` (working dir + ancestors, loaded in full), `@path` imports (no saving over inline), `.claude/rules/*.md` without `paths:` frontmatter, the skill listing (~100 tokens/skill metadata), auto-memory `MEMORY.md` head (first 200 lines / 25KB) | Paid every session, held every turn; we treat adherence as degrading with size *(Anthropic-prescribed; tier framing corroborated)* |
| **invocation-loaded** | Skill bodies (`SKILL.md`, on description match or `/name`), path-scoped rules (`paths:` frontmatter), subtree `CLAUDE.md`, agent/command bodies | Cheap to have, **not cheap to use**: once loaded, every line is a recurring token cost for the rest of the session; we price the compaction re-attach at the first 5k tokens per skill, 25k combined *(Anthropic-prescribed)* |
| **on-demand** | Bundled `context/` / `reference/` files, scripts (only output enters context), docs read via pointer | Zero cost until read; we set no size limit on bundled content *(Anthropic-prescribed)* |

**Grading rule per tier**: always-loaded content must apply broadly, in every session. The
per-line test: flag a line whose removal would not lead Claude into a mistake. Invocation-loaded
content carries the same conciseness bar as CLAUDE.md once triggered. On-demand content is free
until pulled, so depth belongs there. A recorded reason to stay always-loaded overrides the test,
and upstream ownership overrides the local treatment (the finding stays): see
[Boundaries this audit honors](#boundaries-this-audit-honors).

## Size guidance (all advisory: targets and tips, not validation errors)

| Number | Bounds | Status |
|---|---|---|
| 500 lines | SKILL.md body cap; the split trigger fires when a file is **approaching** the cap, not only past it | Anthropic-prescribed |
| <5k tokens | Target SKILL.md body size | Anthropic-prescribed |
| 200 lines | Per-CLAUDE.md target; we read a longer file as costing context and adherence | Anthropic-prescribed; stricter 80–150 community practice exists but is not official |
| ~100 tokens | Per-skill always-loaded metadata cost | Anthropic-prescribed; corroborated (~80 median measured) |
| 1,024 chars | `description` frontmatter validation cap | Anthropic-prescribed (enforced) |
| 1,536 chars | Claude Code listing cap for description + when_to_use per skill; we treat truncation as tail-first, so the key use case goes first | Anthropic-prescribed |
| 1% of context window | Skill-listing budget; we treat an overflow as dropping descriptions, never names (a usage-frequency/recency scoring of the drop order is a *(community)* detail; read the official order at the pointer) | Anthropic-prescribed; corroborated |
| 200 lines / 25KB | MEMORY.md load limit; we treat the excess as not loaded | Anthropic-prescribed |
| 1 level | Max reference nesting depth from the hub | Anthropic-prescribed; corroborated (an academic source finds deeper nesting no help and sometimes harmful) |
| 100 vs 300 lines | Reference-file length above which a TOC is expected; two Anthropic sources disagree on it (record below), hence the two-band treatment | Anthropic-prescribed, conflicting |

**Provenance of the vendor numbers in both tables.**

- **Pointer** (Claude Code-side values: the 1,536 listing cap and its truncation, the 1% listing
  budget, the 5k-per-skill / 25k-combined compaction re-attach, the `MEMORY.md` head limits, the
  200-line CLAUDE.md target):
  [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference),
  [Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle),
  [Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short),
  [`skillListingBudgetFraction`](https://code.claude.com/docs/en/settings-reference#skilllistingbudgetfraction),
  auto memory's [How it works](https://code.claude.com/docs/en/memory#how-it-works) and
  [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions).
- **Pointer** (authoring-side values: the 500-line body cap, the <5k-token body, the ~100
  tokens/skill metadata, one-level nesting, the >100-line TOC band):
  [Token budgets](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#token-budgets),
  [How Skills work](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work),
  [Avoid deeply nested references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-deeply-nested-references)
  and [Structure longer reference files with table of contents](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#structure-longer-reference-files-with-table-of-contents).
- **Pointer** (the 1,024-character `description` cap): the Agent Skills specification's
  [`description` field](https://agentskills.io/specification#description-field). We treat it as
  enforced on upload paths, not by Claude Code locally.
- **As of**: 2026-10-01
- **Recheck trigger**: a fetch of the owning page no longer carrying a table row's value
  re-derives that row; each fleet audit re-runs the whole table.

**TOC threshold conflict.** The platform best-practices section
[Structure longer reference files with table of contents](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#structure-longer-reference-files-with-table-of-contents)
and skill-creator's
[Progressive Disclosure](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md#progressive-disclosure)
disagree on the reference-file length above which a TOC is expected.

- **As of**: 2026-10-01
- **Recheck trigger**: either source changes its threshold, or the two come to agree.

**Two-band TOC treatment** (this skill's resolution of that conflict): a reference file
**>300 lines with no TOC** is a definite finding (both sources agree by then); one at
**100–300 lines with no TOC** is awareness-tier only, and the finding text cites the conflict.

## Split triggers (when a file earns a split)

1. **Size**: approaching the tier's guidance number *(Anthropic-prescribed)*.
2. **Mutual exclusivity**: content for situations that never or rarely arise in the same task,
   split so each part loads alone *(Anthropic-prescribed; the strongest mixed-concern signal:
   co-resident content that never co-executes)*.
3. **Kind mismatch**: a CLAUDE.md section that has turned into a procedure → skill; multi-step or
   part-of-codebase entries → skill or path-scoped rule *(Anthropic-prescribed)*.
4. **Scope mismatch**: instructions relevant to only part of the tree → path-scoped rule or
   per-directory file *(Anthropic-prescribed)*.
5. **Workflow complexity**: a long, many-step workflow → its own file, read per task
   *(Anthropic-prescribed)*.
6. **Adherence symptoms**: a rule the model keeps skipping, which we read as a sign the file has
   grown past what it can hold *(Anthropic-prescribed; a behavioral trigger, visible in use, not in
   the file)*.

- **Pointer**: for separate files loaded only when needed, see
  [Progressive disclosure patterns](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns)
  and [Use workflows for complex tasks](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#use-workflows-for-complex-tasks);
  for what belongs in CLAUDE.md, see
  [When to add to CLAUDE.md](https://code.claude.com/docs/en/memory#when-to-add-to-claude-md); for
  the ignored-rule symptom, see
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).
- **As of**: 2026-10-01
- **Recheck trigger**: one of those sections stops supporting the trigger that cites it.

Mixed-concern signals *(corroborated)*: one category per skill (a skill that straddles several
is a confused one), one topic per rules file, cross-file contradiction as a smell, one topic per
file with no co-mingling (Microsoft guidance, independent convergence), and the case-study
direction that refactoring a mixed 600-line instruction file into 50–150-line topic docs
measurably improves task success (single case study; direction corroborated, percentages
illustrative).

## Pointer-quality criteria (what makes a spoke reachable)

A pointer is good when *(Anthropic-prescribed unless noted)*:

1. **Direct from the hub, one level deep**: we treat a chained pointer as inviting a partial
   preview read of the deeper file instead of a full read.
2. **Condition attached**: the pointer states WHEN to read the target ("For a schema change:
   read MIGRATIONS.md"); a bare link is one Claude may never follow.
3. **Intent marked**: execute vs read ("Run `fetch.py` to pull the rows" vs "Read `fetch.py`
   for the retry rules").
4. **Self-describing target name**: `retry_policy.md`, not `notes2.md` / `helper` / `utils`;
   organize by domain.
5. **Navigable target**: long references open with a TOC so partial reads still see the scope;
   a grep recipe beats a full read for lookup-shaped content.
6. **Portable path form**: forward slashes, relative from the skill root; fully-qualified MCP
   tool names in the form Claude Code resolves, `mcp__<server>__<tool>` for a configured server
   and `mcp__plugin_<plugin>_<server>__<tool>` for a server a plugin bundles.
   Pointer: [permissions, "MCP"](https://code.claude.com/docs/en/permissions#mcp) and
   [MCP, "Plugin-provided MCP servers"](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers).
   As of: 2026-09-10. Recheck trigger: either page changes the form. The platform page's
   [MCP tool references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#mcp-tool-references)
   form applies to other surfaces; we grade against the harness form.

- **Pointer** (criteria 1-5): [Avoid deeply nested references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-deeply-nested-references),
  [Progressive disclosure patterns](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns),
  [Provide utility scripts](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#provide-utility-scripts),
  [Runtime environment](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#runtime-environment)
  and [Structure longer reference files with table of contents](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#structure-longer-reference-files-with-table-of-contents).
- **As of**: 2026-10-01
- **Recheck trigger**: one of those sections stops supporting the criterion that cites it.

Description-as-trigger (the always-loaded pointer to a skill body): name the skill's job AND the
situations that call for it, third person, key use case first (tail-first truncation at 1,536 chars strips
trailing keywords). A when-NOT-to-use clause in descriptions is *(community)* guidance, so
surface it as advisory color only, never as an official requirement.

**Observed-navigation diagnostics** *(Anthropic-prescribed method)*: repeatedly re-read spoke →
promote its content to the hub; never-read spoke → demote, re-signal, or delete; failed
reference-follow → make the link more explicit. Pointer:
[Observe how Claude navigates Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#observe-how-claude-navigates-skills).
As of: 2026-10-01. Recheck trigger: that section is removed or changes the method.

## Boundaries this audit honors

- **Disclosure is a scaling tool, not an intelligence enhancer** *(corroborated, academic)*:
  on small corpora it adds little. Never flag a small single-file skill for lacking spokes.
  There is deliberately no "should have spokes" shape.
- **Depth hurts** *(Anthropic-prescribed + academic agreement)*: one level deep is the rule the
  `deep-nesting` shape enforces.
- The 500/200 numbers are **ceilings, not targets**: a 300-line SKILL.md is not a finding by
  size alone; "approaching the cap" plus tier-inappropriate or mixed content is what fires.
- **A recorded reason to stay always-loaded satisfies the "apply broadly, in every session" test**:
  an ADR or decision doc, or a need for sessions without the plugin or with a synced copy to see
  the content. A file owned upstream (synced, vendored, generated) is never a local-edit target;
  its finding routes to the owner, per the Ownership check hard rule in `SKILL.md`.
