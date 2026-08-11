# Book References — Canonical Naming

Single source of truth for how Pat Pattison's four books are cited
throughout this skill. Every context file references books by SHORT NAME +
year. The short name is used inline; the full title appears in file
headers.

## Canonical short names

| Short name | Full title | Year |
|---|---|---|
| **Essential Guide to Lyric Form and Structure** | *Songwriting: Essential Guide to Lyric Form and Structure* | 1991 |
| **Writing Better Lyrics** | *Writing Better Lyrics* | 2009 |
| **Songwriting Without Boundaries** | *Songwriting Without Boundaries* | 2011 |
| **Essential Guide to Rhyming** | *Pat Pattison's Songwriting: Essential Guide to Rhyming* | 2014 |

## Citation patterns — DO and DON'T

| DO | DON'T |
|---|---|
| `Essential Guide to Lyric Form and Structure (1991), Chapter 4` | `Book 1, Ch 4` |
| `Writing Better Lyrics (2009), Chapter 18` | `Book 2 Ch 18` |
| `Songwriting Without Boundaries (2011), Challenge 1, Day 5` | `Book 3 challenge 1` |
| `Essential Guide to Rhyming (2014), Chapter 7` | `Book 4 ch7` |

**"Chapter" is always spelled out, never abbreviated as "Ch" or "ch".**

**Never cite by book number ("Book 1", "Book 2") — cite by title** — the short
name + year carries the same disambiguation with zero risk of off-by-one
ordering arguments and zero risk of a reader guessing which book is which.

## File-header attribution template

Every `context/*.md` file MUST have a header attributing source books:

```markdown
# <Concept name>

Pat Pattison — *Essential Guide to Lyric Form and Structure* (1991),
Chapter 4. Extended by *Essential Guide to Rhyming* (2014), Chapter 1-2.
```

When a file synthesizes across multiple books, list them in chronological
order. When a file cites only one chapter, abbreviate to that line.

## In-prose anchor pattern

Inside file body, when sourcing a specific principle to a chapter:

> "<quote ≤25 words>" — Pat Pattison, *Essential Guide to Rhyming* (2014),
> Chapter 4

Or shorter inline cite when book context is already established:

The identity check (*Essential Guide to Rhyming* (2014), Chapter 1) — pre-
vowel consonants must differ.

## Multi-book synthesis cites

For concepts Pat developed across books (rhyme types, prosody, meter,
object writing):

```markdown
## Stability scale (synthesized)

Pat introduces the perfect-rhyme conditions in *Essential Guide to Lyric
Form and Structure* (1991), Chapter 4 and extends them through five
stability tiers in *Essential Guide to Rhyming* (2014), Chapters 4-6.
```

NOT: "Pat introduces this in Book 1 and extends it in Book 4."

## Public columns + articles (beyond-books context)

When citing Pat's columns / articles / podcast appearances, use:

```markdown
Pat Pattison — *American Songwriter* magazine, "Tools, Not Rules" column
```

```markdown
Pat Pattison — Coursera *Songwriting* (Berklee specialization), Module 3
"Sonic GPS"
```

```markdown
Pat Pattison — *What's in a Song* podcast, "Creating Metaphors" episode
(2024-08-05)
```

Date when relevant. Citation includes the publication / platform first,
then the title.

## Plugin-authored vocabulary — terms that are NOT Pat's

These terms are used throughout this plugin as working shorthand. **None of them
appears anywhere in the four-book corpus.** Each count below was measured against
the extracted text of all four books, wrap-safe:

| Term | Corpus hits | Status |
| --- | --- | --- |
| `tone of voice` | 0 | Plugin-authored shorthand. Keep, but never attribute to Pat. |
| `front-heavy` / `back-heavy` | 0 | Plugin-authored shorthand for phrase weighting. Same rule. |
| `central emotion` | 0 | **Do not use.** It truncates a real three-part phrase — see below. |

`central emotion` is a distortion rather than an invention, which is why sweeps
for fabricated quotes kept missing it. Pat's actual sentence is:

> The elements all join together to support the central intent, idea, and emotion
> of the work. Everything fits. Prosody: the appropriate relationship between
> elements.
> — Pat Pattison, *Writing Better Lyrics* (2009), Chapter 18

When the three-part idea is meant, write it in Pat's wording — "the central
intent, idea, and emotion" — not the shortened "central emotion."

A term being plugin-authored is not a defect and does not have to be removed.
Presenting one **as Pat's** is the defect. `stable-unstable-meta.md` carries the
worked example of the correction.

## Why this convention matters

- Book numbers are unstable references — readers (human or AI) re-order them
- Short names are self-disambiguating — "Essential Guide to Rhyming" can
  only be the 2014 book
- "Chapter" spelled out forces the AI to pause and verify the chapter
  number, which catches off-by-one errors
- File headers and inline cites use the SAME naming convention, so a reader
  can grep for `Essential Guide to Rhyming (2014)` and find every reference

## Cross-references

- All `context/*.md` files cite books by this convention
- `beyond-books.md` cites columns/courses/podcasts by the platform+title
  convention
- `response-filter.md` references this file when AI is about to cite a
  source — the AI verifies the canonical form before emitting
