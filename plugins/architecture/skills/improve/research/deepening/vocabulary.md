# Deepening Vocabulary

When the `deepening` lens names an architectural idea, it uses one of the eight terms below, with the
meaning given here. Scan agents, report cards and interview turns all hold to this, so two findings
that say "seam" mean the same thing. A near-synonym makes the reader ask whether a second idea is
meant.

Basis: John Ousterhout, *A Philosophy of Software Design*, with "seam" taken from Michael Feathers,
narrowed here for review work. The examples below use one running case: tax calculation in a
billing system.

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

**Adapter**: the code plugged in at a seam. It is named for the slot it fills (the rates-service
adapter, the dictionary adapter), not for the work it does inside.

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
  into every caller, means it was doing real work.
- **Run order is not a reason to split.** Modules cut along the order things happen in (one to load
  the invoice, one to compute tax, one to save the result) tend to share the same knowledge, here the
  layout of an invoice line, so a change to that layout touches all three. Ousterhout calls this
  temporal decomposition. Group code by the knowledge it keeps to itself, even when parts of it run
  at different times.
