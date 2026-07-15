# Refactoring Under Test

Beck's refactoring patterns (Ch 31) and design patterns (Ch 30) used during the refactoring step of TDD, plus Khorikov's refactoring toward valuable tests (Ch 7 CRM example).

## Refactoring in TDD Context

"In TDD, the circumstances we care about are the tests that are already passing. So we can replace constants with variables and call this a refactoring, because it doesn't change the set of tests that pass."

This "observational equivalence" places a burden on you to have enough tests. "It's no excuse to say, 'I knew there was a problem, but the tests all passed so I checked the code in.' Write more tests."

## Refactoring Patterns

### Reconcile Differences

**Problem:** Two similar pieces of code exist.
**Solution:** Gradually bring them closer. Unify only when absolutely identical. Works at all scales: loops, conditionals, methods, classes. "Think about how the last step could be trivial, then work backward."

### Isolate Change

**Problem:** Need to change one part of a multi-part method.
**Solution:** First isolate it (Extract Method, Extract Object), then change it. "The picture is surgery: the entire patient except the part to be operated on is draped."

### Migrate Data

**Problem:** Move from one data representation to another.
**Solution:** Temporarily duplicate the data. Internal-to-external: add new variable → set it everywhere → use it everywhere → delete old → change API. External-to-internal (API first): add parameter → translate internally → delete old parameter → replace internal uses → delete old format.

### Extract Method

The most common refactoring. Turn a piece of a long method into its own method. "I use Extract Method when I'm trying to understand complicated code."

### Inline Method

Replace a method call with its body. "In the heat of battle I'll occasionally get caught up in my own cleverness. Inline Method is a way to reel myself back in."

### Extract Interface

Introduce an interface when you need a second implementation. "Perhaps the interface should be called File and the class DiskFile."

### Move Method

Move a method to the class where it belongs. "Any time I see more than one message sent to another object, I get suspicious." Three properties: easy to spot, quick and safe mechanics, often enlightening results.

### Method Object

Turn a complicated method into an object. All parameters become constructor args, local variables become instance variables, body goes in `run()`. Useful when Extract Method doesn't work due to too many temps and parameters.

### One to Many (Ch 28)

Implement for a single item first, then generalize to collections. Add the collection parameter alongside the single item, switch to using the collection, delete the single item.

## Design Patterns Used in TDD

Beck catalogues which design patterns appear during test writing vs. refactoring:

| Pattern | Test Writing | Refactoring | Key idea |
|---------|:---:|:---:|---|
| **Command** | X | | Represent computation as an object with `run()` |
| **Value Object** | X | | Immutable objects — no aliasing problems. "Every operation returns a fresh object" |
| **Null Object** | | X | Replace null checks with a no-op implementation |
| **Template Method** | | X | Invariant sequence with specializable steps. "Best found through experience, not designed from the beginning" |
| **Pluggable Object** | | X | Replace spreading conditionals with polymorphism. "The second time you see a conditional, it is time to pull out Pluggable Object" |
| **Pluggable Selector** | | X | Dynamic method invocation via reflection. "Use only when cleaning up a straightforward situation" |
| **Factory Method** | X | X | Create objects via method instead of constructor. Adds indirection for flexibility |
| **Imposter** | X | X | New implementation of existing protocol. Null Object and Composite are both Imposters |
| **Composite** | X | X | Treat a collection like a single item. "TestSuites containing TestSuites, Drawings containing Drawings — none translate well from the world, but they all make the code simpler" |
| **Collecting Parameter** | X | X | Pass a parameter to aggregate results. TestResult is the canonical example |

### On Singleton

Beck's complete advice: "How do you provide global variables in languages without global variables? Don't. Your programs will thank you for taking the time to think about design instead."

---

## Khorikov's Refactoring Toward Valuable Tests (Ch 7)

While Beck focuses on refactoring *production code* safely under a test harness, Khorikov focuses on refactoring *both test and production code* to make the tests more valuable — splitting overcomplicated code into testable algorithms and humble controllers.

The core technique: use the **four types of code** (2x2 matrix of complexity vs collaborators) to identify overcomplicated code, then apply the **Humble Object pattern** to split it into domain model (unit-testable) and controllers (integration-testable).

Key patterns that emerge during this refactoring:

- **CanExecute/Execute** — keeps business logic validation in the domain model when the controller needs to make conditional decisions
- **Domain events** — tracks changes in the domain model for later conversion to out-of-process calls, keeping the domain free of external dependencies
- **Tell Don't Ask** — domain classes delegate to collaborators (`company.ChangeNumberOfEmployees(delta)`) rather than querying data and acting on it externally

For the full CRM 4-take refactoring example: [testable-architecture-khorikov.md](testable-architecture-khorikov.md)

### Synthesis: Beck and Khorikov on Refactoring

Both authors agree that refactoring is inseparable from testing — you can't have good tests without well-designed code, and you can't safely refactor without tests. Beck's patterns (Extract Method, Move Method, Method Object) are the *mechanics*. Khorikov's framework (four types of code, Humble Object, three-way trade-off) provides the *strategy* for deciding *what* to extract and *where* to move it.

Beck says: "I use Extract Method when I'm trying to understand complicated code." Khorikov says: use it when a class scores high on both dimensions of the 2x2 matrix — complexity AND collaborators. The two perspectives complement each other: Beck gives you the tool, Khorikov tells you when to reach for it.
