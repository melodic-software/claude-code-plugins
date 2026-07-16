# The Money Example (Beck, Part I)

Beck's first worked example: building multi-currency arithmetic test-first across 17 chapters. This is where he demonstrates TDD's core rhythm on a real problem.

## The Problem

A bond portfolio system needs multi-currency support. Two behaviors needed:

1. Multiply an amount by a number (price × shares)
2. Add amounts in different currencies with exchange rates

Beck starts with a **to-do list** — a running inventory of tests to write, maintained throughout. Items are added when thoughts arise, crossed off when done, bolded when in-progress. This keeps focus narrow.

## The TDD Cycle (stated in Ch 2)

1. **Write a test.** Think about how the operation should *look* from the outside. Invent the interface you wish you had.
2. **Make it run.** Get green as fast as possible — "quick green excuses all sins. But only for a moment."
3. **Make it right.** Remove duplication. Step back onto the straight and narrow.

"First we'll solve the 'that works' part. Then we'll solve the 'clean code' part. This is the opposite of architecture-driven development."

## Three Strategies for Getting to Green (Ch 2, 3)

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| **Fake It** | Return a constant, then gradually replace constants with variables | Default strategy — safest |
| **Obvious Implementation** | Type in the real code directly | When you're confident — but back off to Fake It when you get an unexpected red bar |
| **Triangulation** | Only generalize when you have 2+ examples demanding it | When you're completely unsure how to refactor. "What axes of variability are you trying to support?" |

Beck commonly shifts between Fake It and Obvious Implementation: "When everything is going smoothly, I put in Obvious Implementation after Obvious Implementation. As soon as I get an unexpected red bar, I back up, shift to faking implementations, and refactor to the right code."

## Key Moves Demonstrated

### Dependency and Duplication (Ch 1)

"Dependency is the key problem in software development at all scales. If dependency is the problem, duplication is the symptom." Eliminating duplication eliminates dependency. The duplication isn't always between two code locations — it can be between the test data and the code data. `int amount = 10` in the code is duplication of `5 * 2` in the test.

### Value Objects (Ch 2-3)

Dollar becomes immutable — `times()` returns a new Dollar instead of mutating. "One of the constraints on Value Objects is that the values of the instance variables never change once they have been set in the constructor." This eliminates aliasing bugs. Implications: all operations return new objects, must implement `equals()`.

### Translating Feelings into Tests (Ch 2)

"The translation of a feeling (for example, disgust at side effects) into a test (for example, multiply the same Dollar twice) is a common theme of TDD. The longer I do this, the better able I am to translate my aesthetic judgments into tests."

### Copying to Get Green, Then Removing Duplication (Ch 5-6)

Beck deliberately copy-pastes Dollar to create Franc. "Stop. Hold on. I can hear the aesthetically inclined among you sneering. Remember, our cycle has different phases. The first three need to go by quickly. Speed trumps design, just for that brief moment." He then spends chapters 6-11 systematically eliminating the duplication — extracting Money superclass, unifying equals(), unifying times(), eventually eliminating the subclasses entirely.

### Factory Methods to Decouple (Ch 8)

`Money.dollar(5)` and `Money.franc(5)` hide concrete class construction. "We are now in a slightly better position. No client code knows that there is a subclass called Dollar. By decoupling the tests from the existence of the subclasses, we have given ourselves freedom to change inheritance without affecting any model code."

### Step Size Control (Ch 1, 9)

"TDD is not about taking teeny-tiny steps, it's about *being able* to take teeny-tiny steps. Would I code day-to-day with steps this small? No. But when things get the least bit weird, I'm glad I can."

Ch 9: "I'm feeling defensive again about taking such teeny-tiny steps. What I did just now was to work in larger steps and make a stupid mistake halfway through. I unwound a minute's worth of changes, shifted to a lower gear, and did it over with little steps."

### Ask the Computer, Don't Reason (Ch 10)

"I see this situation all the time — excellent software engineers spending 5 to 10 minutes reasoning about a question that the computer could answer in 15 seconds. Without the tests you have no choice, you have to reason. With the tests you can decide whether an experiment would answer the question faster."

### Back Out When Red (Ch 10)

When a change produces a red bar unexpectedly: "The conservative course is to back out the change so we're back to green. Then we can change the test for equals(), fix the implementation, and retry the original change."

### The Expression Metaphor (Ch 12)

The key design insight: treating monetary operations as *expressions* (like `(2 + 3) * 5`) rather than flat collections (wallet/bag). `Money` is atomic, `Sum` is compound, both implement `Expression`. A `Bank` reduces an `Expression` to a single currency. Beck puts reduction responsibility on Bank, not Expression: "I try to keep the objects at the heart as ignorant of the rest of the world as possible, so they stay flexible as long as possible."

### Polymorphism over Type Checking (Ch 13)

`instanceof` checks replaced with polymorphism by adding `reduce()` to the `Expression` interface. Both `Money` and `Sum` implement it. "Any time we are checking classes explicitly, we should be using polymorphism instead."

### Write the Test You Want, Then Back Off (Ch 15)

For the final mixed-currency test, Beck writes the ideal test first, realizes it won't compile, writes a more specific version to get going, then generalizes from the leaves back to the root.

## Part I Retrospective (Ch 17)

### Code Metrics

| | Functional | Test |
|---|---|---|
| Classes | 5 | 1 |
| Functions | 22 | 15 |
| Lines | 91 | 89 |
| Cyclomatic complexity | 1.04 | 1 |
| Lines/function | 4.1 | 5.9 |

"Roughly as many lines and functions in the test and functional code."

### The Power of Metaphor

"I really didn't expect the metaphor to be so powerful. A metaphor should just be a source of names, shouldn't it? Apparently not." The expression metaphor produced cleaner code than any of Beck's previous implementations using wallet/bag/vector metaphors.

### Three Surprises When Teaching TDD

1. The three approaches to getting green (Fake It, Triangulation, Obvious Implementation)
2. Removing duplication between test and code as the way to drive design
3. The ability to control the gap between tests — "increase traction when the road gets slippery and cruise faster when conditions are clear"

### Test Quality

- TDD should yield ~100% statement coverage
- Defect insertion (Jester) found only one survivable mutation: the faked `hashCode()` returning 0
- TDD tests don't replace performance, stress, or usability testing
- Coverage improves two ways: writing more tests AND simplifying the code (refactoring reduces paths to cover)
