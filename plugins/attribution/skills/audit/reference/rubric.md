# The attribution rubrics

Two rubrics live here, each versioned on its own: the **copy rubric**, version **5**, and the
**restated-fact rubric**, version **1**. This catalog is versioned with the plugin: a change to a
carve-out or a criterion of either rubric lands in `CHANGELOG.md` and **invalidates any golden-set
measurement pinned to an earlier version of that rubric**. **The golden set must be re-scored
against the current version before any precision figure is cited against it**, and no class
becomes fix-eligible on a measurement pinned to a superseded rubric.

Read this at the judgment step. **Each judge dispatch names the one rubric it applies, `copy` or
`restated-fact`, and the judge applies that rubric alone.** A dispatch that names none applies the
copy rubric. The other rubric's section is context; its criteria are never graded. Judges apply
the rubric blind; unanimity renders the verdict and any split routes to the human.

## What these rubrics are for, and what they are not

Both decide one question: **does this passage carry drift risk that a pointer would remove?** A
passage restating a fact an external source owns goes stale the next time that source changes, and
nothing in the repository records that it did. That is the harm being measured. The copy rubric
reads a passage whose text corresponds to a source's text. The restated-fact rubric reads a fact a
passage carries, in any wording, that an external source owns.

Neither is a **copyright or fair-use assessment**, and neither may be reported as one. Some
criterion names below resemble fair-use factors because both bodies of thought ask similar
questions about borrowed text, but the resemblance is where it ends: the verdicts here are
editorial, the remedies are maintenance remedies, and nothing in this catalog is legal advice or
a substitute for it. A finding says a passage should point at its source instead of restating
it. It never says a passage is unlawful.

## Copy rubric: order of evaluation

1. **Carve-outs first.** If any applies, the candidate is declined with that carve-out named,
   and no criterion is graded. Declines are counted, never dropped.
2. **Then the four criteria**, each graded PASS or FAIL with a quoted span.
3. **Verdict: STANDS only if all four PASS.** Any FAIL clears the candidate.
4. **Then the tier**, mapped from evidence by fixed rule, never from the verdict's confidence.

Carve-outs come first because several of them make the criteria meaningless rather than merely
satisfied. Grading "attribution adequacy" on a vendored upstream file asks whether a file that
is wholly and openly someone else's is adequately attributed, which is not a question.

## Copy rubric: carve-outs

Every carve-out here is **categorical**: it names a class of surface, never an individual
passage someone wanted kept. Per-instance keeps are the finding-suppression concern and belong
to the operator, not to this rubric. If the sweep starts accumulating per-instance exceptions,
that is evidence a carve-out is drawn wrongly, and the fix is to redraw it here.

Definitions are carried inline rather than by pointer, because this plugin ships to consumers
who do not have the marketplace repository; the owning convention is cited for provenance.

### 1. Vendored trees

A tree that exists to hold a verbatim upstream copy, and says so. Path-expressible: `**/vendor/**`
and anything marked `linguist-vendored`, both filtered by `list-corpus.sh` before a byte is read.

The copy is the artifact. Replacing it with a pointer destroys the thing it exists to be, and
drift is handled by its sync path, not by this audit.

### 2. Conforming stamped records

A passage carrying a whole stamped record, a pointer to the source, an as-of date, and a recheck
trigger beside the decision it records, is already the sanctioned end state a copy is converted
into. It is not a copy to be found. Text inside the record that matches the source is still judged
like any other passage.

**Conforming is the whole test.** A dated sentence with no trigger is not carved out; it is a
`rule-trigger-less-stamp` candidate where the repository has enabled that check, and a plain
candidate where it has not. Do not extend this carve-out to "it has a date, close enough". That
converts the carve-out into a way to launder any copy by adding a date to it.

### 3. Quotation contexts

Text that is presented as a quotation and attributed: a blockquote with its source named, an
inline quoted span with a citation, a fenced excerpt between provenance markers.

Mostly this is settled before judgment reaches you. The fingerprint module strips quoted spans
from the local text before shingling, meaning blockquotes, code fences, and inline quotation
marks both straight and curly, so a properly quoted excerpt never produces a matched span at
all. The carve-out exists for what the stripper cannot see, chiefly a quotation whose attribution sits a
line or two away rather than inside the quoted span.

### 4. Owned content

