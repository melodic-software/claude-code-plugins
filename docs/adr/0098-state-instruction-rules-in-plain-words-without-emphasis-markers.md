# State instruction rules in plain words without emphasis markers

- Status: accepted
- Date: 2026-11-11
- Refs: owner decision Q312 in the cohort hub interview, 2026-11-11

## Context

Instruction text in this repository (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, skill and agent
bodies, prompts) carries two kinds of emphasis: capital marker words such as `IMPORTANT`, `MUST`,
`NEVER`, `ALWAYS` and `CRITICAL`, and bold. The owner asked for the current Anthropic guidance to
decide how this text marks a rule.

Measured at commit a239e937da over 348 skill bodies and 35 agent bodies, outside frontmatter,
fenced blocks and inline code: 9,542 bold spans, a lower bound because a span wrapped across lines
is not matched; 62 `MUST`, `NEVER`, `ALWAYS` or `IMPORTANT` tokens; and 50 `CRITICAL` tokens, some
of them severity names. Bold runs at about 12 spans per 100 body lines; capitals are rare.

Two written rules covered emphasis before this record. The audit-instructions check I28 flagged
forced-compliance emphasis on triggers, exempted emphasis guarding a high-consequence area, and
named bold lead-ins as this repository's house style. The docs-hygiene `write-for-agents` skill
banned all-caps emphasis and kept firm words for a hard limit no hook enforces.

Basis, each a pointer to the live section rather than a copy of it. As of: 2026-11-11.

- [Best practices, What you can stop doing](https://code.claude.com/docs/en/best-practices#what-you-can-stop-doing)
  and [Keep CLAUDE.md short](https://code.claude.com/docs/en/best-practices#keep-claude-md-short):
  emphasis in capitals is listed as advice for older models, and a line Claude keeps missing goes
  to a hook or deny rule, or to a shorter file.
- [Memory, Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions):
  concrete, verifiable instructions under headers and bullets, in short files.
- [Skills, Claude stops following a skill](https://code.claude.com/docs/en/skills#claude-stops-following-a-skill):
  a rule that must hold every time moves into a hook.
- [Prompting Claude Fable 5.2, Keep caution from piling up](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-2#keep-caution-from-piling-up):
  rewrite absolute rules with their scope and reason. This page is stated for one model family;
  applying it to the others is judgment.

None of these pages addresses bold. The bold rule below is judgment: Anthropic's memory page itself
uses bold list-item labels, which reads as structure rather than emphasis.

Dissent, recorded and not followed:
[Agent Skills best practices, Develop Skills iteratively with Claude](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#develop-skills-iteratively-with-claude)
reports that a helper Claude might suggest stronger language such as "MUST filter" when a skill rule
is missed. It describes a possible suggestion in a refinement loop, not an authoring rule, and the
newer Claude Code pages point the other way.

## Decision

1. Instruction text states each rule in plain words with its scope and reason. It uses no all caps
   and no `IMPORTANT`, `MUST`, `NEVER`, `ALWAYS` or `CRITICAL` markers to make a rule stick. Plain
   firm words (never, always) stay allowed when the sentence gives the rule's scope and reason.
2. A rule that must hold every time moves to a hook, a deny rule or a CI check. A rule that keeps
   getting missed in a long file is fixed by shortening or splitting the file, not by louder words.
3. Bold is structure only: a list-item label, or a defined term at its first use. It never marks a
   whole sentence or a rule.
4. The decision applies when a file is next edited. Existing files are not rewritten in bulk.

Rejected: banning all bold, which removes list-item labels that the docs themselves use as
structure; keeping bold lead-ins as house style, which leaves bold doing the work capitals did; and
keeping I28's exemption for emphasis on a high-consequence area, since the docs send a rule that
cannot bend to a hook or deny rule, not to a louder marker.

## Consequences

- audit-instructions I28 no longer exempts emphasis guarding a high-consequence area: the marker is
  flagged and downgraded, and the directive stays with its scope and reason. Its scanner note no
  longer calls bold lead-ins house style.
- `write-for-agents` states the same rule, so authoring guidance and the audit agree.
- Emphasis in existing files leaves as those files are edited. The bold count above is the baseline
  to compare against.
- A must-hold rule found while editing becomes a candidate for a hook, deny rule or CI check rather
  than a reworded line.

## Revisit triggers

- One of the Claude Code sections above changes its guidance on emphasis, or a current model guide
  asks for emphasis markers back.
- An Anthropic page starts addressing bold in instructions, either way.
