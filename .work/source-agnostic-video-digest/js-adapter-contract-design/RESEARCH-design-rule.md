---
topic: js-adapter-contract-design
section: design-rule
abstract: "The WHAT-not-HOW rule holds directionally but is too strong; the defensible line is that a contract may constrain host-owned protocol, never adapter-owned acquisition technology, and the failure mode's citable name is Parnas 1972, not 'leaky abstraction'."
claims:
  - claim: "Cockburn's stated port rule is to never explicitly name any external object or technology, and always take a parameter for one you need — the second clause is what licenses host-capability injection."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://alistaircockburn.com/hexarch"
        tier: 1
        pool: "Cockburn (primary author)"
      - url: "https://jmgarridopaz.github.io/content/hexagonalarchitecture.html"
        tier: 1
        pool: "Garrido de Paz (book co-author)"
  - claim: "yt-dlp's InfoExtractor docstring devotes ~87% (414 of 474 lines) to specifying the OUTPUT info dict and ~10% to subclass obligations, with exactly one required method (_real_extract); acquisition helpers are base-class conveniences, absent from the required surface."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/common.py"
        tier: 1
        pool: "yt-dlp"
  - claim: "Parnas 1972 names this exact defect: giving more information than necessary 'unnecessarily restricted the class of systems that we can build', which he classes as a design error."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://cw.fel.cvut.cz/old/_media/courses/a4m33sep/materialy/architecture_and_design/01-article_original_de_parnas.pdf"
        tier: 1
        pool: "Parnas / CACM (primary paper)"
  - claim: "'Leaky abstraction' is the WRONG name for this failure — Spolsky's law describes runtime leakage of underlying complexity in failure modes, not an interface signature naming its implementation's technology."
    confidence: HIGH
    tiers: [1, 2]
    sources:
      - url: "https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/"
        tier: 1
        pool: "Spolsky (primary author)"
      - url: "https://en.wikipedia.org/wiki/Leaky_abstraction"
        tier: 2
        pool: "Wikipedia"
  - claim: "The precedent contract is MIXED, not uniformly leaked: deriveLandingUrl and buildLessonUrl are already technology-neutral, so three signatures need re-deriving, not five."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "plugins/knowledge/skills/course-digest/extraction/adapters/adapter-contract.js"
        tier: 0
        pool: "first-party (this repository, Read-verified)"
produced_by: lane-e
---

# (e) Does "the contract prescribes WHAT, not HOW" hold up — and what is the recognized failure mode when a contract leaks the incumbent implementation's shape?

Research pass for the source-adapter contract design. Every claim carries an inline citation and a
confidence marker.

## Confidence markers used

Two orthogonal axes, both preserved:

- **VERIFIED / UNVERIFIED / REFUTED** — whether the claim is supported by a source I reached.
- **`[EXACT]` / `[SUBSTANCE]`** — quote fidelity. `[EXACT]` = extracted byte-for-byte from primary
  text (raw HTML/PDF/source file fetched and de-tagged locally). `[SUBSTANCE]` = wording arrived via
  a summarizing extractor; the substance is verified but the wording is **not** guaranteed verbatim.
  This distinction is not decorative: two fetches of the same Spolsky URL returned two different
  wordings of the same sentence, so at least one was not verbatim.

---

## 0. The concrete case, restated precisely

The task brief states the contract's five required methods "all have signatures taking a Playwright
browser `page` object," then lists two that do not:

| Method | Inputs | Shape |
| --- | --- | --- |
| `extractTranscript(page, platformCfg)` | Playwright `Page` | leaks incumbent technology |
| `extractHlsUrl(page, platformCfg)` | Playwright `Page` | leaks incumbent technology |
| (third `page`-taking method, unnamed in brief) | Playwright `Page` | leaks incumbent technology |
| `deriveLandingUrl(courseUrl, cfg)` | URL string + config | **already correctly shaped** |
| `buildLessonUrl(course, lesson, cfg)` | domain objects + config | **already correctly shaped** |

**This is a MIXED contract, not a uniformly broken one, and that matters analytically.** The leak is
localized to the *acquisition* methods. The two URL-deriving methods take only inputs the pipeline
itself owns and are already source-agnostic — they are the existence proof that the same author
*could* write technology-neutral signatures where the incumbent implementation did not push a handle
into them. The diagnosis is therefore **per-method**, not per-contract, which is exactly the
granularity Ousterhout's §6.5 question 2 operates at (§2.3 below).

The header comment's claim ("prescribes WHAT adapters produce, not HOW they produce it") is
self-refuting **for the `page`-taking subset only**. Precision here is worth keeping: the fix is to
re-derive three signatures, not to discard five.

---

## 1. Alistair Cockburn — Hexagonal Architecture (Ports & Adapters)

### 1.1 Primary source: the 2005 paper

Source: <https://alistair.cockburn.us/hexagonal-architecture/> — "The Hexagonal (Ports & Adapters)
Architecture", HaT Technical Report 2005.02, dated 2005-09-04, v0.9. Fetched raw and de-tagged
locally; all quotes in this subsection are `[EXACT]`.

**How a port is defined — by the application's purpose, not the technology on the other side.**
VERIFIED `[EXACT]`:

> "The word 'port' is supposed to evoke thoughts of ports in an operating system, where any device
> that adheres to the protocols of a port can be plugged into it; and ports on electronics gadgets,
> where again, any device that fits the mechanical and electrical protocols can be plugged in. **The
> protocol for a port is given by the purpose of the conversation between the two devices.** The
> protocol takes the form of an application program interface (API)."

VERIFIED `[EXACT]`:

> "The term 'port and adapters' picks up the purposes of the parts of the drawing. **A port
> identifies a purposeful conversation. There will typically be multiple adapters for any one port,
> for various technologies that may plug into that port.** Typically, these might include a phone
> answering machine, a human voice, a touch-tone phone, a graphical human interface, a test harness,
> a batch driver, an http interface, a direct program-to-program interface, a mock (in-memory)
> database, a real database (perhaps different databases for development, test, and real use)."

The database example is the direct analogue of our case. VERIFIED `[EXACT]`:

> "From the application's perspective, if the database is moved from a SQL database to a flat file or
> any other kind of database, **the conversation across the API should not change.**"

Substituting our terms: from the pipeline's perspective, if the source moves from a browser-scraped
platform to a CLI tool, the conversation across the adapter contract should not change. It currently
cannot survive that move at all.

**The spec is written against the inner boundary, not against any one external technology.**
VERIFIED `[EXACT]`:

> "The functional specification of the application, perhaps in use cases, is made against the inner
> hexagon's interface and not against any one of the external technologies that might be used."

**Cockburn's own worked example of exactly our failure — the "Known Uses" weather system.** This is
the strongest passage in the 2005 paper for our purpose, because it describes a real system that had
already made our mistake and what fixing it consisted of. VERIFIED `[EXACT]`:

> "At the time we discussed this system, **the system's interfaces were identified and discussed by
> technology, linked to purpose.** There was an interface for trigger-data arriving over a wire
> feed, one for notification data to be sent to answering machines, an administrative interface
> implemented in a GUI, and a database interface to get their subscriber data.
>
> The people were struggling because they needed to add an http interface from the weather service,
> an email interface to their subscribers… **They feared they were staring at a maintenance and
> testing nightmare as they had to implement, test and maintain separate versions for all
> combinations and permutations.**
>
> **Their shift in design was to architect the system's interfaces by purpose rather than by
> technology, and to have the technologies be substitutable (on all sides) by adapters.** They
> immediately picked up the ability to include the http feed and the email notification."

That is our situation with the names changed: an interface set organized by the incumbent
technology, a second source arriving, and the remedy being re-derivation by purpose.

**A related "common mistake" Cockburn does name.** VERIFIED `[EXACT]`, from "Use Cases And The
Application Boundary":

> "**A common mistake is to write use cases to contain intimate knowledge of the technology sitting
> outside each port.** These use cases have earned a justifiably bad name in the industry for being
> long, hard-to-read, boring, brittle, and expensive to maintain."

This is about use cases rather than port signatures, so it is an analogue, not the same claim. Marked
as such.

**The inside/outside rule.** VERIFIED `[EXACT]`:

> "Both the user-side and the server-side problems actually are caused by the same error in design
> and programming — **the entanglement between the business logic and the interaction with external
> entities.**… **The rule to obey is that code pertaining to the inside part should not leak into the
> outside part.**"