Content this repository wrote, about its own subject matter, that happens to resemble an
external page. Convergent wording is not provenance: two people documenting the same API in the
same house style will land on similar sentences without either having read the other.

The discriminator is direction, and it is the question a judge should actually ask: **could this
passage have been written without the source in hand?** A passage stating what this repository
does, in this repository's vocabulary, is owned even where the phrasing echoes upstream. A
passage stating what an external product does, carrying specifics no one here would know
first-hand, is not owned no matter how it is phrased.

This is the in-flight discipline's own boundary, cited for provenance: `discipline:point-dont-copy`
in the marketplace repository owns "do not copy while writing"; this carve-out is its read at
audit time.

**Same-organization sibling repositories are not owned here.** A passage that restates what another
repository in the same org documents, even when the same people maintain both, is **external** for
this audit: each repository drifts on its own schedule, and the "could this have been written
without the source in hand?" test is not enough to treat a sibling README as first-party. Judge it
like any other upstream restatement (pointer, quote, or stamped record), or close it only when a
breadcrumb or nomination already names the sibling repo as the source.

Sibling-org repos are external at audit time unless the passage cites that sibling as its source.
**Pointer:** none; this is `judgment`, and no audited pass or upstream source shows the carve-out
behavior yet. **As of:** 2026-09-28. **Recheck trigger:** a consumer policy file declares same-org
siblings owned, or a golden case is added that turns on this boundary.

### 5. Distilled-product architectures

Surfaces whose entire product is a distillation of external material, where the distillation is
the deliverable and the external source is credited as the subject: a playbook pack that
distills a model's documented behavior, a knowledge-tier memory file that exists to hold what a
book or course said.

The carve-out is narrow and it is about the surface's purpose, not its density. A file that
distills a source **as its stated job**, and names that source, is doing what it exists to do. A
file that distills a source **incidentally**, in the middle of doing something else, is a
candidate like any other. If you cannot say what the surface's distillation product is, this
carve-out does not apply.

**The carve-out covers the file's distillation product. It does not cover a verbatim or
near-verbatim span the file's own attribution does not enumerate.** Where a distilling file says
which of its spans are lifted, whether through a Sources section listing the quoted sentences, a
marked block, or an inline citation on the span itself, a lift that appears on none of those
lists is a candidate, and the file's distilling purpose does not reach it. Reformatting is not
distillation: un-fencing a source's prompt block into running prose, or turning its prose into a
table, is that source's content in a different shape, which C4 already says is not transformative.

Grade this the way the surface asks to be graded. A file that never enumerates its lifts is
judged on purpose alone, as above. A file that does enumerate them has told you where its own
boundary is, and a span outside that boundary is outside the carve-out. This is the test a judge
can actually apply to a span; "the file distills something and credits a source" is satisfiable by
almost any reference file that carries a link, which is why it was not enough on its own.

### 6. The plugin's own eval-fixture tree

Golden-set fixtures are planted copies. Finding them is the harness working, not a defect.

**This carve-out is a config entry, never a rule in a script.** The consuming repo lists the
fixture tree in `excluded_paths`, so a normal run declines it and says so, while the eval
harness lifts the config layer and the fixtures report their real findings. An unconditional
exclusion would blind the harness to its own fixtures and leave the eval author reading prose
instead of results.

## Copy rubric: the four criteria

Each is binary. Each requires **a quoted span from the material in front of you**. A grade
without a quote is not a grade; if the text you would need to quote is not in front of you,
grade UNKNOWN and say what you would need. UNKNOWN is not a FAIL and not a PASS. It stops the
verdict and routes to the human.

**Polarity, stated once because it is easy to invert: PASS always means the criterion SUPPORTS
the finding.** All four criteria point the same way, so all four PASS is what makes a verdict
STAND. A criterion that clears the candidate is a FAIL. This reads backwards for C3 and C4,
where the exculpatory answer is the intuitive "yes", adequately attributed and genuinely
transformative, so both are phrased below in the negative to keep the direction uniform. A
rubric whose criteria disagree about which way PASS points cannot render a verdict at all: under
the inverse reading nothing could ever stand.

**Scope, stated once because C3 and C4 are graded at different ones.** C1 and C2 are graded on
the passage; nothing else would mean anything. The other two are not symmetric:

