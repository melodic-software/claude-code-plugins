# Upstream source: "Building with Claude Sonnet 5.5"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Decisions](#decisions)
- [Handed to other sessions](#handed-to-other-sessions)
- [Correlating later posts](#correlating-later-posts)

This is the provenance record for acting on the claude.dev post about building with Sonnet 5.5. It
follows the record shape of [opus-5-5-usage-guide.md](opus-5-5-usage-guide.md) and the
[upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each row is our
decision in our own words; no row restates the post or a docs page.

## Status

The first slice merged in #5676 (2026-10-01): the effort, thinking and compaction pointers and the
usage-limit reset fix, tracked by parent #5674 with sub-issue #5675; #5673 tracks guard-hook
friction found along the way. This follow-up adds this record and the boris skill rows the first
slice missed.

## Source and verification

- Correlate with `https://claude.dev/blog/building-with-claude-sonnet-5-5/` (published 2026-09-28,
  digested and dual-verified 2026-09-29 to 2026-10-01). It is never the pointer where a docs
  section covers the topic.
- Pointer for model behavior in Claude Code: [Model configuration](https://code.claude.com/docs/en/model-config),
  sections named per row, read 2026-10-01.
- Pointer for instruction files: [How Claude remembers your project](https://code.claude.com/docs/en/memory),
  read 2026-10-01.

## Row schema

**Topic** names the item with an ID other files cite; **Ours** is what this repository now does
and where; **Pointer** is the docs section a reader checks live. Shared for every row:

- **As of**: 2026-10-01
- **Recheck trigger**: the pointed-to section is renamed or removed, stops covering its topic, or
  the next Sonnet release.

## Decisions

| Topic | Ours | Pointer |
|---|---|---|
| B1 Default effort per model | Lanes and the boris playbook leave effort at its default and point at the docs instead of stating a model's default: `prompts/loops/loop-lane-prompts.md` (Models), boris `SKILL.md` (Effort and xhigh rows), `advanced.md`, `autonomy.md` (including a superseded note on tip 67). Audit criteria that must name a model's default to check against it are out of this row's scope | [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) |
| B2 Models that always think | Instructions targeting such models change effort instead of adding "think carefully" lines; no model list is kept. Boris `autonomy.md`; the `foundations.md` model-selection note | [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking) |
| B3 Auto-compaction thresholds | context-guard keeps its zone bands below the compaction trigger and states its margin against an assumed trigger, without the published trigger figure; `reader-contract.md` "Zone is not a compaction indicator" | [Default auto-compact thresholds](https://code.claude.com/docs/en/model-config#default-auto-compact-thresholds) |
| B4 Usage-limit reset that names only a clock time | A probed defect in our tooling, not an upstream claim: the keep-going checker takes the time the message was shown and resolves an already-past clock time to the next day; keep-going treats a "lifted" verdict as provisional without that time | Probe: `plugins/session-flow/skills/keep-going/scripts/check-usage-limit-reset.test.py`, #5675 |
| B5 Growing CLAUDE.md after every correction | Boris `foundations.md` §4 carries an amendment: prune as you add, and move scoped rules and procedures out of CLAUDE.md | [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions) |

## Handed to other sessions

Findings the post surfaced on files other sessions own were sent to them and acknowledged; their
records own the decisions:

- The Sonnet 5.5 prompting-digest session: workload and counting rules, the advisor-pairing
  question (resolved upstream before any change), the Priority Tier and between-tools conflicts
  (handed off to be recorded beside the Sonnet 5.5 adaptation chapter),
  docpage-digest pipeline defects, and the source of a blog-body extractor for docpage-digest.
- Interview-page defects on #5569.

## Correlating later posts

A later claude.dev post on Sonnet models is correlated here: add it as a correlate note beside the
row it touches, and move a row's pointer only to a docs section, never to a post.
