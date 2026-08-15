---
topic: skill-architecture-guidance
section: progressive-disclosure
abstract: Spoke files cost nothing until read, so moving lines out of SKILL.md reduces context only when the spokes load CONDITIONALLY; an unconditional "read all spokes" split is net-negative, not merely neutral.
claims:
  - claim: "Bundled reference files consume zero context tokens until explicitly read; only metadata is preloaded at startup."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "The documented payoff condition for splitting is mutual exclusivity / rare co-use, not line count."
    confidence: HIGH
    tiers: [2]
    sources:
      - url: "https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills"
        tier: 2
        pool: "Anthropic (engineering blog)"
      - url: "https://agentskills.io/skill-creation/best-practices"
        tier: 1
        pool: "agentskills.io (Anthropic-authored standard, multi-vendor governed)"
  - claim: "Content Claude reads on every invocation is documented as belonging in SKILL.md, not in a spoke."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "Nested or deep references risk partial reads (head -100), so references must stay one level deep from SKILL.md."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "The two official sources disagree on the reference-file table-of-contents threshold: 100 lines vs 300 lines."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "Invoked SKILL.md content persists in the conversation for the session and is re-appended in full when dynamic-context output changes."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
produced_by: phase-3-falsification
---

# Progressive disclosure — does a hub/spoke split actually reduce context cost?

**Verdict: the peer reviewer is RIGHT. A split pays only when the spokes load conditionally. An
unconditional "read all spokes" instruction is pure line-shuffling — and slightly worse than neutral.**

This was the load-bearing question in the brief, and it was actively falsification-tested rather than
confirmed: the specific hunt was for any official statement that a shorter SKILL.md helps even when the
same total content is eventually read. None exists (see §3).

## 1. The mechanism is conditionality

<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>:

> At startup, only the metadata (name and description) from all Skills is pre-loaded. Claude reads SKILL.md only when the Skill becomes relevant, and reads additional files only as needed.

> **No context penalty for large files:** Reference files, data, or documentation don't consume context tokens until actually read.

The payoff condition is stated outright by Anthropic engineering,
<https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>:

> **If certain contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the token usage.**

And by agentskills.io:

> The key is telling the agent *when* to load each file. 'Read `references/api-errors.md` if the API returns a non-200 status code' is more useful than a generic 'see references/ for details.'

> Keep gotchas in `SKILL.md` where the agent reads them before encountering the situation. A separate reference file works if you tell the agent when to load it, but for non-obvious issues, the agent may not recognize the trigger.

## 2. The unconditional case is named as an anti-pattern — in the opposite direction

Same page, under observing how Claude navigates skills:

> **Overreliance on certain sections:** If Claude repeatedly reads the same file, consider whether that content should be in the main SKILL.md instead

So the docs do not merely fail to endorse the unconditional split — they prescribe reversing it.

**Why it is net-negative rather than neutral:** the same tokens still land in context, plus N extra
Read round-trips, plus partial-read risk:

> Claude may partially read files when they're referenced from other referenced files… Claude might use commands like `head -100` to preview content rather than reading entire files, **resulting in incomplete information**.

> **Keep references one level deep from SKILL.md.** All reference files should link directly from SKILL.md to ensure Claude reads complete files when needed.

**ToC threshold — the two official sources diverge.** best-practices.md: *"For reference files longer
than 100 lines, include a table of contents at the top."* `skill-creator/SKILL.md`: *"For large
reference files (>300 lines), include a table of contents."* Take 100 (Anthropic doc tier over repo
tier), and note the divergence rather than presenting either as settled.

## 3. Falsification attempt — what would have overturned this, and did not

The one remaining falsifier was whether *"under 500 lines **for optimal performance**"* encodes an
attention or recall benefit that would hold even with equal total read content. **It does not:
"optimal performance" is never defined in any official source.** The phrase appears three times in raw
`best-practices.md` (L257, L1132, L1144) as a bare assertion with no mechanism given. No attention,
recall, or "lost in the middle" rationale exists to cite.

**Conclusion stands, unqualified on that axis.**

## 4. One qualification the reviewer's framing misses — INFERRED from documented mechanics

<https://code.claude.com/docs/en/skills>, "Skill content lifecycle":

> the rendered `SKILL.md` content enters the conversation as a single message and stays there for the rest of the session.

> When the conversation is summarized to free context, Claude Code **re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each.** Re-attached skills share a combined budget of 25,000 tokens.

**INFERRED:** a hub under 5,000 tokens survives compaction **intact, with its spoke pointers**, and
Claude can re-read whichever spoke it needs. A monolith past 5k is truncated positionally with no
signal. Content already read out of a spoke is an ordinary Read result subject to normal summarization
— it is **not** re-attached.

This argues for **"keep the hub under 5,000 tokens"**, not for splitting as such.

**Also relevant to this specific skill**, which uses `` !` `` dynamic-context injections:

> When Claude re-invokes a skill whose rendered content is identical to the copy already in context, Claude Code adds a short note that the skill is already loaded rather than a second copy of the content. When the rendered content differs, because the arguments changed or a [dynamic context] command produced new output, Claude Code appends the full content again.

A ~10k-token body whose precomputed-context output drifts (a changed tool version string) re-appends
in full rather than deduplicating.

## 5. What this means for the split

Not "does the split pay" but **"split along which axis":**

- **Splitting to hit a line target** = line-shuffling on an unbacked number. See `RESEARCH-line-budget.md`.
- **Splitting per-source adapter detail into per-source spokes** = the documented pattern, and it pays. YouTube-specific and X-specific ingestion detail are mutually exclusive per invocation — verbatim the Anthropic engineering condition.
- **Shrinking the hub under 5,000 tokens** is separately justified by compaction mechanics, whatever the axis.

**Any spoke the hub tells Claude to read every time belongs in the hub.** The docs say so explicitly.
