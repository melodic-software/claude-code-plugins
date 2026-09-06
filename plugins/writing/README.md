# writing

Write prose a scanning reader can actually use.

One skill, `/writing:be-concise`. It reshapes text so the bottom line comes
first, no more words than the meaning needs survive, the structure holds up
under scanning, and the tone stays factual.

## Why this exists

Agents write a lot of prose that people have to read: tracker tickets and
comments, pull-request descriptions, changelogs, READMEs, status updates for
product owners and executives. Left alone they write walls of text, and the
reader skims, misses the ask, and stops trusting the channel.

Readers scan. They take in a fifth to under a third of the words on a page. In
the study this doctrine derives from, cutting a page to about half its words
raised measured usability by 58% on its own, and cutting, structuring and
de-hyping together raised it 124%. That is one 1997 study of 51 users and it
was never replicated, so the doctrine states it as such. What holds the rules
up is that six independent style authorities prescribe the same things.

## The two modes

| Invocation | What happens |
|---|---|
| `/writing:be-concise` | Sets a standing posture for the rest of the session |
| `/writing:be-concise <target>` | Reshapes that text and reports before and after word counts |

A target is whatever the agent can resolve with the tools it has: pasted text,
a file, a URL, a pull request, a tracker item.

## The floor

Completeness is not traded away. No decision, number, ask, error or warning is
ever dropped, a destination's own structural contract survives the rewrite, and
an already-posted record is never edited in place unless you say so. Where
brevity and completeness genuinely conflict, the bottom line goes first and the
full record stays below it or one link away.

## What it is not

- Terseness in flight on chat and code is `discipline:tighten-your-output`.
- Word-level trimming of a repo markdown file is `docs-hygiene:compress`.
- Restructuring a dense message without shortening it is `adhd:clarify`.
- Documentation genre and language standards at authoring time are
  `docs-hygiene:write-for-humans`.
- AI-writing tells are `ai-slop:audit`. This plugin adds no punctuation rule and
  inherits whatever that plugin's config says.

## Sources

The rules are paraphrased with drift stamps from Nielsen Norman Group's
concise, scannable and objective research, GOV.UK content design, the US
federal plain-language guidelines, Google's and Microsoft's style guides, and
BLUF. No upstream article text is vendored. Nielsen Norman Group's terms permit
short quotes with credit and forbid reposting articles, so this plugin
summarises and cites. Per-source records live in
`skills/be-concise/reference/sources.md`.