- **C3 is graded outward from the passage, across the whole file.** This file already grades it
  that way in its own worked examples: the PASS example turns on a URL "two sections below" the
  restated text, and the FAIL example on a source line adjacent to a blockquote. Neither is
  inside the span. What C3 asks is whether the attribution's declared **scope matches the
  derivation's**. File-scope attribution discharges C3 when the derivation is file-wide; it does
  not when one lift sits inside otherwise-original material, because there the header understates
  and the reader misallocates which sentences came from upstream. "The attribution exists and is
  complete" is not the test. That reading lets a single lift into an original file escape on a
  header line about something else.
- **C4 is graded on the passage**, which is what its worked examples below already do, and what
  its closing replacement test asks. A file can be substantially transformed while the span in
  question adds nothing over its source, and it is the span that was copied.

The asymmetry is the point, and it cuts both ways. Grade both at the file, and a majority-adapted
file **that carries adequate file-level attribution** clears twice. The qualifier matters, since
a file with no attribution anywhere still fails C3 at either scope. Grade both at the span, and a
well-attributed derived file stands every time.

### C1-span-correspondence

**Does a specific span of the local text correspond to a specific span of the named source?**

PASS requires you to be able to point at both: this local sentence, that source sentence.
"The whole page is about the same topic" is not correspondence. Topic overlap is what you would
expect between two documents about one subject; span correspondence is what you would not.

- **PASS, worked.** Local: `The runner accepts three retry values: none, linear, and exponential.`
  Source: `retry accepts one of three values — none, linear, exponential.` Different wording,
  same enumerated content in the same order, and the enumeration is the source's to define.
- **FAIL, worked.** Local: `Retries are configurable.` Source: a page documenting a retry
  parameter. True, related, and corresponding to nothing specific. A pointer would not preserve
  a claim this general because the claim is not carrying anything from the source.

Note what C1 does **not** ask: how the correspondence arose. A local passage that corresponds
because both authors read the same spec still corresponds; that is C4's and carve-out 4's
question, not this one.

### C2-beyond-common-idiom

**Is the corresponding text beyond what any competent writer would produce independently?**

Shared technical vocabulary is not a copy. Field names, standard phrasings, the obvious sentence
for an obvious fact: these recur because the subject constrains them, and flagging them would
bury real findings under noise.

- **PASS, worked.** A 27-word span reproducing an unusual ordering of caveats, including a
  parenthetical aside the source's author chose. The specific structure had alternatives and this
  text took the source's.
- **FAIL, worked.** `Set the token in the environment variable before running the command.` There
  is no meaningfully different way to write this sentence.

The deterministic separation rule is the mechanical floor under C2, not a replacement for it:
matched spans are measured after quote-stripping, and the rule fires on containment at or above
its threshold **or** a matched span at or above its word floor. A span below the rule can still
FAIL C2 on judgment; a span above it can still FAIL C2 if the matched words are boilerplate. The
numbers bound the evidence; they do not render the verdict.

### C3-attribution-adequacy

**Is the attribution already present INADEQUATE to discharge the obligation?**

Adequate attribution answers three things for a reader who wants to check: *what* is being
attributed, *to where*, and *as of when* if the claim is time-bound. A bare link at the bottom of
a long file does not attribute a specific paragraph in the middle of it. So adequate attribution
FAILS this criterion and clears the candidate; inadequate attribution PASSES it.

- **PASS, worked.** Three paragraphs of restated behavior, with the source URL appearing once in
  a `See also` list two sections below. The reader cannot tell which sentences came from there,
  and neither can the next maintainer.
- **FAIL, worked.** A blockquote followed by `— <source title>, <url>, read 2026-08-12`, adjacent
  to the quoted text.

Grade what is on the page, not what a reasonable author probably intended. This criterion is
also the one most often used to argue a finding away; the quoted-span requirement is what keeps
that honest. Quote the attribution you are grading, whichever way you grade it.

### C4-transformative-use

**Is the use NON-transformative, meaning the local text adds nothing the source does not carry?**

Selection, synthesis across sources, application to this repository's own context, worked
examples the source lacks: these make a passage this repository's own even where it began from
someone else's material, and they FAIL this criterion, clearing the candidate. Reformatting is
not transformation: a table of the source's prose is the source's content in a table, and it
PASSES.

- **PASS, worked.** Three upstream parameters re-listed with their upstream descriptions lightly
  reworded, no local judgment added.
