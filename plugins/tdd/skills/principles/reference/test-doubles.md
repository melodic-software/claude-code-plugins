# Test Doubles

Beck's patterns for testing objects that depend on expensive or complicated resources (Ch 27), plus Khorikov's mock/stub taxonomy, CQS connection, and five mocking best practices (Ch 5, 9).

## Mock Object

**Problem:** How do you test an object that relies on an expensive or complicated resource?

**Solution:** Create a fake version that answers constants.

```java
public void testOrderLookup() {
    Database db = new MockDatabase();
    db.expectQuery("select order_no from Order where cust_no is 123");
    db.returnResult(new String[] {"Order 2", "Order 3"});
    // ...
}
```

**Benefits beyond performance:**

- **Readability** — you can read the test end-to-end. With a real database of realistic data, "you have no idea why 14 is the right answer"
- **Design pressure** — Mock Objects "encourage you down the path of carefully considering the visibility of every object, reducing the coupling in your designs"

**Risk:** What if the Mock doesn't behave like the real object? Mitigate by having tests that run against both the Mock and real object.

**Design implication:** You can't easily store expensive resources in global variables (Singletons). Beck and Arnoldi tried to make a global Exchange work with mocks and eventually decided to just pass the Exchange as a parameter. "We thought we would have to modify hundreds of methods. In the end, we added a parameter to ten or fifteen methods, and cleaned up other aspects of the design along the way."

## Self Shunt

**Problem:** How do you test that one object communicates correctly with another?

**Solution:** Have the object under test communicate with the test case itself (the test case implements the expected interface).

```python
def testNotification(self):
    self.count = 0
    result = TestResult()
    result.addListener(self)
    WasRun("testMethod").run(result)
    assert 1 == self.count

def startTest(self):
    self.count = self.count + 1
```

The test case *is* the mock. "Tests written with Self Shunt tend to read better" — you can see both values in one place. May require Extract Interface. In Java, you'll implement "all sorts of bizarre interfaces."

## Log String

**Problem:** How do you test that messages are called in the correct sequence?

**Solution:** Append to a string when each message is called.

```python
def testTemplateMethod(self):
    test = WasRun("testMethod")
    result = TestResult()
    test.run(result)
    assert("setUp testMethod tearDown " == test.log)
```

"Particularly useful when implementing Observer and you expect notifications in a certain order." Works well combined with Self Shunt. If order doesn't matter, use a set instead of a string.

## Crash Test Dummy

**Problem:** How do you test error code that is unlikely to be invoked?

**Solution:** Create a special object that throws an exception instead of doing real work.

```java
public void testFileSystemError() {
    File f = new File("foo") {
        public boolean createNewFile() throws IOException {
            throw new IOException();
        }
    };
    try {
        saveAs(f);
        fail();
    } catch (IOException e) { }
}
```

"Like a Mock Object, except you don't need to mock up the whole object." Java's anonymous inner classes let you override just the one method, right in your test.

Beck's principle: "Code that isn't tested doesn't work. This seems to be the safe assumption."

---

## Khorikov's Mock/Stub Taxonomy (Ch 5)

All five test double types collapse into two categories based on their role:

```
Test double
├── Mock (mock, spy)         → emulate and examine OUTGOING interactions (commands)
└── Stub (stub, dummy, fake) → emulate INCOMING interactions (queries)
```

This maps directly to **Command Query Separation (CQS)**:

| CQS | Side effects? | Returns? | Test double |
|-----|--------------|----------|-------------|
| **Command** | Yes | void | Mock |
| **Query** | No | Value | Stub |

**Critical rule:** never assert interactions with stubs. A stub call is a means to produce the end result, not the end result itself. Verifying it is overspecification.

> "Asserting interactions with stubs is a common anti-pattern that leads to fragile tests." — Khorikov

When a single double serves both roles (provides canned answers AND is verified), it's still called a mock — the mock role is the more important fact.

## Five Mocking Best Practices (Khorikov, Ch 9)

1. **Mock only unmanaged dependencies** — managed deps (database) use real instances; unmanaged deps (message bus, SMTP) get mocked
2. **Verify interactions at system edges** — mock the last type in the chain (e.g., `IBus` not `IMessageBus`). Maximizes protection against regressions and resistance to refactoring
3. **Mocks in integration tests only** — domain model tests are unit tests with no mocks. Controllers are integration tests — that's where mocks belong
4. **Multiple mocks per test are fine** — the "one mock per test" guideline is a misconception. The number depends on the number of unmanaged dependencies in the operation
5. **Verify both expected AND unexpected calls** — use `Times.Once` + `VerifyNoOtherCalls()` to ensure backward compatibility in both directions

**Spies are superior to mocks at system edges** — handwritten mocks with fluent assertion interfaces provide reusable, readable verification and don't rely on production code for assertions.

## SDK-Style Interfaces Over Generic Fetchers

> Editorial synthesis, not from either source book.

At system boundaries, prefer specific functions per external operation over one generic function with conditional logic:

```typescript
// GOOD: Each function independently mockable, one shape per mock
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mock requires conditional logic, unclear which endpoints a test exercises
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

SDK approach: each mock returns one specific shape, no conditional logic in test setup, type safety per endpoint, easy to see which endpoints a test exercises.

## Synthesis: Beck vs Khorikov

Beck focuses on the *mechanics* of test doubles (how to build them). Khorikov focuses on the *policy* (when to use which kind, and what to verify). They agree on the core principle: mocks exist to verify interactions with external dependencies, not to isolate classes from each other. Beck's design pressure from mocks ("pass the Exchange as a parameter") aligns with Khorikov's stance that the need to mock reveals coupling problems.

**Key difference:** Beck's Self Shunt and Log String patterns verify intra-system interactions (the test case implements the interface). Khorikov explicitly warns against this for domain classes — inter-domain interactions are implementation details. Use Beck's patterns for verifying *external-facing* communication; use Khorikov's taxonomy to decide whether to mock at all.

For full details: [observable-behavior-khorikov.md](observable-behavior-khorikov.md) (mock/stub taxonomy, CQS), [integration-testing-khorikov.md](integration-testing-khorikov.md) (managed vs unmanaged, mocking best practices).

## Replace, Don't Layer (Ousterhout)

> Editorial synthesis — draws on Ousterhout, not from either source book.

When merging shallow modules behind a deeper interface ("deepening" per Ousterhout's *A Philosophy of Software Design*), the test surface moves to the deepened interface. The discipline: write new tests at the deepened interface, delete the old shallow-module tests, assert observable outcomes not internal state. If the `architecture` plugin is installed, `/architecture:improve` covers the wider deepening workflow ("Replace, don't layer"); when it is absent, the summary above is the full guidance.

This complements Khorikov's "observable behavior" principle: the deepened interface IS the observable behavior surface, so tests behind it are implementation-detail tests by definition.