Honest note: the rule as literally stated runs inside→outside, while our defect runs outside→inside
(the adapter's technology entering the contract). The *diagnosis* Cockburn gives for both — the
"entanglement between the business logic and the interaction with external entities" — is symmetric,
and the paper's whole framing is the inside/outside asymmetry. But do not cite the "should not leak"
sentence as if its stated direction is ours.

### 1.2 The 2024/2025 book — the sharpest statement, and the closest thing to a name

Source: *Hexagonal Architecture Explained*, Alistair Cockburn & Juan Manuel Garrido de Paz, Humans
and Technology Press, ISBN 979-8-9985862-0-0 (paperback) / 979-8-9985862-1-7 (ePub). I could not
reach the full book. Cockburn publishes the **v1.1b update pages** free as a PDF, and they contain
the load-bearing passages:
<https://alistaircockburn.com/hexarch%20v1.1b%20DIFFS%2020250420-1012%20paper+epub.docx.pdf>
(fetched and text-extracted locally; quotes `[EXACT]`). Chapter numbers below are as printed in
those update pages; the underlying book is 194 pages.

**The rule, stated as the pattern's central requirement.** VERIFIED `[EXACT]`, §1.1 "Copy this
code", book p. 10:

> "The most surprising part of implementing it is this requirement:
>
> **"Never explicitly name any external object or technology. Always take a parameter for any
> external object or technology you wish to access.""**

Both sentences matter. Sentence one condemns `extractTranscript(page, …)` outright. **Sentence two is
the permission clause** — it is what licenses passing a capability in at all, and it is the hinge for
the "limits" question in §7.2 below. The pattern does not forbid parameters; it forbids parameters
that *name a technology*.

**Weak vs. strong conformance — Cockburn's own name for a contract that leaked its adapter's
technology.** VERIFIED `[EXACT]`. The book carries this twice; the second occurrence is under a
literal section heading:

> **"Weak versus strong conformance to the pattern"** (book p. 27)
>
> "You can implement this pattern in a **legal but weak way**. Suppose you know that the database
> will use SQL. Without tying to a particular database, you still express the driven port in SQL.
> **While technically meeting the rules of the architecture, that still ties your system to SQL,
> which is not what we are after.**
>
> To get a proper, or strong implementation of the Ports & Adapters architecture, **the app cannot
> know anything about the external technology.**
>
> That is, the driven port is expressed purely in terms of concepts that make sense in the
> application language. **It can't even know that there a database, let alone an SQL one.**"

(The p. 10 variant reads "…handcuffs the system to SQL" and "…the Service Provider Interface (SPI)
or 'driven port' is expressed purely in terms of concepts that make sense in the language of the
domain." `[EXACT]`. The `there a database` typo is in the original.)

**Applying it:** our contract is *worse than weak conformance*. Cockburn's weak case is "legal but
weak" — SQL-flavoured but still implementable by any SQL store. Ours is **not legal at all**: a
`Page`-typed parameter cannot be satisfied by an adapter with no browser, so the second adapter
cannot be written. The contract is unsatisfiable, not merely over-committed.

**Is there a specific coined term for a port that leaked its adapter's technology?** **REFUTED — no
coined term found.** I searched the 2005 paper, the v1.1b update pages, and Garrido de Paz's
canonical article. There is no "leaky port", no named anti-pattern entry. The closest named things
are Cockburn's section heading **"Weak versus strong conformance to the pattern"** and the 2005
paper's descriptive **"interfaces… identified and discussed by technology"** vs. "by purpose". Both
are usable in review; neither is a term of art.

### 1.3 Garrido de Paz — the naming rule and the two-adapter discipline

Source: Juan Manuel Garrido de Paz, "Ports and Adapters Pattern (Hexagonal Architecture)", published
2018-08-29, <https://jmgarridopaz.github.io/content/hexagonalarchitecture.html>. Fetched raw and
de-tagged locally; quotes `[EXACT]`. Authority note: Cockburn's own book dedication calls him "the
world's other leading authority on the Ports & Adapters pattern," and he is the book's co-author, so
this page is co-author primary material rather than blog commentary.

**The port-naming rule, §2.3 "PORTS".** VERIFIED `[EXACT]`:

> "The interactions between actors and the application are organized at the hexagon boundary by the
> reason why they are interacting with the application. **Each group of interactions with a given
> purpose/intention is a port.**
>
> **Ports should be named according to what they are for, not according to any technology.** So, in
> order to name a port, we should use a verb ending with 'ing' and we should say 'this port is for
> …ing something'. For example:
>
> This driver port is for 'adding products to the shopping cart'.
> This driven port (repository) is 'for obtaining information about orders'.
> This driven port (recipient) is for 'sending notifications'."

VERIFIED `[EXACT]`, same section:

> "Ports are interfaces that the application offers to the outside world for allowing actors interact
> with the application. So the application should follow the **Information Hiding Principle**. An
> important thing to remark is that **ports belong to the application**."

Two things land here. First, the "for …ing something" test is directly runnable on our contract: a
port *for obtaining a transcript* is legitimate; a port *for running a Playwright page* is not.
Second, "ports belong to the application" is the ports-and-adapters form of the client-owns-the-
interface claim (§5.3) — and note that Cockburn's book confirms this structurally too, with its
interface names `ForCalculatingTaxes` / `ForGettingTaxRates` `[EXACT]`, and the guidance that port
folders be named `for_calculating_taxes` / `for_admin_purposes` `[EXACT]`.

**The two-adapter discipline, §2.4 "ADAPTERS".** VERIFIED `[EXACT]`:

> "**For each driver port, there should be at least two adapters:** one for the real driver that is
> going to run it, and another one for testing the behaviour of the port."
>
> "**For each driven port we should write at least two adapters:** one for the real world device, and
> another one a mock that mimics the real behavior."

**On "you cannot know a port is right until a second adapter exists".** **The strong epistemic claim
is UNVERIFIED — it is not in any source I reached.** What the sources actually support is weaker and
still sufficient:

- Garrido de Paz prescribes **≥2 adapters per port, one of them a test/mock adapter**, as a *design
  rule* (quoted above). VERIFIED `[EXACT]`.
- Cockburn's Figure 3 staging is mock-first: "1. With a FIT test harness driving the application and
  using the mock (in-memory) database substituting for the real database; 2. Adding a GUI…"
  VERIFIED `[EXACT]`. The second adapter is built *before* the real one, not after.
- Cockburn: "**The ultimate benefit of a ports and adapters implementation is the ability to run the
  application in a fully isolated mode.**" VERIFIED `[EXACT]`.

**My inference, labelled as mine, not theirs:** if the discipline mandates a second (test) adapter
from the outset, then a port that has only ever had one adapter has never been *exercised* against
the rule, and its correctness is untested rather than established. That is a defensible reading of
the two-adapter rule, but neither author states the epistemic form. Do not attribute it to them.

**Empirical test to adopt from this:** the two-adapter rule is the cheapest available check on any
proposed replacement signature. A signature that a trivial in-memory/fixture adapter cannot satisfy
has failed before the second real source is even written.

---

## 2. John Ousterhout — *A Philosophy of Software Design*, 2nd ed. (2021, Yaknyam Press)

**Sourcing caveat, load-bearing.** I could not reach a publisher-channel 2e text. Evidence comes from
(a) `github.com/yingang/aposd2e-zh` (`docs/en/*.md`), a bilingual reproduction of the **2nd edition**
in which Ch. 6, Ch. 11, all chapter intros/conclusions and the full Summary appendix are complete;
(b) `milkov.tech/assets/psd.pdf`, a full **1st edition** PDF, for the body text of §4.4–4.5, §5.2 and
§7.1; (c) `github.com/johnousterhout/aposd-vs-clean-code`, Ousterhout's own repo (primary); (d) the
official book page, <https://web.stanford.edu/~ouster/cgi-bin/aposd.php>.

The 1e→2e carry-over for Chapters 4/5/7 rests on an **edition-provenance argument, not a 2e source**:
the 2e appendix page refs for *Shallow Module* (pp. 25, 110) and *Information Leakage* (p. 31) are
identical to 1e, while *Pass-Through Method* moves p. 46 → p. 52 — exactly the shift Ch. 6's
documented expansion predicts. Independently, 1e §6.5 and 2e §6.5 are word-for-word identical.
Chapter **6** quotes below are from 2e text directly. Chapters **4, 5, 7** quotes are 1e text carried
by that argument — treat their *2e* wording as VERIFIED-by-inference, not VERIFIED-by-2e-source.

2e structure: 22 chapters (1–20 same titles as 1e; Ch. 21 "Decide What Matters" is new; Conclusion
moves to Ch. 22), then a back-matter "Summary" containing *Summary of Design Principles* (16 in 2e
vs. 15 in 1e) and *Summary of Red Flags* (14). VERIFIED.

### 2.1 Information leakage — Chapter 5, "Information Hiding (and Leakage)", §5.2

VERIFIED `[SUBSTANCE]` (1e text; the exact sentence is independently corroborated by the 2e appendix
entry):

> "The opposite of information hiding is information leakage. **Information leakage occurs when a
> design decision is reflected in multiple modules.** This creates a dependency between the modules:
> any change to that design decision will require changes to all of the involved modules."

VERIFIED `[SUBSTANCE]`, same section:

> "**Information leakage is one of the most important red flags in software design.** One of the best
> skills you can learn as a software designer is a high level of sensitivity to information leakage."

The 2e appendix entry restores the same phrasing: *"Information Leakage: a design decision is
reflected in multiple modules (see p. 31)."* VERIFIED `[SUBSTANCE]`.

Note a wording fork worth not conflating: the boxed **Red Flag: Information Leakage** sidebar inside
§5.2 uses different words — *"Information leakage occurs when the same knowledge is used in multiple
places, such as two different classes that both understand the format of a particular type of
file."* VERIFIED `[SUBSTANCE]`. This is the wording that circulates in third-party summaries; it is
not a competing definition.

**Applying "reflected in multiple modules" to our case, rather than asserting the fit.** The design
decision is *"acquisition happens by driving a Playwright browser page."* Where is it reflected?
(1) In the browser adapter, where it belongs. (2) **In the contract module itself**, whose signatures
name the `Page` type. (3) In the pipeline/host code that must construct a `Page` and thread it into
every adapter call, because the signatures demand one. That is three modules holding one decision —
the definition is satisfied on its own terms, not by analogy. The dependency Ousterhout predicts is
the one actually observed: the decision changed (a source with no browser arrived) and the contract
module must change to accommodate it.

### 2.2 Deep vs. shallow modules — Chapter 4, "Modules Should Be Deep", §4.4–4.5

§4.4 VERIFIED `[SUBSTANCE]`: *"The best modules are those that provide powerful functionality yet
have simple interfaces. I use the term **deep** to describe such modules… A deep module is a good
abstraction because only a small fraction of its internal complexity is visible to its users."*

§4.5 VERIFIED `[SUBSTANCE]`: *"a shallow module is one whose interface is relatively complex in
comparison to the functionality that it provides."*

**"An interface that mirrors its implementation is shallow" — REFUTED as a quotation.** That sentence
is not in the book; "mirror" occurs once in 188 pages, in an unrelated comment-naming passage
(§13.4). The nearest actual statements, all §4.5, VERIFIED `[SUBSTANCE]`:

> "The complexity of a linked list interface is **nearly as great as the complexity of its
> implementation**."
> "The method offers no abstraction, since **all of its functionality is visible through its
> interface**… **It is no simpler to think about the interface than to think about the full
> implementation.**"

2e appendix, VERIFIED `[SUBSTANCE]`: *"Shallow Module: **the interface for a class or method isn't
much simpler than its implementation** (see pp. 25, 110)."*

Use the appendix wording in review. The paraphrase "mirrors its implementation" is a fair gloss of
the idea but must not be quoted as Ousterhout's.

### 2.3 General-purpose interfaces are deeper — Chapter 6, "General-Purpose Modules are Deeper"

This chapter is the one the official book page records as **expanded in 2e** (§6.1–6.9); quotes below
are from 2e text directly. VERIFIED `[SUBSTANCE]`, §6.1 "Make classes somewhat general-purpose":

> "In my experience, the sweet spot is to implement new modules in a **somewhat general-purpose**
> fashion. The phrase 'somewhat general-purpose' means that **the module's functionality should
> reflect your current needs, but its interface should not.** Instead, the interface should be
> general enough to support multiple uses. The interface should be easy to use for today's needs
> without being tied specifically to them. The word 'somewhat' is important: don't get carried away
> and build something so general-purpose that it is difficult to use for your current needs."

That middle sentence is the single most on-point line in the book for our case. Our contract did the
inverse: the interface reflected the current *implementation*, not merely the current needs.

**§6.5 "Questions to ask yourself" — exactly three, VERIFIED `[SUBSTANCE]`** (1e §6.5 is word-for-word
identical, so there is no edition risk here). Lead-in: *"Here are some questions you can ask
yourself, which will help you to find the right balance between general-purpose and special-purpose
for an interface."*

1. **"What is the simplest interface that will cover all my current needs?"**
2. **"In how many situations will this method be used?"**
3. **"Is this API easy to use for my current needs?"**

Question 2 carries the single-use-case red flag, VERIFIED `[SUBSTANCE]`:

> "**In how many situations will this method be used?** If a method is designed for **one particular
> use**, such as the `backspace` method, **that is a red flag that it may be too special-purpose.**
> See if you can replace several special-purpose methods with a single general-purpose method."

Question 3 supplies the counterweight that stops over-correction, VERIFIED `[SUBSTANCE]`: *"If you
have to write a lot of additional code to use a class for your current purpose, that's a red flag
that the interface doesn't provide the right functionality."*

**Applying question 2 per method** is why §0's mixed-contract framing matters. `deriveLandingUrl` and
`buildLessonUrl` pass question 2 — they are expressible for any URL-addressable source.
`extractTranscript(page, …)` fails it: designed for one particular use, satisfiable in exactly one
situation.

**Important scope caveat: "designing an interface from a single use case is a red flag" is chapter
guidance, NOT a named red flag.** The 14-item red-flag list is a closed set and contains no such
entry. VERIFIED. Cite it as §6.5 question 2, never as "Ousterhout's single-use-case red flag."

### 2.4 Pass-through methods — Chapter 7, "Different Layer, Different Abstraction", §7.1

Definition, VERIFIED `[SUBSTANCE]`: *"A pass-through method is one that does little except invoke
another method, whose signature is similar or identical to that of the calling method."*

Boxed red flag, VERIFIED `[SUBSTANCE]`: *"…This typically indicates that there is not a clean
division of responsibility between the classes."*

Why bad, VERIFIED `[SUBSTANCE]`: *"**Pass-through methods make classes shallower:** they increase the
interface complexity of the class… but they don't increase the total functionality of the system."* /
*"**Pass-through methods also create dependencies between classes**…"*

Chapter 7 intro, VERIFIED `[SUBSTANCE]`: *"If a system contains adjacent layers with similar
abstractions, this is a red flag that suggests a problem with the class decomposition."*

**Honest relevance verdict: pass-through methods are a WEAK fit for our case and I would not lead
with them.** Our defect is not a method that forwards to an identically-shaped method one layer down;
it is a signature naming a foreign type. The genuinely adjacent §7 concept is **§7.5 "Pass-through
variables"** — a value threaded through many methods that mostly do not use it, which is closer to
what `page` does to the call chain. I did not obtain §7.5's body text: **UNVERIFIED**, offered as a
lead only.

### 2.5 Design it Twice — Chapter 11

VERIFIED `[SUBSTANCE]`: *"You'll end up with a much better result if you consider multiple options for
each major design decision: design it twice."* / *"**Try to pick approaches that are radically
different from each other; you'll learn more that way.** Even if you are certain that there is only
one reasonable approach, consider a second design anyway, no matter how bad you think it will be."* /
*"Designing it twice does not need to take a lot of extra time. For a smaller module such as a class,
you may not need more than an hour or two to consider alternatives."*

This is design principle #12 in the 2e appendix. VERIFIED. It is the process remedy that pairs with
the two-adapter rule (§1.3): the contract was designed once, against one source.

### 2.6 The 14 red flags (2e appendix, "Summary of Red Flags")

VERIFIED `[SUBSTANCE]`, exact names: Shallow Module · Information Leakage · Temporal Decomposition ·
Overexposure · Pass-Through Method · Repetition · Special-General Mixture · Conjoined Methods ·
Comment Repeats Code · Implementation Documentation Contaminates Interface · Vague Name · Hard to
Pick Name · Hard to Describe · Nonobvious Code. Names and wording are identical between 1e and 2e;
only page numbers differ. VERIFIED.

Two are candidates for our case: **Information Leakage** (the fit, argued in §2.1) and
**Overexposure** — *"An API forces callers to be aware of rarely used features in order to use
commonly used features"* (§5.7). Overexposure is a **near-miss**: our API forces callers to be aware
of a *foreign mechanism*, not of a rarely-used feature of the API itself. Do not use it.

---

## 3. yt-dlp's `InfoExtractor` — the positive exhibit

Source read directly: `yt_dlp/extractor/common.py` on `master`, fetched raw and read locally.
<https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/common.py>. All quotes `[EXACT]`.

**Scale (the reason this exhibit carries weight).** VERIFIED, with method stated:
- 184,481 GitHub stars at time of reading (GitHub API).
- **940 files** under `yt_dlp/extractor/` on `master` (GitHub contents API, count of `"type": "file"`).
- **1,751 unique identifiers matching `\b[A-Za-z0-9_]+IE\b`** in `yt_dlp/extractor/_extractors.py`
  (2,474 lines). *Method caveat:* this is a name-pattern count over the registry file, not a count of
  `class` definitions; treat it as "on the order of 1,700+ extractor classes", not as an exact
  class count.

These adapters span HTML scraping, JSON APIs, HLS/DASH/ISM/F4M manifests, and cookie/OAuth auth. They
are unified by an output-shape contract.

### 3.1 The docstring is overwhelmingly about output shape

The `InfoExtractor` class docstring runs lines **106–580** (~475 lines). Its composition, VERIFIED by
direct line accounting:

| Span | Content | Lines |
| --- | --- | --- |
| 108–114 | Framing | 7 |
| 116–529 | **The info-dict output specification** (video fields, `formats` sub-dict schema, `_type` variants: playlist, multi_video, url, url_transparent) | **414 (~87%)** |
| 532–579 | Subclass obligations and configuration attributes | 48 (~10%) |

Framing, `[EXACT]`:

> "Information extractors are the classes that, given a URL, extract information about the video (or
> videos) the URL refers to. This information includes the real video URL, the video title, author
> and others. **The information is stored in a dictionary which is then passed to the YoutubeDL.**"

Required output, `[EXACT]`:

> "For a video, the dictionaries **must** include the following fields:
>
> `id`: Video identifier.
> `title`: Video title, unescaped. Set to an empty string if video has no title as opposed to 'None'
> which signifies that the extractor failed to obtain a title
>
> Additionally, it **must** contain either a `formats` entry or a `url` one:
>
> `formats`: A list of dictionaries for each format available, ordered from worst to best quality."

The `formats` schema then specifies ~60 fields. Note that even the transport-specific detail is
expressed as **output data**, not as an interface obligation — `[EXACT]`:

> "`* url` The mandatory URL representing the media: for plain file media - HTTP URL of this file,
> for RTMP - RTMP URL, for HLS - URL of the M3U8 media playlist, for HDS - URL of the F4M manifest,
> for DASH … for MSS - URL of the ISM manifest."

Five wildly different transports, one output field. This is what "prescribes WHAT, not HOW" looks
like when it is done correctly: the contract names the *shapes the transports produce*, never a
handle to any transport's client object.

### 3.2 The required interface takes only a URL

`[EXACT]`, lines 532–534:

> "Subclasses of this should also be added to the list of extractors and should define `_VALID_URL`
> as a regexp or a Sequence of regexps, and re-define the `_real_extract()` and (optionally)
> `_real_initialize()` methods."

`[EXACT]`, line 830:

```python
def _real_extract(self, url):
    """Real extraction process. Redefine in subclasses."""
    raise NotImplementedError('This method must be implemented by subclasses')
```

**One required method. Its only input is a URL string — an input the host owns. Its output is the
info dict.** Every acquisition decision (fetch a page? call a JSON API? parse an m3u8? shell out?)
lives inside the method body.

### 3.3 The acquisition helpers are helpers, not signature-level requirements — CONFIRMED

VERIFIED by reading the definitions:

- `def _download_webpage(self, url_or_request, video_id, note=None, errnote=None, fatal=True, tries=1, timeout=NO_DEFAULT, *args, **kwargs)` — line 1172.
- `def _download_webpage_handle(self, url_or_request, video_id, …)` — line 925.
- `_download_json_handle, _download_json = __create_download_methods(…)` — line 1166.
- `def _extract_m3u8_formats(self, *args, **kwargs)` — line 2168, delegating to
  `_extract_m3u8_formats_and_subtitles(self, m3u8_url, video_id, …)` at line 2174.

All are **instance methods on the base class that a subclass may call from inside `_real_extract`**.
None appears in the required subclass surface (§3.2). An extractor that never calls
`_download_webpage` is perfectly valid. **The contract does not force a transport into the
interface.** CONFIRMED as the task hypothesised.

Contrast, stated plainly: yt-dlp's equivalent of our mistake would be
`_real_extract(self, page, url)`. It does not do that. Note especially that
`_extract_m3u8_formats_and_subtitles(self, m3u8_url, …)` takes a **URL string**, not an HLS client
object — even the manifest helper refuses to name a mechanism in its parameter list.

### 3.4 The honest limit: yt-dlp's contract DOES constrain some mechanism

This is where "prescribes WHAT, not HOW" is too strong as stated, and the evidence is in the same
lines 532–579 `[EXACT]`:

- `_VALID_URL` must be **"a regexp or a Sequence of regexps"** — a mechanism choice (regex matching),
  imposed on every extractor.
- *"Subclasses may also override `suitable()` if necessary, but **ensure the function signature is
  preserved** and that this function imports everything it needs (except other extractors), **so that
  lazy_extractors works correctly**."* — an explicit HOW, with the host's reason attached.
- *"To support username + password (or netrc) login, the extractor must define a `_NETRC_MACHINE` and
  re-define `_perform_login(username, password)`…"* — a prescribed auth protocol.
- `_GEO_BYPASS`, `_GEO_COUNTRIES`, `_GEO_IP_BLOCKS`, `_ENABLED`, `_WORKING` — host-machinery hooks.

**The distinction that actually holds is not WHAT-vs-HOW.** It is: the HOW a contract may constrain
is **host-owned protocol** (how the host discovers, dispatches to, authenticates, and lazily loads an
adapter), never **adapter-owned technology** (how the adapter reaches its source). Every constraint
in the list above is host machinery. None of them is one adapter's acquisition library.

### 3.5 yt-dlp also does host-capability injection — at exactly one seam

This is the strongest single piece of evidence for the "limits" answer in §7.2, and it sits inside
the positive exhibit itself. `[EXACT]`:

```python
def __init__(self, downloader=None):
    """Constructor. Receives an optional downloader (a YoutubeDL instance).
    If a downloader is not passed during initialization,
    it must be set using "set_downloader()" before "extract()" is called"""
```
```python
def set_downloader(self, downloader):
    """Sets a YoutubeDL instance as the downloader for this IE."""
    self._downloader = downloader
```
```python
def get_param(self, name, default=None, *args, **kwargs):
    if self._downloader:
        return self._downloader.params.get(name, default, *args, **kwargs)
    return default
```

Three observations, all VERIFIED from the source:

1. The host object (`YoutubeDL`) enters through the **constructor**, at one seam.
2. `_real_extract(self, url)` — the required working method — **is untouched by it**. The extractor
   closes over `self._downloader`; it is never threaded through the interface.
3. `get_param` **guards against the host object's absence** and returns a default. The extractor is
   built to function without it.

That is the same shape as Rollup / Vite / ESLint / webpack (§6), reached independently, inside the
codebase whose output contract is our positive exhibit.

---

## 4. The failure mode's recognized names — which apply, which are misapplications

### 4.1 "Leaky abstraction" (Spolsky) — **MISAPPLIED here**

Source: <https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/>, 2002-11-11.
VERIFIED (date). The law, VERIFIED `[SUBSTANCE]` (returned identically by two independent fetches):

> "All non-trivial abstractions, to some degree, are leaky."

Supporting, VERIFIED `[SUBSTANCE]`: *"Abstractions fail. Sometimes a little, sometimes a lot. There's
leakage."*

His examples are uniformly **runtime/behavioural**, VERIFIED `[SUBSTANCE]` (wording approximate — the
same URL returned two different renderings of the SQL sentence, so treat every phrase here as
substance, not verbatim): TCP over unreliable IP ("TCP attempts to provide a complete abstraction of
an underlying unreliable network, but sometimes, the network leaks through"); SQL queries thousands
of times slower than logically equivalent ones; remote-file-is-like-local-file; 2-D array iteration
performance differing by traversal order; ASP.NET breaking with JavaScript disabled.

Wikipedia's `Leaky_abstraction` article defines it the same narrow way and every example it lists is
runtime/behavioural or cognitive. VERIFIED `[SUBSTANCE]`.
<https://en.wikipedia.org/wiki/Leaky_abstraction>

**Verdict: REFUTED as the name for our case, and the misapplication is actively harmful.** Spolsky's
leak presupposes an abstraction that *does* hide the substrate and then fails at the margins. In the
`page`-typed signature case **nothing leaked, because nothing was ever hidden** — the substrate is
named in the contract, at design time, in the normal case, in every case. That is the *absence* of an
abstraction, not a hole in one.

The harm is specific: "leaky abstraction" imports an inevitability excuse — *"All non-trivial
abstractions, to some degree, are leaky"* — that licenses shrugging. Our leak was avoidable and is
fixable by naming the port after the conversation instead of the tool. Reaching for Spolsky here
converts a design error into a law of nature. **Do not use this name.**

### 4.2 Parnas 1972 — **the primary, best-sourced name**

Citation: D. L. Parnas, "On the Criteria To Be Used in Decomposing Systems into Modules",
*Communications of the ACM* **15**(12), December 1972, pp. 1053–1058. Text-extractable digitized copy:
<https://cw.fel.cvut.cz/old/_media/courses/a4m33sep/materialy/architecture_and_design/01-article_original_de_parnas.pdf>
VERIFIED `[EXACT]` (extracted with `pdftotext`). Page range VERIFIED from the copy's own header line;
**per-quote CACM page numbers UNVERIFIED** — the digitized copy's internal page markers do not map
onto 1053–1058.

The criterion, from the Conclusion, `[EXACT]`:

> "We propose instead that one begins with a list of difficult design decisions or **design decisions
> which are likely to change. Each module is then designed to hide such a decision from the others.**"

The interface sentence, from "The Criteria", `[EXACT]`:

> "Every module in the second decomposition is characterized by its knowledge of a design decision
> which it hides from all others. **Its interface or definition was chosen to reveal as little as
> possible about its inner workings.**"

**And the passage that is our case in 1972 vocabulary** — from "Improvement in Circular Shift
Module", where Parnas critiques his *own* published interface, `[EXACT]`:

> "Hindsight now suggests that **this definition reveals more information than necessary.**"
> "By prescribing the order for the shifts **we have given more information than necessary and so
> unnecessarily restricted the class of systems that we can build without changing the
> definitions.**"
> "Our failure to do this in constructing the systems with the second decomposition **must clearly be
> classified as a design error.**"

"Unnecessarily restricted the class of systems that we can build without changing the definitions" is
a literal description of what has happened: the class of systems buildable against the contract was
restricted to browser-driven ones, and admitting yt-dlp requires changing the definitions.

This is the citation I would defend. It is byte-exact, it is the founding paper of the field's
information-hiding criterion, and it names our exact mechanism *and* verdict ("design error").

### 4.3 Ousterhout, "Information leakage" — **the modern short name**

See §2.1 for the definition, the application, and the sourcing caveat. This is the name to use in a
code review with a modern audience: it is one phrase, it has a book behind it, and its definition
("a design decision is reflected in multiple modules") is satisfied literally, not by analogy.

Pairing note: Parnas supplies the *criterion* (hide decisions likely to change) and the *verdict*;
Ousterhout supplies the *name* for the symptom. They are the same idea 49 years apart, and citing
both costs one sentence.

### 4.4 Dependency Inversion Principle — **part B is a direct literal hit**

Source: Robert C. Martin, "The Dependency Inversion Principle", *C++ Report*, 1996.
<https://www.cs.utexas.edu/~downing/papers/DIP-1996.pdf> — VERIFIED `[EXACT]` (extracted with
`pdftotext`). Note: the all-caps below is the original's **small-caps** rendering, not emphasis.

> "A. HIGH LEVEL MODULES SHOULD NOT DEPEND UPON LOW LEVEL MODULES. BOTH SHOULD DEPEND UPON
> ABSTRACTIONS."
> "B. **ABSTRACTIONS SHOULD NOT DEPEND UPON DETAILS. DETAILS SHOULD DEPEND UPON ABSTRACTIONS.**"

Part B is exactly our defect in nine words: `Page` is a detail, the contract is the abstraction, and
the abstraction depends on the detail. This is the most compact and most review-legible framing
available.

Also `[EXACT]`, from "Finding the Underlying Abstraction":

> "What is the high level policy? It is the abstractions that underlie the application, **the truths
> that do not vary when the details are changed.**"
> "**What mechanism is used to detect the user gesture? Irrelevant!** What is the target object?
> Irrelevant! **These are details that do not impact the abstraction.**"

Cockburn's 2005 paper cites DIP explicitly under "Related Patterns", VERIFIED `[EXACT]` — so this is
not a cross-tradition splice.

**"Clients own the interfaces" — REFUTED for the 1996 DIP article.** A full-text grep of the extracted
article for `own`, `belong`, `client`, `invert` finds **no** statement that the abstraction belongs to
or is owned by the client. "Inversion" is explained *solely* as inversion of dependency direction
relative to Structured Design. **Agile Software Development, Principles, Patterns, and Practices
(2002) — UNVERIFIED**: only secondary paraphrases were reachable; no page number or wording is
asserted here.

### 4.5 Interface Segregation Principle — **the best-sourced "the interface is shaped by its clients"**

Source: Robert C. Martin, "The Interface Segregation Principle", *C++ Report*, 1996.
<https://www.cs.utexas.edu/~downing/papers/ISP-1996.pdf> — VERIFIED `[EXACT]`.

> "CLIENTS SHOULD NOT BE FORCED TO DEPEND UPON INTERFACES THAT THEY DO NOT USE."

And the directional argument — section heading plus body, `[EXACT]`:

> "**Separate Clients mean Separate Interfaces.**"
> "Since the clients are separate, the interfaces should remain separate too. Why? Because… **clients
> exert forces upon their server interfaces.**"
> "**The backwards force applied by clients upon interfaces.**"
> "When we think of forces that cause changes in software, we normally think about how changes to
> interfaces will affect their users. … However, **there is a force that operates in the other
> direction. That is, sometimes it is the user that forces a change to the interface.**"

Use this instead of the unverified Agile-PPP "clients own the interfaces" paraphrase. It is also the
**structural diagnosis of why the defect happened**: only one client-side implementation existed, so
only one implementation's forces shaped the interface. Garrido de Paz's "**ports belong to the
application**" (§1.3, `[EXACT]`) is the ports-and-adapters restatement of the same thing.

### 4.6 Fowler, "Separated Interface" — the remedy vocabulary, with one premise refuted

Source: <https://martinfowler.com/eaaCatalog/separatedInterface.html>, *Patterns of Enterprise
Application Architecture* (2002). VERIFIED `[SUBSTANCE]`:

> "Defines an interface in a separate package from its implementation."
> "If so, use Separated Interface to define an interface in one package but implement it in another."
> "This way a client that needs the dependency to the interface can be completely unaware of the
> implementation."

**"Define the interface in the client's package" — REFUTED at that URL.** A targeted re-fetch
restricted to exact sentences containing "package"/"client" reports the catalog page contains no such
sentence; the earlier reading was the fetch extractor *inferring*, not Fowler writing. The full P of
EAA book chapter may carry the client-package discussion — **UNVERIFIED**, the book text was not
reachable. **Do not cite the catalog URL for that claim.**

The pattern still applies as remedy vocabulary — the contract module belongs with the pipeline that
consumes it, not with the browser adapter that first implemented it — but source it to ISP §4.5 or
Garrido de Paz §1.3, not to this page.

### 4.7 Rule of Three, and abstracting from N=1

**Rule of Three — VERIFIED `[SUBSTANCE]`, page UNVERIFIED.** Fowler, *Refactoring* (1st ed., 1999),
Ch. 2 "Principles in Refactoring", section "When Should You Refactor?", sub-heading "The Rule of
Three", attributed to Don Roberts:

> "Here's a guideline Don Roberts gave me: The first time you do something, you just do it. The
> second time you do something similar, you wince at the duplication, but you do the duplicate thing
> anyway. The third time you do something similar, you refactor."
> "Three strikes, then you refactor."

Sources: <https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming)>,
<https://eoinnoble.com/posts/origins-of-the-rule-of-three/>. Notes: the popular form is "three
strikes **and** you refactor"; the reported book wording is "three strikes, **then** you refactor" —
variance flagged rather than smoothed. The commonly-cited **p. 58 is UNVERIFIED**. **2nd ed. (2018)
status UNVERIFIED** — Fowler's own "Changes for the 2nd Edition" says only that the principles and
smells chapters "had a thorough overhaul… about three-quarters of it changed"
(<https://www.martinfowler.com/articles/refactoring-2nd-changes.html>) without saying whether this
section survived.

**Scope caveat, important:** the Rule of Three is literally about *duplication → extract*, not about
*interface design from one implementation*. It is the closest canonical N≥3 threshold and is routinely
generalized, but citing it for our case is an **analogy**, not a direct hit. Say so if you use it.

**Sandi Metz, "The Wrong Abstraction" — the best-fitting named guidance for N=1.** VERIFIED
`[SUBSTANCE]`. <https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction>, 2016-01-20; originating
in her RailsConf 2014 talk "all the little things":

> "duplication is far cheaper than the wrong abstraction"

Her prescribed remedy is to **re-inline the abstraction back into its callers and re-derive it** —
which is the honest fix for a `page`-typed contract, as opposed to bolting on an `if (isBrowser)`
branch or an optional-`page` parameter.

**"AHA" / "Avoid Hasty Abstractions"** — <https://kentcdodds.com/blog/aha-programming>, 2020-06-22.
VERIFIED `[SUBSTANCE]` but **blog-tier**; the post itself credits the acronym to Cher Scarlett and
the underlying idea to Metz. Use as a mnemonic only; cite Metz as the authority.

**"Premature generalization" / "premature abstraction" — REFUTED as a canonical named smell.** No
book- or catalog-tier source names either term; every hit is blog-tier and treats it as a synonym for
Speculative Generality.

**Speculative Generality — VERIFIED as a real smell, but it does NOT describe our case.**
*Refactoring*, "Bad Smells in Code" chapter (Ch. 3 in 1e; retained in 2e). From an authorized InformIT
2e excerpt, VERIFIED `[SUBSTANCE]`
(<https://www.informit.com/articles/article.aspx?p=2952392&seqNum=15>):

> "You get it when people say, 'Oh, I think we'll need the ability to do this kind of thing someday'
> and thus add all sorts of hooks and special cases to handle things that aren't required."

Speculative Generality is *too much unused generality added for an imagined future*. Ours is the
opposite — *too little generality, hard-wired to the present incumbent*. Anyone who reaches for this
name in review is diagnosing backwards. Flagged because it is a likely wrong turn.

### 4.8 Abstraction inversion — **real anti-pattern, DOES NOT APPLY**

VERIFIED `[SUBSTANCE]`: <https://en.wikipedia.org/wiki/Abstraction_inversion>

> "In computer programming, abstraction inversion is an anti-pattern arising when users of a construct
> need functions implemented within it but not exposed by its interface."

Users are then forced to re-implement the needed primitive on top of the higher-level public
interface. Origin traced by Wikipedia's citation list to **Henry Baker, "Critique of DIN Kernel Lisp
Definition Version 1.2," footnote 2** — VERIFIED as the cited origin. **AntiPatterns (Brown et al.,
1998) — UNVERIFIED and unsupported**; no such entry appears in the article's sources. **c2 wiki —
UNVERIFIED**; `wiki.c2.com/?AbstractionInversion` is JS-rendered and returned no text.

**Verdict: REFUTED for our case, on a near-opposite mechanism.** Abstraction inversion is an interface
exposing **only high-level operations** and withholding primitives. Ours exposes a **low-level,
implementation-specific primitive** in its signatures. Nobody is rebuilding a primitive on top of a
too-high API; a second implementer simply cannot satisfy the contract at all.

---

## 5. Contract tests (Fowler / Robinson)

### 5.1 Three refutations of premises in the brief — recorded, not smoothed

1. **`IntegrationContractTest.html` and `ContractTest.html` are not two entries.** VERIFIED: the
   former **301-redirects** to the latter and the fetched bodies are byte-identical. Fowler's own
   revision note, `[EXACT]`: *"2018-01-01: Originally this bliki entry was entitled Integration
   Contract Test. Since it was written the term "contract test" has become widely used for these, so
   I changed the bliki entry."* Cite `ContractTest.html` only.
2. **"Run the same contract tests against every implementation of an interface" is NOT on Fowler's
   page. REFUTED.** The article is short (~3.4 KB of prose) and was read in near-entirety; it contains
   no mention of interfaces, implementations, polymorphism, or a suite reused across implementations.
   Fowler's contract test is **one consumer's suite run against one external supplier**. The
   "one suite, N implementations" idea is a different concept (commonly "interface contract testing",
   lineage usually credited to J. B. Rainsberger) — **UNVERIFIED**, no primary source fetched, and
   **not Fowler's**.
3. See §4.6 for the third (Separated Interface / client's package).

### 5.2 What Fowler and Robinson actually say

Fowler, <https://martinfowler.com/bliki/ContractTest.html>, 12 January 2011. `[EXACT]`:

> "These check that all the calls against your test doubles **return the same results** as a call to
> the external service would. A failure in any of these contract tests implies you need to update your
> test doubles, and probably your code to take into account the service contract change."

And the single most load-bearing sentence for the output-shape claim, `[EXACT]`:

> "Contract tests check the contract of external service calls, but not necessarily the exact data.
> Often a stub will snapshot a response as at a particular date, since **the format of the data
> matters rather than the actual data.** In this case the contract test needs to check that the
> format is the same, even if the actual data has changed."

Robinson, "Consumer-Driven Contracts: A Service Evolution Pattern",
<https://martinfowler.com/articles/consumerDrivenContracts.html>, 12 June 2006. `[EXACT]`:

> "By expressing and asserting expectations of a provider contract, consumer contracts effectively
> define which parts of that provider contract currently support the business value realized by the
> system… **In this view, provider contracts emerge to meet consumer expectations and demands.**"

The admission criterion, `[EXACT]`:

> "How do we decide whether to include a candidate contractual element in our provider contract? We do
> so by asking ourselves whether **any of our consumers might reasonably express one or more
> expectations** that the business function capability encapsulated by the element continue to be
> satisfied throughout the service's lifetime."

### 5.3 Adjudication of "the contract is best pinned by tests against the OUTPUT/behavior rather than by the interface's method signatures"

**PARTIALLY SUPPORTED. First half is Fowler's framing; the exclusionary second half is an overreach,
and Robinson contradicts it directly.**

**Half 1 — SUPPORTED.** Fowler defines the check as an output comparison ("return the same results"),
and explicitly abstracts above literal payload content to shape ("the format of the data matters
rather than the actual data"). The mechanism he prescribes is *running tests*, not comparing
declarations.

**Half 2 — REFUTED for consumer-driven contracts.** Robinson enumerates what a provider contract
*contains*, and operation signatures are a first-class member. `[EXACT]`:

> "**Interfaces** In their simplest form, service provider interfaces comprise **the set of exportable
> operation signatures** a consumer can exploit to drive the behaviour of a provider… Either way,
> consumers depend on some portion of a provider's interface to realise business value, and in
> consequence **we must account for interface consumption when evolving our service landscape.**"

The full member list is **Document schemas, Interfaces, Conversations, Policy, Quality of service
characteristics** — behaviour and signatures sit side by side as peers, never opposed. And Robinson's
admission criterion is *consumer expectation*, not artifact kind: it **admits** signatures whenever a
consumer depends on them.

Neither source ever poses output *versus* signature. Fowler's contrast is a different axis entirely
(test double vs. real supplier; format vs. exact data). Reading "output not signatures" out of "format
not data" is a category substitution.

**Safe restatement both sources bear:**

> A contract is *verified* by executing tests that assert the supplier's observable responses — their
> format, not their literal data — against what consumers actually depend on; and what counts as being
> *in* the contract is settled by consumer expectation, which can include operation signatures,
> schemas, conversations, policy, and QoS alike.

**Consequence for our design:** do not conclude "signatures don't matter, only output does." Conclude
the sharper thing — **signatures are in the contract, which is precisely why what they are permitted
to mention is a design decision, and why output-shape assertions (not signature shape alone) are what
prove an adapter conforms.** A `page`-typed signature is a *contract element no consumer of the
pipeline ever expressed an expectation about*; by Robinson's own admission criterion it should never
have been in the contract.

---

## 6. Host-owned capability injection in mature plugin systems

The question this settles: **is passing a host-owned capability into an adapter different in kind
from leaking one implementation's technology into the interface?** Five mature systems, from official
docs.

**Correction to a premise in the brief, recorded first.** The brief proposed the axis "optional hooks
receiving host objects vs. mandatory signatures taking a mechanism." **The evidence does not support
optionality as the load-bearing distinction** — three of five systems inject the host object into a
**mandatory** position (ESLint's `create`, webpack's `apply`, Babel's plugin factory). Building the
argument on optionality would put ESLint and webpack on the wrong side of it.

**What actually holds across all five: host-ownership + fleet-wide uniformity + single-seam
confinement.**

| System | Injected object | Host-owned? | Uniform across all plugins? | Injection site | Doc says it can be absent/ignored? |
| --- | --- | --- | --- | --- | --- |
| Rollup | `this` (PluginContext) | YES — "**Rollup's internal** SWC-based parser" | YES | `this` binding in "most hooks" | Not stated (INFERENCE: yes) |
| Rolldown | `this` (PluginContext) | YES | YES | same framing verbatim | Not stated |
| Vite | `ViteDevServer`, `ResolvedConfig` | YES | YES | **one opt-in hook each** | **YES, explicitly** |
| ESLint | `context` | YES | YES | one **mandatory** factory arg | Not stated (INFERENCE) |
| webpack | `compiler` | YES — "underlying webpack compiler" | YES | one **mandatory** `apply` arg, once at install | Not stated |
| Babel | `api` | YES — "supplied … by Babel itself" | YES | one **mandatory** factory arg | Not stated |
| **yt-dlp** | `downloader` (YoutubeDL) | YES | YES | **constructor / `set_downloader`** | **YES — `get_param` returns a default when absent** |

Sources and key quotes (all VERIFIED):

- **Rollup**, <https://rollupjs.org/plugin-development/> — *"A Rollup plugin is an object with **one or
  more** of the properties, build hooks, and output generation hooks described below."* /
  *"A number of utility functions and informational bits can be accessed from within **most hooks** via
  `this`."* / `this.parse` = *"Use **Rollup's internal** SWC-based parser…"*
- **Rolldown**, <https://rolldown.rs/apis/plugin-api> — carries the *identical* framing sentence. (Note:
  Vite now states *"Vite plugins extends **Rolldown's** plugin interface"*, not Rollup's — the pattern
  survived an engine swap intact, which is itself evidence of its durability.)
- **Vite**, <https://vite.dev/guide/api-plugin> — `configureServer(server: ViteDevServer)`; the docs'
  "Storing Server Access" pattern shows `configureServer(_server) { server = _server }` alongside an
  untouched `transform(code, id)`. And the strongest single quote in the whole survey:
  *"Note `configureServer` is **not called** when running the production build so your other hooks need
  to **guard against its absence**."* Also *"These hooks are **ignored by Rollup**."*
- **ESLint**, <https://eslint.org/docs/latest/extend/custom-rules> — *"The `context` object is the **only
  argument** of the `create` method in a rule."* Yet the visitor methods `create` *returns*
  (`Identifier(node)`, `"FunctionExpression:exit"`) receive **only AST arguments, never `context`** —
  the rule closes over it. The surface is centrally governed: *"Earlier versions of ESLint supported
  additional methods on the `context` object. Those methods were removed in the new format and should
  not be relied upon."*
- **webpack**, <https://webpack.js.org/contribute/writing-a-plugin/> — *"The `apply` method is given a
  reference to the **underlying webpack compiler**."* / plugins *"**Manipulate webpack internal**
  instance specific data."* Compiler given once at install; tapped callbacks then receive domain
  payloads (`compilation`, `assets`, `stats`), not the compiler.
- **Babel** — official docs have **no plugin-development page** (VERIFIED by enumerating the
  `babel/website` `docs/` directory via the GitHub API; `babeljs.io/docs/plugins` is a catalog). The one
  official page stating the signature is <https://babeljs.io/docs/babel-helper-plugin-utils>:
  `declare((api, options, dirname) => { return {}; })`, with *"`api.assertVersion` always exists…
  when not supplied by **Babel itself**"* and *"Every one of Babel's core plugins and presets will use
  this module."* The returned visitor object's methods taking AST args rather than `api` is
  **UNVERIFIED** from official docs.
- **yt-dlp** — §3.5 above, read directly from source. `[EXACT]`.

**The property that holds in every case, and is the discriminator:**

1. **The object is the HOST's own service surface, never a plugin's technology.** Rollup's
   `this.parse` is *Rollup's* parser; ESLint's `context.report` publishes into *ESLint's* problem
   pipeline; webpack's docs literally say "manipulates **webpack internal** instance specific data";
   yt-dlp's `_downloader` is the *YoutubeDL* driver. Nothing here is one plugin's choice of library
   imposed on its peers — which is exactly what our `page` parameter is.
2. **It is identical for every plugin.** Nobody negotiates a variant. ESLint governs the surface so
   centrally that it *removed* methods and published a note saying so.
3. **It enters at exactly ONE seam and does not propagate into working-method signatures.** This holds
   even where injection is mandatory. Vite: `configureServer(server)` stores it; `transform(code, id)`
   stays clean. ESLint: `create(context)` takes it; the returned visitors do not. webpack:
   `apply(compiler)` once at install; tapped callbacks get `assets`. Babel: factory takes `api`; the
   returned visitor object does not. yt-dlp: constructor takes `downloader`;
   `_real_extract(self, url)` does not. **In every system the host object arrives once and is closed
   over — it is never threaded through every method's parameter list.**

Property 3 is the one our contract violates most visibly. Even if `page` were a legitimate
host-owned capability (it is not — see §7.2), threading it through *every* acquisition method's
parameter list would still be the wrong shape by the unanimous practice of five mature systems.

---

## 7. Answers

### 7.1 Does the rule hold up in the form stated? Is there a sharper formulation?

**The rule is directionally right and the codebase's own header is self-refuting for three of five
methods — but "prescribes WHAT, not HOW" is too strong in one direction and too vague in another, and
should not be adopted verbatim.**

**Too strong.** yt-dlp — the strongest available positive exhibit, with 1,700+ adapters — *does*
constrain HOW: `_VALID_URL` must be a regex; `suitable()`'s signature "must be preserved… so that
lazy_extractors works correctly"; `_perform_login(username, password)` is a prescribed auth protocol;
`_GEO_BYPASS`/`_ENABLED`/`_WORKING` are host-machinery hooks (§3.4, all `[EXACT]`). A rule that
forbids the contract from constraining any HOW is contradicted by the exhibit meant to prove it.

**Too vague.** "WHAT adapters produce" does not tell an author what a *parameter* may name — which is
precisely the decision that went wrong.

**Critique of the brief's candidate sharper form** — *"the contract fixes the OUTPUT TYPES and the
ACQUISITION OBLIGATIONS, and takes only inputs the pipeline itself owns — never a handle to a
mechanism only one adapter uses."* It fails on its own evidence in three places:

- **"a mechanism only one adapter uses"** — the adapter-count test is the wrong discriminator. §6
  found the discriminator is host-ownership + uniformity + single-seam confinement, explicitly *not*
  adapter count. A host capability used by exactly one adapter (Vite's dev server, used by a minority
  of plugins) is legitimate; a technology used by *two* adapters is still wrong. Count is not the
  variable.
- **"ACQUISITION OBLIGATIONS"** is undefined filler, and Cockburn's two sentences already do the whole
  job including the permission clause: *"Never explicitly name any external object or technology.
  Always take a parameter for any external object or technology you wish to access."*
- **"fixes OUTPUT TYPES"**, if read as *signatures are not the contract*, overreaches — Robinson lists
  **Interfaces** ("the set of exportable operation signatures") as a first-class contract member
  (§5.3). The sharp claim is about what a signature may **mention**, not about signatures being
  outside the contract.

**Proposed replacement — four clauses, each with a citation and each independently checkable:**

> 1. **No signature in the contract may name an external technology.** Parameters and return types
>    mention only domain concepts, host-owned values, and host-owned capabilities.
>    *(Cockburn: "Never explicitly name any external object or technology." Garrido de Paz: "Ports
>    should be named according to what they are for, not according to any technology." DIP part B:
>    "Abstractions should not depend upon details.")*
> 2. **Every adapter obligation is stated as an output shape the adapter must return**, never as a
>    mechanism it must be handed.
>    *(yt-dlp: ~87% of the `InfoExtractor` docstring specifies the info dict; the one required method
>    is `_real_extract(self, url)`.)*
> 3. **The contract may constrain HOW only where the HOW is host-owned protocol** — discovery,
>    dispatch, lifecycle, auth handshake, capability declaration — never adapter-owned acquisition
>    technology.
>    *(yt-dlp: `_VALID_URL`, `suitable()`, `_perform_login`, `_GEO_*` are all host machinery.)*
> 4. **Host capabilities may be injected, at ONE seam, uniformly for all adapters, and every adapter
>    must function without them** — never threaded through working-method parameter lists.
>    *(Vite: "your other hooks need to guard against its absence." ESLint `create(context)` → visitors
>    without it. webpack `apply(compiler)` once at install. yt-dlp `__init__(downloader=None)` and
>    `get_param`'s `if self._downloader: … return default`.)*

**Empirical test that pins all four cheaply:** Garrido de Paz's two-adapter rule — *"For each driver
port, there should be at least two adapters: one for the real driver… and another one for testing the
behaviour of the port."* A signature a trivial fixture adapter cannot satisfy has failed before the
second real source is written. Pair it with Fowler's format-not-data framing: assert the returned
shape, not the call shape.

**Naming check, runnable in review:** say the method aloud as "this port is for …ing something."
*"…for obtaining a transcript"* passes. *"…for running a Playwright page"* fails.

### 7.2 Where does the rule have limits? Is a host-owned capability different from an implementation handle?

**Yes — categorically different, and the distinction is documented, not invented.** Cockburn's own
statement contains the permission clause: *"**Always take a parameter for any external object or
technology you wish to access.**"* `[EXACT]` The pattern does not forbid parameters. It forbids
parameters that **name** a technology. In his own example code the parameter type is
`ForGettingTaxRates` — a domain-named port — not `SqlConnection`.

Five mature systems plus yt-dlp inject host services into plugins (§6). The three properties that
make it legitimate:

1. **Host-owned** — the object is the host's own service surface, not one adapter's library.
2. **Fleet-uniform** — identical for every adapter; centrally governed (ESLint removes methods and
   says so).
3. **Single-seam and absence-tolerant** — arrives once (constructor / one hook), is closed over, does
   not appear in working-method signatures, and the adapter must run without it (Vite states this
   outright; yt-dlp's `get_param` implements it).

**Does the Playwright `page` qualify?** **No, on all three counts.**

1. **Not host-owned in kind.** A `Page` is Playwright's object, not the pipeline's. The pipeline
   would be lifecycling a third-party browser client purely because one adapter wants it.
2. **Not fleet-uniform.** The yt-dlp adapter has no use for it, cannot receive one meaningfully, and
   the host cannot supply one without launching a browser it does not otherwise need.
3. **Not single-seam.** It is threaded through *every* acquisition method's parameter list — the exact
   shape all six surveyed systems avoid.

**The legitimate reshaping, if the host must own a shared resource.** A browser context genuinely is
expensive and genuinely should be host-lifecycled — that is a real constraint, not a rationalization.
But it is satisfied by:

- a **host-owned, uniform capability object** injected at **one** seam (adapter construction), whose
  members are named in *pipeline* terms (`fetchText(url)`, `fetchJson(url)`, `openSession()`) rather
  than in Playwright terms; the browser adapter's *own* module owns the Playwright dependency;
- **or** a declared capability requirement — the adapter states what it needs and the host provisions
  it, which is closer to yt-dlp's `_NETRC_MACHINE` / `_GEO_BYPASS` declaration style than to a
  parameter;
- **and** in either case, `extractTranscript(lessonRef)` returning a typed transcript, with the
  capability closed over.

**The line, stated once:** the host may inject **its own capabilities**; it may never inject **one
adapter's client object**. Ownership and uniformity draw the line — *not* optionality, and *not*
how many adapters happen to use the thing.

### 7.3 Name the failure mode precisely — the citation I would defend

**Layered, strongest first:**

**1. Primary — Parnas (1972): an interface that reveals a design decision likely to change.** The
byte-exact sentence to defend is his own self-critique: *"we have given more information than
necessary and so unnecessarily restricted the class of systems that we can build without changing the
definitions,"* and his verdict, *"must clearly be classified as a design error."* (CACM 15(12),
Dec 1972, pp. 1053–1058, §"Improvement in Circular Shift Module".) This is our case in the field's
founding vocabulary, with the mechanism and the verdict both stated. VERIFIED `[EXACT]`.

**2. Modern short name — Ousterhout, "Information Leakage"** (*A Philosophy of Software Design*, 2nd
ed., **Chapter 5 "Information Hiding (and Leakage)", §5.2**; also the 2nd red flag in the Summary of
Red Flags). *"Information leakage occurs when a design decision is reflected in multiple modules."*
The fit is literal, not analogical: the decision *"acquisition is by driving a Playwright page"* is
reflected in the browser adapter, in the contract module's signatures, and in the host code that must
construct and thread a `Page` — three modules, one decision, and the predicted dependency has now
fired. VERIFIED `[SUBSTANCE]`, with the 2e sourcing caveat in §2's preamble.

**3. Pattern-local name — Cockburn, "Weak versus strong conformance to the pattern"** (*Hexagonal
Architecture Explained*, book p. 27, v1.1b update pages). *"You can implement this pattern in a legal
but weak way… While technically meeting the rules of the architecture, that still ties your system to
SQL."* **With the escalation stated:** our contract is worse than weak conformance. Cockburn's weak
case is *legal* — SQL-flavoured but implementable. Ours is **unsatisfiable**: a `Page` parameter
cannot be met by an adapter with no browser, so the second adapter cannot be written at all. Not weak
conformance — non-conformance. VERIFIED `[EXACT]`.

**4. Most review-legible one-liner — DIP part B:** *"Abstractions should not depend upon details.
Details should depend upon abstractions."* (Martin, C++ Report, 1996.) VERIFIED `[EXACT]`.

**5. Structural cause — ISP's backwards force:** *"there is a force that operates in the other
direction… sometimes it is the user that forces a change to the interface."* Only one implementation
existed, so only one implementation's forces shaped the contract. Compounded by an abstraction derived
at **N=1** — below the Rule of Three threshold, and Metz's *"duplication is far cheaper than the wrong
abstraction"* with its re-inline-and-re-derive remedy. VERIFIED `[EXACT]` / `[SUBSTANCE]` respectively.

**Do NOT use, with reasons:**

- **"Leaky abstraction" (Spolsky)** — REFUTED. Runtime phenomenon, not a signature phenomenon; nothing
  leaked because nothing was hidden. It also smuggles in an inevitability excuse ("All non-trivial
  abstractions… are leaky") that this avoidable, fixable error does not deserve.
- **"Abstraction inversion"** — REFUTED. Near-opposite mechanism (too-high interface withholding
  primitives).
- **"Speculative generality"** — REFUTED. Opposite defect (too much unused generality for an imagined
  future). Likely wrong turn in review; flag it if someone reaches for it.
- **"Overexposure" (Ousterhout §5.7)** — near-miss; it concerns rarely-used *features of the API*, not
  a foreign mechanism.
- **"Pass-through methods" (Ousterhout §7.1)** — weak fit. §7.5 "Pass-through variables" is the closer
  §7 concept but its body text is UNVERIFIED here.

**Is there a specific term for a port that leaked its adapter's technology?** **No — REFUTED.** No
coined term of art was found in Cockburn's 2005 paper, the 2024/2025 book update pages, or Garrido de
Paz's canonical article. The closest are Cockburn's section heading **"Weak versus strong conformance
to the pattern"** and the 2005 paper's descriptive contrast, **interfaces "identified and discussed by
technology" vs. architected "by purpose rather than by technology."** Both are quotable; neither is a
named anti-pattern.

---

## 8. Sources

**Primary text read directly (fetched raw, extracted locally — quotes `[EXACT]`)**
- Cockburn, "The Hexagonal (Ports & Adapters) Architecture", HaT TR 2005.02, 2005-09-04 — <https://alistair.cockburn.us/hexagonal-architecture/>
- Cockburn & Garrido de Paz, *Hexagonal Architecture Explained*, v1.1b update pages (194 pp., ISBN 979-8-9985862-0-0) — <https://alistaircockburn.com/hexarch%20v1.1b%20DIFFS%2020250420-1012%20paper+epub.docx.pdf>
- Garrido de Paz, "Ports and Adapters Pattern (Hexagonal Architecture)", 2018-08-29 — <https://jmgarridopaz.github.io/content/hexagonalarchitecture.html>
- yt-dlp, `yt_dlp/extractor/common.py` and `_extractors.py` @ `master` — <https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/common.py>
- Parnas, CACM 15(12), Dec 1972, 1053–1058 — <https://cw.fel.cvut.cz/old/_media/courses/a4m33sep/materialy/architecture_and_design/01-article_original_de_parnas.pdf>
- Martin, "The Dependency Inversion Principle", C++ Report 1996 — <https://www.cs.utexas.edu/~downing/papers/DIP-1996.pdf>
- Martin, "The Interface Segregation Principle", C++ Report 1996 — <https://www.cs.utexas.edu/~downing/papers/ISP-1996.pdf>
- Fowler, "ContractTest", 2011-01-12 (rev. 2018-01-01) — <https://martinfowler.com/bliki/ContractTest.html>
- Robinson, "Consumer-Driven Contracts", 2006-06-12 — <https://martinfowler.com/articles/consumerDrivenContracts.html>

**Reached via summarizing extractor or third-party reproduction (`[SUBSTANCE]`)**
- Ousterhout, *A Philosophy of Software Design*, 2nd ed., 2021 — official page <https://web.stanford.edu/~ouster/cgi-bin/aposd.php>; 2e reproduction `github.com/yingang/aposd2e-zh`; 1e PDF `milkov.tech/assets/psd.pdf`; Ousterhout's own `github.com/johnousterhout/aposd-vs-clean-code`
- Spolsky, "The Law of Leaky Abstractions", 2002-11-11 — <https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/>
- Fowler, *Refactoring* — Rule of Three via <https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming)> and <https://eoinnoble.com/posts/origins-of-the-rule-of-three/>; Speculative Generality via <https://www.informit.com/articles/article.aspx?p=2952392&seqNum=15>
- Fowler, "Separated Interface", P of EAA — <https://martinfowler.com/eaaCatalog/separatedInterface.html>
- Metz, "The Wrong Abstraction", 2016-01-20 — <https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction>
- Wikipedia, "Leaky abstraction" / "Abstraction inversion"
- Rollup <https://rollupjs.org/plugin-development/> · Rolldown <https://rolldown.rs/apis/plugin-api> · Vite <https://vite.dev/guide/api-plugin> · ESLint <https://eslint.org/docs/latest/extend/custom-rules> · webpack <https://webpack.js.org/contribute/writing-a-plugin/> · Babel <https://babeljs.io/docs/babel-helper-plugin-utils>

**Not reached — recorded as gaps**
- *A Philosophy of Software Design* 2e publisher text (Ch. 4/5/7 body wording rests on an edition-provenance argument; §7.5 "Pass-through variables" body **UNVERIFIED**)
- *Hexagonal Architecture Explained* full book text (only the free v1.1b update pages)
- *Agile Software Development, PPP* (2002) — "clients own the interfaces" **UNVERIFIED**
- *Refactoring* book text — Rule of Three page number and 2e survival **UNVERIFIED**
- *P of EAA* book chapter — Separated Interface "client's package" discussion **UNVERIFIED**
- ACM DL DOI for Parnas 1972 — not fetched, not asserted
- Babel official plugin-development docs — **do not exist** (verified by enumerating `babel/website` `docs/`)