- **FAIL, worked.** A paragraph that takes those same three parameters, explains which one this
  repository uses and why the other two are wrong here, and cites the page. The judgment is local
  and does not exist upstream.

The honest failure mode here is generosity. Almost any restatement feels a little transformative
to the person reading it. Ask instead: **if this passage were replaced by a link, what could a
reader no longer learn?** If the answer is "nothing that is not on the other side of the link",
C4 holds and the finding stands.

## Tier mapping

The tier is mapped from evidence by fixed rule. **A run never invents or reassigns a tier from
prose**, and a unanimous panel does not upgrade one.

| Tier | Evidence gate | Reaches relay | Fix-eligible |
|---|---|---|---|
| `fingerprint-confirmed` | A matched span above the separation rule, against an identity-checked fetched source | Yes | Yes |
| `vendored-snapshot` | The source was read from a committed snapshot because the live fetch was unavailable or failed; the finding records `source.route: vendored-snapshot` and names the snapshot path, its declared upstream ref and its sync date; a paraphrase or summary stays `llm-suspected` | No, human report | No |
| `source-fetched-similar` | Source fetched, below the deterministic rule, unanimous STANDS | No, human report | No |
| `llm-suspected` | No lexical evidence is possible (paraphrase, summary) | No, human report | No |
| `not-found` | Budgets exhausted with no source; every searched surface named | No, human report | No |

The relay column is the copy class's. A restated-fact finding maps to a row above by the same fixed
rule and relays by a rule of its own, on the panel's unanimity and the refutation pass, whatever the
row says; it is never fix-eligible.

Two consequences that judges get wrong if they are not stated:

- **A paraphrase can never be `fingerprint-confirmed`**, however confident the panel. There is no
  lexical evidence to gate on, and unanimity does not manufacture any. `paraphrase` and `summary`
  are permanently report-only classes.
- **`not-found` is a first-class outcome, not a failure and not an acquittal.** It says the run
  did not locate a source within its budget, naming every surface it checked. Absence of a
  located source is never evidence that a passage is original.

## Restated-fact rubric

Apply this section only when the dispatch names `restated-fact`. It decides whether a passage
**restates a fact an external source owns**, in any wording, without conforming to the
upstream-drift shape: a pointer at the point of use, or a whole stamped record (pointer, as-of
date, observable recheck trigger). It never asks whether the passage's words correspond to
a source's words: a paraphrase, a summary, or a table restates a fact as fully as a copied
sentence does.

The facts in scope are the ones an external owner can change without touching this repository: a
constant, a default, a version pin, a field list, the semantics of a named external product.

### Restated-fact order of evaluation

1. **Carve-outs first.** A carve-out declines the candidate, names itself, and grades no
   criterion. Declines are counted, never dropped.
2. **Then the four criteria**, each graded PASS, FAIL or UNKNOWN with a quoted span. Polarity is
   the copy rubric's: PASS always supports the finding, FAIL clears the candidate, UNKNOWN stops
   the verdict and routes to the human.
3. **Verdict: STANDS only if all four PASS.**
4. **Then the tier**, by the rule under "Restated-fact verdict and tier".

Vendored trees and the plugin's own eval-fixture tree (copy carve-outs 1 and 6) are settled by
corpus scoping before either rubric runs.

### Restated-fact carve-outs

Categorical, as for the copy rubric: each names a class of surface, never a passage someone
wanted kept.

1. **Conforming pointer or record.** The passage names the source in place of stating the fact,
   or carries every part of a conforming record (see "A conforming record's parts" below).
   Conforming is the whole test. A link beside a stated value cites the value and does not
   record when it was checked or what obliges a recheck, and a dated sentence with no observable
   trigger is missing a part; neither is carved out.
2. **Owned content.** Facts this repository owns, in its own vocabulary. The direction test and
   the same-organization sibling rule are copy carve-out 4's.
3. **Distilling-file surface whose own attribution enumerates the fact.** A surface whose stated
   product is a distillation of a named external source, and whose own attribution (a Sources
   section, per-section source tags, an inline citation on the span) accounts for this fact.
   Quote that line; if you cannot, the carve-out does not apply. A fact the attribution does not
   enumerate is a candidate, and the surface's purpose does not reach it. A file that distills a
   source incidentally, while doing another job, is not carved out.
4. **Quoted and cited text.** A fact inside a quotation whose source is named at the span, as in
   copy carve-out 3.

