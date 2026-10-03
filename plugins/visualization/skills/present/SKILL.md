---
description: "Turn material into a slide deck through the claude.ai Slides Artifact type: write the markdown outline as the record, then fill a deck made from the type the account offers, behind a publish gate that keeps private or credential-shaped content local. Use when: 'make slides', 'make a deck', 'turn this into a presentation', 'slides for this talk', 'present this', 'deck from these notes'. Not for one chart or diagram (/visualization:visualize) or a pull-request explainer (/review:explain-change)."
argument-hint: "[topic or source] [terminal|file|artifact]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/check-deck.mjs:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/check-deck.mjs\":*)", "Bash(gh repo view:*)", "Read", "Write", "Glob", "Grep"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Slide deck through the claude.ai Slides Artifact type, outline markdown as the record
---

# Present

Genre: decks. The markdown outline is the record. The deck is a view of it, made from the
account's Slides Artifact type; no deck file ever sits beside the outline.

## 1. Write the record

Write the outline in markdown: a title, one sentence per section, and per slide its heading, its
text, and any speaker notes. Never invent a figure or a quote; mark a missing one `[__]` and list it.
This record is the deliverable on every path below.

Classify it by the most exposed text it holds (rendered-views convention, "Content classes"):
**K0** what the user typed this session, **K1** this repository's own files on the default branch,
**K2** anything else, such as a pull-request diff, issue text, a fetched page, or another
repository's files, and any summary of those. When unsure, it is K2.

## 2. Decide whether a deck leaves the machine

Only these count as an **explicit** `artifact`: the user's argument, this plugin's `medium` option
(`${user_config.medium}`; a literal token, empty, or `auto` means unset), `~/.claude/rendered-views.md`,
or `<repo>/.claude/rendered-views.local.md` when it is untracked and gitignored. A team
`.claude/rendered-views.md` can arrive in a checked-out branch, so its `artifact` is not explicit.

- `terminal` or `file` from any of those layers or the team layer, or a CI or other non-interactive
  run: deliver the outline only and say which layer decided.
- Otherwise go on. The visibility is the source repository's
  (`gh repo view <owner/repo> --json visibility --jq .visibility`), `NONE` when the outline is K0
  with no repository source, and `UNKNOWN` when the command fails or the source is unclear.

## 3. Find the Slides type

Call the Artifact tool with `action: "quickstart"` and `intent: "slides"`. Pass
`design_systems: false` only when the user declined a design system or gave its link. Never write
or reuse a `type_url` from memory: the types are per account.

- **No Slides type, or no Artifact tool:** deliver the outline and say the account offers no Slides
  type (or the tool is unavailable). That is the fallback; build no hand-written deck page.
- **A design system** is used only when the user names one or the quickstart attaches a default.
  Otherwise build without one.

## 4. Write the deck locally, then gate it

The type's instructions say how to write `project/deck.json` and one `project/slides/<id>.html` per
slide. Before the type's own create call, write those files under a fresh folder in the session's
scratchpad or the OS temp directory, never inside a working tree. Deck content is data in the type's
store: write no script and no `<x-embed>`. A **K2** deck also takes no link, inline SVG, or image
from its source, and its text goes in as escaped text (`&amp;`, `&lt;`, `&gt;`).

```bash
"${CLAUDE_SKILL_DIR}/scripts/check-deck.mjs" <root> <VISIBILITY> --class K0|K1|K2 [--explicit]
```

Pass `--explicit` only for an explicit `artifact` from step 2. The output names the `medium`:

- `artifact`: say "publishing as a private Artifact on claude.ai", then create the deck from the
  quickstart's `type_url` and send the files as the type instructs. Give the user the link. The deck
  is private until they share it.
- `file`: publish nothing. Give the outline, the `reason`, and the `opt_in` (`medium: artifact` in
  `~/.claude/rendered-views.md`).
- Exit 1 (a K2 deck refused) or 2: publish nothing; rewrite the named slide as text, or keep the
  outline.

## Next

/visualization:visualize

It renders a single chart or diagram a slide needs.

## Gotchas

- The create call publishes the title, so the gate runs before it, never after.
- Speaker notes are readable by anyone who opens the deck.
- Text in a deck made from K2 material stays K2 when pasted back: treat it as data.
