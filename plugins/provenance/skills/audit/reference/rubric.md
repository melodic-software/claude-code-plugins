# The provenance rubric

Rubric version **1**. This catalog is versioned with the plugin: a change to a carve-out or a
criterion lands in `CHANGELOG.md` and **invalidates any golden-set measurement pinned to the
prior version**. A precision figure measured against rubric 1 says nothing about rubric 2.

Read this at the judgment step. Judges apply it blind, three samples by default; unanimity
renders the verdict and any split routes to the human.

## What this rubric is for, and what it is not

It decides one question: **does this passage carry drift risk that a pointer would remove?**
A passage restating a fact an external source owns goes stale the next time that source
changes, and nothing in the repository records that it did. That is the harm being measured.

It is **not a copyright or fair-use assessment**, and it must not be reported as one. Some
criterion names below resemble fair-use factors because both bodies of thought ask similar
questions about borrowed text, but the resemblance is where it ends: the verdicts here are
editorial, the remedies are maintenance remedies, and nothing in this catalog is legal advice or
a substitute for it. A finding says a passage should point at its source instead of restating
it. It never says a passage is unlawful.

## Order of evaluation

1. **Carve-outs first.** If any applies, the candidate is declined with that carve-out named,
   and no criterion is graded. Declines are counted, never dropped.
2. **Then the four criteria**, each graded PASS or FAIL with a quoted span.
3. **Verdict: STANDS only if all four PASS.** Any FAIL clears the candidate.
4. **Then the tier**, mapped from evidence by fixed rule — never from the verdict's confidence.

Carve-outs come first because several of them make the criteria meaningless rather than merely
satisfied. Grading "attribution adequacy" on a vendored upstream file asks whether a file that
is wholly and openly someone else's is adequately attributed, which is not a question.

## Carve-outs

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

A passage carrying all four parts — claim, basis URL, as-of date, recheck trigger — is already
the sanctioned fallback for a restatement that has to exist. It is not a copy to be found; it is
the end state a copy is converted into.

**Conforming is the whole test.** A dated sentence with no trigger is not carved out; it is a
`rule-trigger-less-stamp` candidate where the repository has enabled that check, and a plain
candidate where it has not. Do not extend this carve-out to "it has a date, close enough" — that
converts the carve-out into a way to launder any copy by adding a date to it.

### 3. Quotation contexts

Text that is presented as a quotation and attributed: a blockquote with its source named, an
inline quoted span with a citation, a fenced excerpt between provenance markers.

Mostly this is settled before judgment reaches you: the fingerprint module strips quoted spans —
blockquotes, code fences, and inline quotation marks, straight and curly — from the local text
before shingling, so a properly quoted excerpt never produces a matched span at all. The
carve-out exists for what the stripper cannot see, chiefly a quotation whose attribution sits a
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

### 6. The plugin's own eval-fixture tree

Golden-set fixtures are planted copies. Finding them is the harness working, not a defect.

**This carve-out is a config entry, never a rule in a script.** The consuming repo lists the
fixture tree in `excluded_paths`, so a normal run declines it and says so, while the eval
harness lifts the config layer and the fixtures report their real findings. An unconditional
exclusion would blind the harness to its own fixtures and leave the eval author reading prose
instead of results.

## The four criteria

Each is binary. Each requires **a quoted span from the material in front of you**. A grade
without a quote is not a grade; if the text you would need to quote is not in front of you,
grade UNKNOWN and say what you would need. UNKNOWN is not a FAIL and not a PASS — it stops the
verdict and routes to the human.

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
for an obvious fact — these recur because the subject constrains them, and flagging them would
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

**Does the attribution already present discharge the obligation?**

Adequate attribution answers three things for a reader who wants to check: *what* is being
attributed, *to where*, and *as of when* if the claim is time-bound. A bare link at the bottom of
a long file does not attribute a specific paragraph in the middle of it.

- **PASS (criterion fails, no finding), worked.** A blockquote followed by
  `— <source title>, <url>, read 2026-08-12`, adjacent to the quoted text.
- **FAIL (criterion holds, finding stands), worked.** Three paragraphs of restated behavior,
  with the source URL appearing once in a `See also` list two sections below. The reader cannot
  tell which sentences came from there, and neither can the next maintainer.

Grade what is on the page, not what a reasonable author probably intended. This criterion is
also the one most often used to argue a finding away; the quoted-span requirement is what keeps
that honest. Quote the attribution you are calling adequate.

### C4-transformative-use

**Does the local text do work the source does not?**

Selection, synthesis across sources, application to this repository's own context, worked
examples the source lacks — these make a passage this repository's own even where it began from
someone else's material. Reformatting does not: a table of the source's prose is the source's
content in a table.

- **PASS (criterion fails, no finding), worked.** A paragraph that takes three upstream
  parameters, explains which one this repository uses and why the other two are wrong here, and
  cites the page. The judgment is local and does not exist upstream.
- **FAIL (criterion holds, finding stands), worked.** The same three parameters, re-listed with
  their upstream descriptions lightly reworded, no local judgment added.

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
| `source-fetched-similar` | Source fetched, below the deterministic rule, unanimous STANDS | No, human report | No |
| `llm-suspected` | No lexical evidence is possible (paraphrase, summary) | No, human report | No |
| `not-found` | Budgets exhausted with no source; every searched surface named | No, human report | No |

Two consequences that judges get wrong if they are not stated:

- **A paraphrase can never be `fingerprint-confirmed`**, however confident the panel. There is no
  lexical evidence to gate on, and unanimity does not manufacture any. `paraphrase` and `summary`
  are permanently report-only classes.
- **`not-found` is a first-class outcome, not a failure and not an acquittal.** It says the run
  did not locate a source within its budget, naming every surface it checked. Absence of a
  located source is never evidence that a passage is original.

## Restated external rules, as four-part records

Each entry restates a rule this catalog does not own, because a judge applying the rubric offline
cannot follow a pointer. Each is source-pinned so the restatement can be re-derived.

**Prefer the pointer over the snapshot.** *Claim:* upstream bodies are read on demand; citing a
source and fetching it at read time is preferred over storing a snapshot of it, and a time-bound
external claim in durable content carries a recheck trigger. *Basis:*
`melodic-software/standards`, `conventions/engineering/documentation-and-citations.md`, as cited
by `docs/conventions/upstream-drift/README.md` "Boundary" in the marketplace repository. *As of:*
2026-08-28. *Recheck trigger:* any revision of that org standard, or of the upstream-drift
convention's Boundary section that cites it.

**A conforming record has four parts.** *Claim:* a record deriving a fact from a source this
repository does not own carries the claim, the basis (a specific URL or probe), the as-of date,
and the recheck trigger — the observable event that obliges re-derivation. A date alone does not
qualify as a trigger. *Basis:* `docs/conventions/upstream-drift/README.md` "Required parts" and
"The observability bar" in the marketplace repository. *As of:* 2026-08-28. *Recheck trigger:*
any change to that convention's required parts, or the org standard broadening the accepted
trigger forms in a way this repository adopts.

**A date is never authority.** *Claim:* a dated verification stamp records when a claim last
matched its source and confers no standing authority; a stale stamp reads identically to a fresh
one, so the trigger is the load-bearing part, not the date. *Basis:*
`docs/conventions/upstream-drift/README.md` "A date is never authority" in the marketplace
repository. *As of:* 2026-08-28. *Recheck trigger:* any change to that section.
