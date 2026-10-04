# Sentence rules: address, load, and ambiguity

The three sentence-level layers of the default set, in one file because they apply to every sentence
at once. Splitting them by standard would make you open three files per sentence.

Read this while drafting. It is the fallback set. When the consuming project declares its own style
guide, that guide replaces everything here, and the skill body says so before you get this far.

Every example below documents one made-up backup tool, `stash`, so the rules can be compared on the
same material. Its `stash export` command writes an archive; `--since` limits it by date.

## Address: how the sentence talks to the reader

Our paraphrased selection from the Google developer documentation style guide, grouped by the
part of the page you are checking.

**Page elements.** Check these on every page before reading a single sentence:

- Formatting: commands, flags, and file names in code font (`stash export`); UI labels in bold.
- Links: the link text is the title of the target page or a few words that describe it, such as
  "Export flags". "Click here" tells the reader nothing about where it goes. When the reader needs
  only a sentence of context, write it on the page instead of linking away.
- Headings: sentence case, a single h1, and levels that never jump past one. A heading says what
  the section concludes or does, not only its subject: "Export one table", not "Exporting". Phrase
  task headings as verb phrases with no subject, and concept headings, such as "Archive layout",
  as noun phrases.
- Lists: numbers when order matters, bullets otherwise. A complete sentence comes before every
  list, and every item has the same grammatical form.
- Series: use the serial comma ("tables, views, and indexes"). Never end a list with "etc."; if
  the list is incomplete, the sentence before it says so.

**Sentences that give instructions.**

| Rule | Write | Not |
|---|---|---|
| An instruction is an imperative. A fact is a plain statement. "Should be done" is neither. | "Run `stash export --since 2026-01-01`." | "The export should be run with a start date." |
| A sentence that has a condition or goal puts it first, so a reader it does not concern stops there. | "To export a single table, pass `--table`." | "Pass `--table` to export a single table." |
| A procedure never calls a step "simply", "easy", or "quickly"; the reader is here because it was not. It never says "please" either. | "Run the export." | "Simply kick off the export, please." |

**Sentences that describe.**

| Rule | Write | Not |
|---|---|---|
| The subject is whoever does the action. Use the passive only when that actor is unknown or does not matter. | "The scheduler retries a failed export." | "A failed export is retried." |
| Use "you" and present-tense verbs. "Will" is for events that do happen later. | "You get one archive per table." | "The user will get one archive per table." |
| The usual case comes before the exceptions. | The default run, then the `--table` run. | The edge cases, then the default. |

**Tone across the page.** Sound like a colleague who knows the tool well: no buzzwords and no
figures of speech. Say nothing about features that do not exist yet ("support for X is coming").
Consecutive sentences start differently, not "Stash exports. Stash compresses. Stash verifies."
When a sentence still sounds awkward read aloud, rewrite it.

## Load: how much one sentence carries

These are our house limits, selected from ASD-STE100 Simplified Technical English. The
specification settles anything this file does not cover. The record in [`sources.md`](sources.md)
holds the pointer and the recheck trigger.

Check from the largest unit down to the smallest. Each row is one check.

| Unit | Rule | Example |
|---|---|---|
| Paragraph | One topic, and no more than six sentences. Break a longer paragraph where its topic shifts. | A paragraph about export flags ends before the first sentence about restoring. |
| Sentence | An instruction sentence, warnings and cautions included, has a hard cap of 20 words: count them and split any sentence over it. Split other sentences once they pass about 25 words. | A 26-word step that names the flag, the date and the copy target becomes two steps. |
| Sentence | An instruction sentence asks for one action. Any other sentence makes one statement. | "Run the export and check the archive size" becomes two sentences, one per action. |
| Sentence | A warning or condition comes before the step it protects, so the reader reads it before acting. | "The purge deletes every archive. Copy the archives you need, then run `stash purge`." |
| Verb | Simple verb forms only. | "The archive has been written" becomes "the export wrote the archive"; "stash will be running" becomes "stash runs". |
| Verb | Each step of a procedure is a command to the reader: never a story about what the reader does, never passive. | "Create the archive folder", not "next, the user creates the archive folder" or "the archive folder must be created". |
| Verb | One verb per action, kept for the whole document. | Once a page says "export", it never calls the same action "dump". |
| Word | A word, once used, keeps its first sense and its grammatical role for the whole document. | If "load" means "read from disk", a sentence about system load needs a different word. |
| Word | Where a form other than an "-ing" word exists, use it. An "-ing" word can act as a noun, an adjective or a verb, so it invites a wrong parse. | "Exporting tables can be slow" can mean the act of exporting or tables that are being exported. |
| Word | Keep the articles. | "Export archive" can be an instruction or the name of an archive; "Export the archive" can only be an instruction. |

## Ambiguity: can this be read two ways?

Our paraphrased selection from Kohl, *The Global English Style Guide*. The readers these rules
protect are the reader whose first language is not English, the translator, and the agent; all
three read simple constructions most reliably.

Word placement and grouping:

- Put "only" and "not" directly beside the word they limit. "Stash only skips locked tables" and
  "stash skips only locked tables" are different claims.
- When "and" and "or" could group two ways, say how they group. "If ... then", "either ... or" and
  "both ... and" remove the doubt at no cost.
- Where dropping it could cause a misread, give each item of a series its own article: "the reader
  and the writer", not "the reader and writer", which can be one component with two roles.
- Never leave a verb implied. "The first pass copies the schema and the second the rows" gives the
  second pass no verb; write "the second pass copies the rows".
- Before deleting a "that" or a "to" to save a word, read the sentence without it. "Stash warns
  the archive is incomplete" first reads as stash warning the archive; "stash warns that the
  archive is incomplete" has one reading. The word stays: word count is never worth a second
  parse.

References and names:

- Each pronoun ("it", "this", "they") must refer to a single noun the reader can name. If it might
  not, repeat the noun. Never let "this" or "which" stand for a whole clause.
- Split long noun stacks: "the nightly table export retry limit setting" becomes "the setting that
  limits retries of the nightly table export".
- Give each thing one name and use it everywhere. A page that calls one file "the archive", "the
  bundle" and "the dump" makes the reader look for three files. Rewording a sentence the edit did
  not change has the same cost, so leave unchanged sentences as they are.

Punctuation and register:

- Text inside parentheses is either a complete grammatical unit or moved into its own sentence.
  Never write a plural as "(s)": "the archive(s)" becomes "one or more archives".
- No slashes between alternatives: "CSV/JSON" and "and/or" become "CSV, JSON, or both".
- Leave out idioms, colloquial phrases, metaphors and Latin abbreviations: "e.g." becomes "for
  example"; "works out of the box" becomes "works with no configuration".

### Two punctuation rules that a project may well disable

Kohl's guidelines add two punctuation rules: end a sentence with a period where a semicolon would
join two, and turn an em dash into a sentence break. Both are here because they are part of the
standard being paraphrased, and both are the first rules a project with a deliberate house style is
likely to overrule.

That is the intended outcome, not a defect. A project that uses em dashes on purpose disables this
pair the same way it disables any other rule, through its own declared style guide or its prose
linter's configuration, and the disabled rule stays visible as a decision rather than vanishing.
Do not apply either rule to a project that has ruled against it, and do not delete them for
projects that have not.