### Restated-fact criteria

Each is binary and needs a quoted span from the material in front of you; where the text to quote
is absent, grade UNKNOWN and say what you would need. R1 to R3 are graded on the passage. R4 is
graded outward across the containing file, because whether a record is whole and covers the fact
cannot be read from the passage alone.

**R1-external-owner.** *Does the passage assert a fact an external source owns?* Quote the fact
and name its owner, from what the passage or file says or from the fact itself (a named product's
own flag, field or limit). A fact that is general practice, which no source decides, FAILS. A fact
that plainly has an external owner the material does not let you name is UNKNOWN.

- **PASS, worked.** `The client library retries three times by default.` The library's
  documentation owns the default.
- **FAIL, worked.** `Retries should back off between attempts.` General practice; no source
  decides it.

**R2-specific-and-revisable.** *Is the fact a concrete value, enumeration, or behavior its owner
can change without notice?*

- **PASS, worked.** `A request carries at most 32 items and the fields id, name, and tags.` A cap
  and a field list.
- **FAIL, worked.** `The service exposes an HTTP API.` True across every revision; a pointer would
  preserve nothing.

**R3-stated-as-current.** *Is the fact asserted as how the external thing works now, for a reader
to act on?*

- **PASS, worked.** `Keep runs under 60 seconds; the platform terminates longer ones.`
- **FAIL, worked.** `Release 2.3 raised the cap from 16 to 32 items.` History states what was
  true at a named point and is not a claim about now, and neither is an example the text labels
  illustrative.

**R4-no-conforming-shape.** *Is the fact stated without a whole record (pointer, as-of date,
observable recheck trigger)?* A record elsewhere in the file covers the fact only where it names
the fact's topic. A whole record FAILS this
criterion and clears the candidate. Quote the nearest citation or stamp and name the part it
lacks; where there is none, say so.

- **PASS, worked.** `The default is 30 seconds ([docs](<url>)).` A basis, with no as-of date and
  no trigger.
- **FAIL, worked.** `The default is 30 seconds. Verified <date> against <url>; recheck when the
  vendor changelog lists a change to the timeout.` A pointer, a date, and a trigger that is an
  event a reader can check.

### Restated-fact verdict and tier

**A restated-fact STANDS never carries `fingerprint-confirmed`, whatever the fingerprint module
reported, so it is never fix-eligible.** That tier needs the copy rubric's evidence: a matched
span above the separation rule. This rubric judges drift risk in any wording and yields no
lexical evidence, and unanimity does not manufacture any. A fetched source caps the verdict at
`source-fetched-similar` whatever the fingerprint showed. Every other tier is mapped from evidence
by the table above, by fixed rule, never from a judge's confidence.

## Org rules this rubric applies, as stamped records

Each entry is how this rubric applies a rule it does not own, stated here because a judge applying
the rubric offline cannot follow a pointer. Each is pinned so it can be re-derived.

**Prefer the pointer over the snapshot.** This rubric treats a pointer read on demand as the end
state and a stored snapshot as a candidate, and expects a time-bound external claim in durable
content to carry a recheck trigger. *Pointer:* `melodic-software/standards`,
`conventions/engineering/documentation-and-citations.md`, as cited by
`docs/conventions/upstream-drift/README.md` "Boundary" in the marketplace repository. *As of:*
2026-10-01. *Recheck trigger:* any revision of that org standard, or of the upstream-drift
convention's Boundary section that cites it.

**A conforming record's parts.** This rubric treats a record as conforming when it carries a
pointer to the source (a specific URL or probe), an as-of date, and a recheck trigger, the
observable event that obliges re-derivation, beside the decision it records. A date alone does not
qualify as a trigger. *Pointer:* `docs/conventions/upstream-drift/README.md` "Required parts" and
"The observability bar" in the marketplace repository. *As of:* 2026-10-01. *Recheck trigger:* any
change to that convention's required parts, or the org standard broadening the accepted trigger
forms in a way this repository adopts.

**A date is never authority.** This rubric reads a dated stamp as the last time the record was
derived from its source, never as standing authority: what obliges re-derivation is the trigger,
not the date. *Pointer:* `docs/conventions/upstream-drift/README.md` "A date is never authority" in
the marketplace repository. *As of:* 2026-10-01. *Recheck trigger:* any change to that section.
