# TDD Methodology (Beck)

The core process, philosophy, and strategic patterns from Beck's Part III pattern catalog (Ch 25-28, 32).

## The Two Rules

1. Write new code only if an automated test has failed
2. Eliminate duplication

These generate all of TDD's technical and social implications.

## The Cycle: Red/Green/Refactor

1. **Red** — Write a little test that doesn't work (and perhaps doesn't even compile)
2. **Green** — Make the test work quickly, committing whatever sins necessary
3. **Refactor** — Eliminate all duplication created in merely getting the test to work

"First we'll solve the 'that works' part. Then we'll solve the 'clean code' part."

## Three Strategies for Getting to Green

| Strategy | When to use | Risk |
|----------|-------------|------|
| **Fake It** | Default. Return a constant, gradually replace with variables | Low risk — always green |
| **Obvious Implementation** | When you're confident. Type the real code | Higher risk — demands perfection |
| **Triangulation** | When completely unsure how to refactor. Add a second example to force generalization | Conservative — "I only use it when I'm really, really unsure" |

**Shifting gears:** "When everything is going smoothly, I put in Obvious Implementation after Obvious Implementation. As soon as I get an unexpected red bar, I back up, shift to faking implementations, and refactor to the right code."

## Strategic Patterns

### Test List (Ch 25)

Before you begin, write a list of all tests you know you'll need. "Conservative mountain climbers have a rule that of your four hands and feet, three must be attached at any one time. The pure form of TDD, wherein you are never more than one change away from a green bar, is like that three-out-of-four rule."

Don't implement all tests at once — if you have ten broken tests, you're too far from green.

### Test First (Ch 25)

"You won't test after. Your goal as a programmer is running functionality." Test-first inverts the stress/testing death spiral into a virtuous cycle.

### Assert First (Ch 25)

Start writing the test from the assertion backward. "Where should you start writing a test? With the asserts that will pass when it is done." This has a powerful simplifying effect — you solve "what's the right answer?" and "how do I check?" before solving all other problems.

### Test Data (Ch 25)

Use data that makes tests easy to read. "If there is a difference in the data, it should be meaningful." Never use the same constant for two different purposes (use 3 + 4, not 2 + 2).

### Evident Data (Ch 25)

Include expected and actual results in the test itself. Make the relationship between inputs and outputs apparent. `assertEquals(new Note(100 / 2 * (1 - 0.015), "GBP"), result)` is better than `assertEquals(new Note(49.25, "GBP"), result)` because you can see the calculation.

### One Step Test (Ch 26)

"Pick a test that will teach you something and that you are confident you can implement." Programs grow from known to unknown — neither purely top-down nor bottom-up.

### Starter Test (Ch 26)

Start with a variant that doesn't do anything. "The first question you have to ask with a new operation is, 'Where does it belong?'" A realistic test leaves you solving too many problems at once.

### Learning Test (Ch 26)

When using a new API for the first time, write a test that verifies it works as expected. When new releases arrive, run the Learning Tests first.

### Regression Test (Ch 26)

When a defect is reported, write the smallest possible test that fails. "Regression tests are tests that, with perfect foreknowledge, you would have written when coding originally."

### Another Test (Ch 26)

When tangential ideas arise, add a test to the list and stay on track.

### Break / Do Over (Ch 26)

When stuck, take a break. When truly lost, throw away the code and start over. "Dave Ungar calls this his Shower Methodology."

### Broken Test (Ch 27)

When programming solo, leave the last test broken as a bookmark. "When you come back, you have an obvious place to start."

### Clean Check-in (Ch 27)

When programming in a team, always check in with all tests passing.

## The Courage/Fear Dynamic (Preface)

"Test-driven development is a way of managing fear during programming." Not fear in a bad way, but legitimate uncertainty. Tests are like ratchet teeth: "the tougher the programming problem, the less ground that each test should cover."

Fear makes you tentative, uncommunicative, and avoidant of feedback. TDD inverts this:

- Instead of being tentative → begin learning concretely
- Instead of clamming up → communicate more clearly
- Instead of avoiding feedback → search out concrete feedback

## The Stress/Testing Loop (Ch 25)

Without TDD (death spiral — positive feedback loop, even number of negative connections):

```
Stress ──⊖──→ Testing ──⊖──→ Errors ────→ Stress
  ↑                                          │
  └──────────────────────────────────────────┘
```

With TDD (virtuous cycle — replace "Testing" with "Automated Testing"):

```
Stress ──→ Run Tests ──→ Green Bar ──→ Confidence ──⊖──→ Stress
                                                          │
  ↑                                                       │
  └───────────────────────────────────────────────────────┘
```

"Tests are the Programmer's Stone, transmuting fear into boredom."

### Fatigue/Judgment Loop (Ch 26)

```
Fatigue ──⊖──→ Judgment ──⊖──→ Fatigue
```

"You're getting tired, so you're less capable of realizing that you're tired." Break the loop with outside elements: water bottle (hours), commitments (days), weekends (weeks), vacation (years).

## Isolated Tests (Ch 25)

Tests should not affect each other. "If I had one test broken, I wanted one problem. If I had two tests broken, I wanted two problems." Isolation encourages composing solutions from "many highly cohesive, loosely coupled objects."

## Step Size Control (Ch 32)

"You should be able to do either" — tiny steps or large leaps. The tendency over time is toward smaller steps. But: "TDD is not about taking teeny-tiny steps, it's about being able to take teeny-tiny steps."

## When to Test (Ch 32)

"Write tests until fear is transformed into boredom." Test: conditionals, loops, operations, polymorphism — but only those you write. "TDD's view of testing is pragmatic. If our knowledge of the implementation gives us confidence even without a test, then we will not write that test."

## Test Quality Signals (Ch 32)

Tests that suggest design problems:

- **Long setup code** → objects are too big, need splitting
- **Setup duplication** → too many objects too tightly intertwined
- **Long running tests** → testing bits and pieces is hard (design problem). "The equivalent of 9.8 m/s² is the ten-minute test suite"
- **Fragile tests** → one part of the app surprisingly affects another

## TDD and Frameworks (Ch 32)

"By not considering the future of your code, you make your code much more likely to be adaptable in the future." Features go in one at a time; duplication gets eliminated; the Open/Closed Principle is "gradually satisfied, and for precisely those kinds of variation that occur in practice."

## How TDD Works (Ch 32)

1. **Reduced defects** — sooner found, cheaper to fix
2. **Shortened feedback loop** — design decisions get feedback in seconds, not weeks
3. **Attractor toward correctness** — "Code is more likely to change for the better over time instead of for the worse"

"One of the ironies of TDD is that it isn't a testing technique. It's an analysis technique, a design technique, really a technique for structuring all the activities of development."

## Rapid Unhurriedness (Fowler, Afterword)

Martin Fowler's key observation: TDD produces "rapid unhurriedness" — progress that feels unhurried but is actually fast. "I remember trying to keep several balls in the air at once, any lapse of concentration and everything would come tumbling down. Test-driven development helps reduce that feeling."

The mechanism: TDD decomposes programming into **monological modes** — each focused on one concern:

- **Adding features test-first** — "I'm not worried about design, I'm just trying to get a test to pass"
- **Refactoring** — "I'm not worried about adding function, I'm just worried about getting the right design"
- **Pattern copying** — "I'm just adapting the pattern, not thinking about the problem"

"The combination of monological modes and switching gives you the benefits of focus and lowers the stress on the brain without the monotony of the assembly line."
