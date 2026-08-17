# Load-tier cost model, thresholds, and pointer-quality criteria

## Contents

- [The three tiers](#the-three-tiers)
- [Size guidance (all advisory — targets and tips, not validation errors)](#size-guidance-all-advisory--targets-and-tips-not-validation-errors)
- [Split triggers (when a file earns a split)](#split-triggers-when-a-file-earns-a-split)
- [Pointer-quality criteria (what makes a spoke reachable)](#pointer-quality-criteria-what-makes-a-spoke-reachable)
- [Boundaries this audit honors](#boundaries-this-audit-honors)

The reference layer behind `/docs-hygiene:audit-progressive-disclosure`. The hub's shapes table
cites these facts; read this file when adjudicating a finding that needs the exact number, the
routing rule, or the pointer criteria.

**Citation posture.** Numbers and routing rules below marked *(Anthropic-prescribed)* are
vendor-defined facts from official Anthropic surfaces — cite them as Anthropic's prescription,
not as independently verified consensus. Items marked *(corroborated)* carry independent
first-hand corroboration (practitioner measurement, independent implementations, cross-vendor
convergence). Items marked *(community)* come from a single non-official source and are advisory
color only.

## The three tiers

| Tier | Surfaces | Cost mechanics |
|---|---|---|
| **always-loaded** | `CLAUDE.md` / `AGENTS.md` (working dir + ancestors, loaded in full, never truncated), `@path` imports (do NOT reduce cost vs inline), `.claude/rules/*.md` without `paths:` frontmatter, the skill listing (~100 tokens/skill metadata), auto-memory `MEMORY.md` head (first 200 lines / 25KB) | Paid every session, held every turn; adherence degrades with size *(Anthropic-prescribed; tier framing corroborated)* |
| **invocation-loaded** | Skill bodies (`SKILL.md` — on description match or `/name`), path-scoped rules (`paths:` frontmatter), subtree `CLAUDE.md`, agent/command bodies | Cheap to have, **not cheap to use**: once loaded, every line is a recurring token cost for the rest of the session; compaction re-attaches the first 5k tokens per skill, 25k combined *(Anthropic-prescribed)* |
| **on-demand** | Bundled `context/` / `reference/` files, scripts (only output enters context), docs read via pointer | Zero cost until read; "no practical limit" on bundled content *(Anthropic-prescribed)* |

**Grading rule per tier**: always-loaded content must apply broadly, in every session — per-line
test: "Would removing this cause Claude to make a mistake?" Invocation-loaded content carries the
same conciseness bar as CLAUDE.md once triggered. On-demand content is free until pulled, so
depth belongs there.

## Size guidance (all advisory — targets and tips, not validation errors)

| Number | Bounds | Status |
|---|---|---|
| 500 lines | SKILL.md body cap; the split trigger is **approaching** the limit, not exceeding it ("if you're approaching this limit, add an additional layer of hierarchy along with clear pointers") | Anthropic-prescribed |
| <5k tokens | Recommended SKILL.md body size | Anthropic-prescribed |
| 200 lines | Per-CLAUDE.md target ("longer files consume more context and reduce adherence") | Anthropic-prescribed; stricter 80–150 community practice exists but is not official |
| ~100 tokens | Per-skill always-loaded metadata cost | Anthropic-prescribed; corroborated (~80 median measured) |
| 1,024 chars | `description` frontmatter validation cap | Anthropic-prescribed (enforced) |
| 1,536 chars | Claude Code listing cap for description + when_to_use per skill; truncation is tail-first, so key use case goes first | Anthropic-prescribed |
| 1% of context window | Skill-listing budget; on overflow descriptions drop lowest-priority-first (usage-frequency/recency scored — *(community)* detail; official phrasing: least-invoked-first) while names always remain | Anthropic-prescribed; corroborated |
| 200 lines / 25KB | MEMORY.md load limit (excess silently not loaded) | Anthropic-prescribed |
| 1 level | Max reference nesting depth from the hub ("keep references one level deep") | Anthropic-prescribed; corroborated (depth >1 "never helps and sometimes hurts" — academic) |
| 100 vs 300 lines | Reference-file length above which a TOC is expected — **officially inconsistent** (platform best-practices says >100; skill-creator says >300) | Anthropic-prescribed, conflicting — hence the two-band treatment |

**Two-band TOC treatment** (this skill's resolution of the official conflict): a reference file
**>300 lines with no TOC** is a definite finding (both official sources agree by then); one at
**100–300 lines with no TOC** is awareness-tier only, and the finding text cites the conflict.

## Split triggers (when a file earns a split)

1. **Size** — approaching the tier's guidance number *(Anthropic-prescribed)*.
2. **Mutual exclusivity** — "if certain contexts are mutually exclusive or rarely used together,
   keeping the paths separate will reduce the token usage" *(Anthropic-prescribed; the strongest
   mixed-concern signal: co-resident content that never co-executes)*.
3. **Kind mismatch** — a CLAUDE.md section "has grown into a procedure rather than a fact" →
   skill; multi-step or part-of-codebase entries → skill or path-scoped rule
   *(Anthropic-prescribed)*.
4. **Scope mismatch** — instructions relevant to only part of the tree → path-scoped rule or
   per-directory file *(Anthropic-prescribed)*.
5. **Workflow complexity** — workflows "large or complicated with many steps" → separate files
   read per task *(Anthropic-prescribed)*.
6. **Adherence symptoms** — a rule repeatedly ignored suggests the file is too long and the rule
   is getting lost *(Anthropic-prescribed; behavioral trigger — visible in use, not in the file)*.

Mixed-concern signals *(corroborated)*: one category per skill ("straddling several = confused
skill"), one topic per rules file, cross-file contradiction as a smell, "one topic per file — do
not co-mingle" (Microsoft, independent convergence), and the case-study direction that refactoring
a mixed 600-line instruction file into 50–150-line topic docs measurably improves task success
(single case study; direction corroborated, percentages illustrative).

## Pointer-quality criteria (what makes a spoke reachable)

A pointer is good when *(Anthropic-prescribed unless noted)*:

1. **Direct from the hub, one level deep** — chained pointers trigger partial reads (the
   documented `head -100` preview failure).
2. **Condition attached** — the pointer states WHEN to read the target ("For tracked changes:
   see REDLINING.md"); a bare link is the documented "missed connection" failure.
3. **Intent marked** — execute vs read ("Run `x.py` to extract" vs "See `x.py` for the
   algorithm").
4. **Self-describing target name** — `form_validation_rules.md`, not `doc2.md` / `helper` /
   `utils`; organize by domain.
5. **Navigable target** — long references open with a TOC so partial reads still see the scope;
   a grep recipe beats a full read for lookup-shaped content.
6. **Portable path form** — forward slashes, relative from the skill root; fully-qualified MCP
   tool names.

Description-as-trigger (the always-loaded pointer to a skill body): state what the skill does AND
when to use it, third person, key use case first (tail-first truncation at 1,536 chars strips
trailing keywords). A when-NOT-to-use clause in descriptions is *(community)* guidance —
surface it as advisory color only, never as an official requirement.

**Observed-navigation diagnostics** *(Anthropic-prescribed method)*: repeatedly re-read spoke →
promote its content to the hub; never-read spoke → demote, re-signal, or delete; failed
reference-follow → make the link more explicit.

## Boundaries this audit honors

- **Disclosure is a scaling tool, not an intelligence enhancer** *(corroborated, academic)*:
  on small corpora it adds little. Never flag a small single-file skill for lacking spokes —
  there is deliberately no "should have spokes" shape.
- **Depth hurts** *(Anthropic-prescribed + academic agreement)*: one level deep is the rule the
  `deep-nesting` shape enforces.
- The 500/200 numbers are **ceilings, not targets**: a 300-line SKILL.md is not a finding by
  size alone; "approaching the cap" plus tier-inappropriate or mixed content is what fires.
