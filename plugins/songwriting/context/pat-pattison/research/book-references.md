# Book References — Canonical Naming

Single source of truth for how Pat Pattison's four books are cited
throughout this skill. Every context file references books by SHORT NAME +
year. The short name is used inline and in file headers.

## ⚠ WHAT "VERBATIM" COVERS — read this before auditing anything

**Verbatim means the WORDS.** Reproduce Pat's examples, exercises, answer keys,
tables and analysed lyrics exactly as printed: no paraphrase, no genericizing,
no invented substitutes.

**It does NOT mean punctuation glyphs.** ASCII `'` and `"` versus curly `’`
`“` `”` are typography, not content. This repo is GitHub-flavored Markdown and
either form is acceptable. The four books are not even consistent with each
other — the 2009 EPUB prints ASCII apostrophes, the other three print curly.

**Do not sweep, measure, audit, or open work items on punctuation glyphs.** A
session was spent on exactly that before the owner ruled it out of scope. If a
restoration reproduces the printed words, it is verbatim, full stop. Spend the
effort on missing content, invented content, and wrong citations instead.

**Two places deliberately carry a title longer than the short name — do not
"normalize" either one:** this file's bibliographic table below, and the
buy-the-books list in the plugin `README.md`. That list exists so a reader can go
and purchase the books, which is the one job a short name does not do.

This only affects the 1991 and 2014 books; the 2009 and 2011 short names *are*
their full titles, so those two entries look identical everywhere. Note the
README deliberately stops short of the full catalogue string for 1991: its
`dc:title` is `Songwriting: Essential Guide to Lyric Form and Structure: Tools
and Techniques for Writing Better Lyrics (Songwriting Guides)`, and the subtitle
and series marker are dropped because they are not needed to find the book.

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

### `Challenge #N` vs `Challenge N` — the hash boundary

**The 2011 book prints the hash.** Its chapter titles are `Challenge #1: Object
Writing`, `Challenge #2: Metaphor`, and Pat uses the hash in running prose too
("You'll become very familiar with this process in Challenge #3"). Our citation
convention drops it, as the table above shows. Both are deliberate, and the
boundary is by **role, not by file**:

| Role | Form | Why |
|---|---|---|
| **Our citation apparatus** — attribution lines, file headers, source lists, in-prose anchors | `Challenge 4` | Matches `Chapter N` for the other three books, so one citation grammar covers all four |
| **Verbatim reproduction** — anything inside a quotation, and any place reproducing the book's own chapter title as printed | `Challenge #3` | It is quoted source. Altering transcribed text to match a house convention is the fabrication this project exists to prevent |

`metaphor.md` shows both in the same section and is the worked example: its
citation reads `Challenge 3 ("Object Writing with Metaphor")`, and Pat's quoted
sentence four lines later keeps `Challenge #3`. **That is not an inconsistency
— do not "normalize" it.** The same rule is why the 1991 book's chapter titles
are quoted as printed while its citations read `Chapter 3`.

**A citation that glosses the title is still a citation.**
`audit-checklist.md:178` reads `Challenge 4 "Writing in Rhythm & Rhyme"` — no
hash — and that is correct, even though the book's own chapter title is
`Challenge #4: Writing in Rhythm & Rhyme`. The line is citing the challenge and
naming it for the reader, in the same shape as the 1991 citation beside it
(`Chapter 3 "Rhythm: Setting Up, Shutting Down"`). **Do not read it as a title
reproduction and re-add the hash.** The verbatim branch applies only where the
title is being reproduced *as printed text* — inside a quotation, a transcribed
figure, or a heading that reproduces the book's own.

## Image-only figure content — render, read, transcribe

**Some content in these books exists only inside a scanned figure**, with no
counterpart in the EPUB text layer. Transcribing it from a rendered page image
is **permitted and expected**, under these conditions:

- **Render the figure and read it by eye. OCR is forbidden**, always, with no
  exception — a misread stress mark or a swallowed word is indistinguishable
  from a fabrication once it is in the file.
- **A named PNG stands behind every transcription.** Name the figure in the
  file (`fig image_rsrc34F`) so any later reader can re-render and re-check it.
- **Crop one row at a time and magnify.** Scansion marks are unreadable at
  whole-figure zoom; 12x or better on a single row is the working threshold.
- This covers **lyrics too**, not just tables and answer keys. `hook.md`
  transcribes figs `34F` and `34G`; `cliche.md` reads a full page inventory
  figure; `bridge.md` restores a list that is printed only in `image_rsrc32E`.

**Do not conclude "image-only" from a failed search.** Before recording any
content as absent from the text layer, search **every book's every spine file**
— not just the spine that holds the figure — and search **line by line**. Fig
`34F`'s lyric was recorded as image-only for two releases because the search was
scoped to the chapter containing the figure while the same verse is printed as
prose six chapters earlier — Chapter 1, against the figure in Chapter 7. One
line of it still returns nothing, because the
text layer misspells a word: **a single line that fails to match when its
neighbours match means "look for a typo", not "absent".**

**When the scan and the text layer disagree, say so and stop.** Figures are
photographs of the printed page; the text layer is a reflow of it, and it can
carry defects the scan does not. Record both readings and which witness is
which. Never edit one to agree with the other.

## File-header attribution template

Every `context/*.md` file MUST have a header attributing source books:

```markdown
# <Concept name>

Pat Pattison — *Essential Guide to Lyric Form and Structure* (1991),
Chapter 4. Extended by *Essential Guide to Rhyming* (2014), Chapters 1-2.
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

## Vocabulary that is NOT in the four books

**"Not in the books" and "not Pat's" are different claims. Do not collapse
them** — an earlier version of this table did, and was wrong. Pat teaches
outside the books too, and terms he coins in a column are still his.

Each corpus count below was measured wrap-safe against the extracted text of all
four books:

| Term | Corpus hits | Status |
| --- | --- | --- |
| `front-heavy` / `back-heavy` | 0 | **Pat's own coinage**, outside the books — see below. Citable to the column, never to a book. |
| `tone of voice` | 0 | Not located in any Pat source, book or column. Treat as plugin shorthand; never attribute to Pat. |
| `central emotion` | 0 | **Do not use.** It truncates a real three-part phrase — see below. |

`front-heavy` / `back-heavy` are Pat's, coined in his patpattison.com column
"The Art of Phrasing" (fetched and read 2026-08-11,
<https://www.patpattison.com/art-of-phrasing>), which defines both:

> "We'll call phrases that start on the downbeat of a bar, or pick up to the
> downbeat, front-heavy."
> "We'll call phrases that start after the downbeat back-heavy."

So the correct caveat on these two is **"not in the four books, cite the
column"** — not "not Pat's". `phrasing.md` had this right before this table did.

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
