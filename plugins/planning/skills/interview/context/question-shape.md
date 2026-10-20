# Question shape

## Contents

- [The shape](#the-shape)
- [Per lane](#per-lane)
- [Context](#context)
- [Plain names](#plain-names)
- [Scope](#scope)
- [Purpose and format (shared lane)](#purpose-and-format-shared-lane)
- [Schema version](#schema-version)

## The shape

One question shape serves all three lanes. The schema is
`<plugin-root>/shared/schema/question-shape.schema.json`; `<plugin-root>` is the placeholder
SKILL.md "Spoke paths" defines.

| Field | Holds |
|---|---|
| `id` | the ledger's `Q<N>`: one counter per topic, across rounds, lanes and sessions |
| `text` | the question, worded so "yes" accepts the recommendation |
| `short` | a label of at most 80 characters for lists |
| `scope` | the view, screen or artifact the question is about ([Scope](#scope)) |
| `context` | what drives the decision ([Context](#context)) |
| `recommendation` | the one recommended answer, or the `Withheld:` text |
| `basis` | opens `Checked against:` (see [Plain names](#plain-names)), then the `Basis:` label and the reasoning |
| `alternatives` | `{key, text, tradeoff}`, keys `a` to `d`; none restates the recommendation |
| `dependsOn` | earlier question ids only |

The rules in SKILL.md's Stance apply in every lane: one verdict marker, a `Basis:` on every
recommendation, a withheld question asked open, `Commits you to:` parts listed, yes accepting the
recommendation.

## Per lane

| Lane | Where each field goes |
|---|---|
| terminal | SKILL.md's per-question template: `Q<N>:` is `text`, the context line and `Source:` block are `context`, `My recommendation:`, `Basis:` and `Checked against:` are `recommendation` and `basis`, `Alternatives to consider:` lists `alternatives` |
| page | the round file fields in [`surface.md`](surface.md): `title` is `text`, `facts` carries the `Checked against:` line, then `context`, then any `Source:` block; `commits` holds the `Commits you to:` parts; at least two alternatives |
| shared | the fields above as written, plus `purpose`, `format`, `answerScope` and `references` ([`lane-shared.md`](lane-shared.md)); `scope` is required, and two or three alternatives |

## Context

Before the recommendation, `context` carries what drives the decision and nothing else:

- the problem the decision solves, in one or two sentences;
- what the source says or ships, paraphrased, with a short quote only where the exact words matter;
- what exists today and the gap;
- which parts of an absorbed idea come from the source and which are ours, labeled;
- any term the question relies on that the reader may not share, defined inline.

Every factual claim carries a link or `file:line` the reader can open. If removing a line would not
change how a reasonable person decides, remove it; long material goes behind a link. In the
terminal lane the context stays within SKILL.md's one context line plus the `Source:` block; the
page and the shared session have room for the whole block. A question shown again (unanswered from
last round, restated after async input) keeps its context, recommendation, basis and alternatives:
never a condensed form unless the user asks for one.

## Plain names

Show the human name in everything a person reads: questions, restatements, recaps, the page, labels
and reports. When the name stands alone, show only the name (`scoped change`, not `C3`). Pair a
code with its name only where the code must be quoted, such as a question id people answer by
(`question Q14, retry budget`). Expand a code to its real name, never to a metaphor; keep the
technical terms. On the page and in a shared session `Checked against:` names constraints in words;
the terminal line follows SKILL.md "Keep a running constraint ledger". The ledger may keep bare ids.

## Scope

Name the view, screen or artifact each question is about ("Payment step, pay button"), never "this
page" when several exist, and keep the scope current when a later round moves or renames it. Name
the thing asked about in the question text too: "Which device are you on right now?", not "What
are you using right now?", which a person can read as their activity. The
shared lane requires `scope`; the other lanes write it into the question when more than one artifact
is in play. Every answer in a shared session records the view and device it came from, so a question
whose scope is unclear gets answers about different things.

## Purpose and format (shared lane)

Infer each question's `purpose` from what the answer is for; there are no session templates, and the
owner may override one question from the Host view.

| `purpose` | When | How people answer |
|---|---|---|
| `decide` | one answer must be chosen | answers and votes; a moderator locks one |
| `gather` | many answers are wanted and all stand | answers and reactions; Claude summarizes from the digest |
| `poll` | a quick pick among fixed options | one pick each; results show after picking; the owner closes it |

Infer `format` the same way:

| `format` | When |
|---|---|
| `text` | free answers |
| `choice` | exactly one of two to four options (images allowed) |
| `multi` | any that apply, of two to eight options |
| `scale` | how much or how often: `1` to a `max` of 3 to 10, with `labels` for both ends (and `mid` if useful) |
| `rank` | an order of priority among three to six options |
| `confirm` | "Did you mean this?" on a screenshot with a marked area |
| `prototype` | two to six variants on their own page |

Only `text` carries a `recommendation`; elsewhere the options are the cards. Never write a
"Something else" or "Other" option: the server adds one to `choice`, `multi` and `rank`, and
`scale` and `confirm` take a comment.

A diagram or chart goes in `references` as `{kind: "diagram", asset, alt, caption?}`: an SVG
added with `add-asset`, drawn with whatever this session has or by hand. `alt` is required and
says what the picture shows in words.

A `rect` (the area a `confirm` question or an image reference marks) is in percent of the image,
0-100: `x + w` and `y + h` stay at most 100, and the server refuses a larger one.

## Schema version

The schemas under `<plugin-root>/shared/schema/` are the source of truth for every persisted and
wire shape. The state file carries no version: only the server stamps `pluginVersion` and `rev`;
never write or edit them, and never edit `state.json` by hand. A change to a persisted shape ships
no migration: when a later build cannot read a session, the owner starts a new one.
