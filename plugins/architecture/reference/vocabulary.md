# Module-design vocabulary

An architecture finding names an architectural idea with one of the eight terms below, with the
meaning given here. Scan agents, report cards and interview turns all hold to this, so two findings
that say "seam" mean the same thing. A near-synonym makes the reader ask whether a second idea is
meant. Domain nouns come from the project's own glossary.

Basis, by term:

- Module, interface, implementation and depth (deep and shallow modules): John Ousterhout, *A
  Philosophy of Software Design*; his notes on modular design state the goal as maximizing
  functionality over interface complexity ([Stanford CS190, Modular Design](https://web.stanford.edu/~ouster/cgi-bin/cs190-winter18/lecture.php?topic=modularDesign)).
- Seam: Michael Feathers, *Working Effectively with Legacy Code*, ch. 4: "A seam is a place where
  you can alter behavior in your program without editing in that place." That a module's interface
  sits wherever its seam sits is our narrowing.
- Adapter: Alistair Cockburn's ports and adapters (hexagonal architecture), where an adapter
  converts between a port's API and what an outside device or system needs. We use the narrower
  sense of the code plugged in at a seam.
- Leverage and locality as the two things depth produces, the deletion test and the two-adapter
  check: Matt Pocock, `codebase-design` in
  [mattpocock/skills](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/codebase-design);
  our record:
  [`docs/upstream/mattpocock-skills.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/upstream/mattpocock-skills.md).

The examples below use one running case: tax calculation in a billing system.

## Naming the parts

**Module**: whatever a finding is about, at whatever size. `parseInvoiceDate()` is a module, so is
the `TaxCalculator` class, so is the `billing` package, and so is "export an invoice" taken from the
button down to the database. Each has two sides, the interface callers see and the implementation
they do not. Not: service, component, unit.

**Interface**: everything a caller has to get right to use the module, which comes down to three
questions the caller asks:

- What happens when it goes wrong, and how long will it take? Its failure modes and its speed.
- What must stay true, and in what order do I call it? Its invariants and its call sequence.
- What do I hand over and get back? Its types, plus any configuration that must exist first.

Not: signature or API, and not the public methods of a class or the TypeScript `interface`
keyword. Each of those answers only the last question.

**Implementation**: the lines and logic a module carries. Two questions keep it apart from an
adapter. How much code is there? That measures the implementation. How many calls does the slot
define? That measures the adapter. `DictTaxRates` answers forty lines and twenty calls;
`ElasticInvoiceIndex` answers thousands of lines and three calls. A sentence about what plugs into a
seam says adapter; a sentence about the code itself says implementation.

**Seam**: a placement decision, made before anyone decides what goes on either side: the spot where
one adapter comes out and another goes in with no edit at that spot (Feathers' sense). In the
running example it is the `TaxRates` port: production plugs in the rates-service client, tests plug
in `DictTaxRates`. A module's interface sits wherever its seam sits. Not: boundary, a word
domain-driven design already spends on bounded contexts.

Every seam has an **enabling point**, the place where the choice of adapter is made (Feathers,
same chapter). Here it is the argument through which `TaxCalculator` receives its `TaxRates`. A
spot with no enabling point is not a seam: nothing can be swapped there without an edit.

This is the module-design sense, the only one an architecture finding uses. A project may give
the word other senses in its own documents; a finding never means those.

**Adapter**: the code plugged in at a seam. It is named for the slot it fills (the rates-service
adapter, the dictionary adapter), not for the work it does inside. Not: the Gang of Four Adapter
pattern, whose intent is to "convert the interface of a class into another interface clients
expect" (Gamma, Helm, Johnson and Vlissides, *Design Patterns*, 1994). An adapter here may convert
nothing.

## Judging a module

**Depth**: what a caller gets back for what the interface makes it learn. **Deep** describes a module
with a small interface over large behavior; **shallow** describes one whose interface is about
the size of its implementation. Not: dividing implementation lines by interface lines, a score
that padding the implementation would raise.

**Leverage**: the callers' share of depth. Once `TaxCalculator.quote(order)` hides the rate tables,
rounding and exemptions, the checkout page, the invoice export and the refund job each make one
call, and a single test suite covers what all three rely on.

**Locality**: the maintainers' share of depth. When a rounding defect is reported, the fix, the test
that proves it, and the understanding of how rounding works all sit inside `TaxCalculator`, and none
of the three callers changes.

## How the terms relate

| Term | Relation |
|---|---|
| Module | has one interface, no more |
| Seam | is the location of a module's interface |
| Adapter | occupies a seam, fulfilling its interface |
| Depth | belongs to a module and is judged against its interface |
| Leverage, locality | are what depth produces, for callers and maintainers respectively |

## Architecture styles

A style is a rule for where a system's modules and seams go. It adds no term to the eight above,
and a finding about a styled codebase still uses them. Two styles by name:

- **Modular monolith**: one deployment unit made of modules, each independent, holding everything
  one business area needs, and reached only through a defined interface (Kamil Grzybek,
  [Modular Monolith: A Primer](https://www.kamilgrzybek.com/blog/posts/modular-monolith-primer)).
- **Vertical slice**: one module per request or feature, grouping its concerns from front end to
  back: "Minimize coupling between slices, and maximize coupling in a slice" (Jimmy Bogard,
  [Vertical Slice Architecture](https://www.jimmybogard.com/vertical-slice-architecture/), 2018).

Which style a repository follows is its own decision, read from its standards
(`/architecture:improve conventions` finds them), never assumed.

## Checks

- **Two-adapter check.** Before adding a seam, name both adapters that will plug into it, usually a
  production one and a test one. If only one can be named, the seam is speculation and stays out.
- **Testing check.** A test is one more caller, so it uses the interface and nothing behind it.
  When a test can only be written by reaching past the interface, take that as evidence the module
  is cut in the wrong place.
- **Internal parts do not count.** Depth is measured where callers stand. `TaxCalculator` may be
  assembled from a dozen small, swappable functions, with **internal** seams that only its tests touch.
  Those stay private; only the **external** seam, the interface, enters the judgment.
- **The deletion test.** Ask what each caller would have to write if the module were removed. A
  direct call to whatever the module wrapped means it only forwarded calls. The same logic, copied
  into every caller, means it was doing real work. A module that only forwards calls has three
  fixes: delete it so callers call what it wrapped, move work between it and the module it wraps
  so each has a distinct job, or merge the two into one deeper module (Ousterhout, *A Philosophy
  of Software Design*, §7.1). A scan records the result as `concentrates` when removing the module
  gathers logic into fewer places (it only forwarded calls, or several shallow modules fold into one
  deep one), a candidate, or `moves` when the logic would be copied into every caller, a module that
  earns its keep and is not a candidate.
- **Count the edits one change forces.** Suppose invoice lines gain an exemption code. If
  `TaxCalculator`'s rate step, its rounding step and its receipt step each need an edit, each step
  reads the line layout for itself: the code was cut along the sequence of the pipeline, not along
  who is responsible for the layout (Ousterhout calls this temporal decomposition). Give the layout
  one owning module and have the steps call it. A step's place in the sequence, first or last, is
  no reason to keep it outside that module.
