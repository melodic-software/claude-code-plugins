# Fathom guide: define success measures and build evaluations

Synthetic source page for the attribution golden set. Fathom is a fictional model platform
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/fathom/docs/evaluate/develop-tests`.

## Define your success measures

Good success measures are specific, measurable, achievable and relevant. Decide them before you
write a single test, so the tests answer a question you already asked.

### Measures to consider

Most use cases need a mix of measures. Task-specific numbers include edit distance, token overlap
and calibration error. General numbers include hit rate and false-alarm rate. Operational numbers
include time to first token, in milliseconds, and availability, as a percentage.

Methods you can run include a side-by-side comparison against a baseline version, signals drawn
from user behavior such as how often a session reaches its goal, and a review of corner cases that
counts the share handled cleanly. Where a number is not enough, add rating scales or expert scoring
guides, always together with numbers.

## Build evaluations

### Design principles

1. Match the real work: design evaluations that mirror your real task distribution, and remember
   the corner cases. Corner cases might include input data that is missing or unrelated, input
   that is far too long, (for chat) hostile or off-topic user input, and cases so unclear that even
   people would disagree on the answer.
2. Grade by script where you can: shape questions so that grading can be automated, for example
   multiple choice, exact match, code-graded or model-graded. Often, clever design is all that
   separates you from a scriptable eval.
3. Prefer many cases to perfect ones: a larger set of questions graded by script with slightly
   weaker signal beats a small set graded carefully by hand.
