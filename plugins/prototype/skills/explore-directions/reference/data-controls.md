# Data controls

On the HTML mockup substrate, the page opens with seeded synthetic data and carries a small bar of
data controls, so the person can see each variant full, empty and back again without asking for a
new build. The bar is harness chrome, like the switcher and the control panel: neutral, unbranded,
no project tokens, and not part of the design being judged.

## Seed, clear and reset

Every mockup carries all three. Each acts on the one shared data set, so every variant changes at
once and the data stays the control variable.

| Control | What it does |
|---|---|
| Seed | Adds more synthetic records, generated from the same definition as the opening set, so the person can push a variant to volume: two buttons such as "Seed 10" and "Seed 100" when volume is in question, one otherwise |
| Clear | Removes every record, so each variant shows how it handles having none |
| Reset | Restores the opening seeded set exactly as the page first loaded it; this is the clean state the [clean-state proof](../../../context/discipline.md#clean-state-proof-and-check-list) starts from |

Rules:

- **No new data set.** Seed generates from the existing definition and Clear empties it; neither
  adds a set beside the ordinary and worst-content ones. When the switcher shows the worst content,
  the three controls act on that set, and Reset restores it as defined.
- **States still derive.** Every `data-screen-state` block renders from the data as it stands
  after a press, never from a copy taken at load.
- **Memory only.** The controls change in-memory data; reloading the page is the same as Reset.
- **No test ids.** The bar's controls carry no `data-testid`, so the copy-out terminator's
  test-id list holds only the design's own elements.

## Pagination, filter and sort

Add these only when a variant renders a list: rows, cards, items or any repeated record. A screen
with no list gets no toggles. Name the list in the plan line, so whoever reads the plan knows the
toggles are coming.

Each is a toggle on the bar that turns that behavior on or off in every variant at once, off when
the page opens. Every variant implements the behavior in its own structure (a table pages one way,
a card column another), and each acts on the data shown, never a copy, so a Seed or Clear shows
through it. A variant whose primary affordance is filtering or sorting keeps it on regardless of
the toggle: the step 2 must-differ rows still hold.

## Placement

Top-left, fixed, clear of the switcher's bottom-center bar and the control panel's top-right
corner. When a variant occupies the top-left, move the bar to the left edge, centered vertically,
rather than shrinking it.

## On the real stack

The page's own data loading is the source, and every write is stubbed, so the bar does not seed or
clear the app's records. Drive the real page to its full, empty and long-list cases the way
[worst content](switcher.md#worst-content) says.
