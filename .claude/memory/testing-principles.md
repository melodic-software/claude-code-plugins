# Testing Principles and Best Practices

## Overview

This document provides language-agnostic testing principles and best practices for ensuring test suites remain maintainable, reliable, and valuable over time. These principles apply to all codebases regardless of language or framework.

## Core Testing Philosophy

**Tests are production code.** They deserve the same attention to quality, maintainability, and design as implementation code. Technical debt in tests compounds just as quickly as in production code and must be managed with equal rigor.

**Test behavior, not implementation.** The fundamental principle for maintainable tests is verifying **what a system does** (behavior) rather than **how it does it** (implementation). Tests that focus on behavior remain stable through refactoring; tests coupled to implementation details become brittle and expensive to maintain.

**Quality over quantity.** A test suite with 100% coverage of poorly designed tests provides false confidence while incurring massive maintenance burden. Prioritize well-designed tests of critical behaviors over achieving high coverage percentages.

## FIRST Principles

Every test should embody these five characteristics:

### Fast

- Tests should execute quickly to enable rapid feedback loops
- Unit tests should complete in milliseconds, not seconds
- Slow tests discourage running the suite frequently, reducing their value
- Optimize test speed by mocking expensive operations (database, network, file I/O)

### Isolated

- Each test must be independent of all other tests
- Test execution order should never matter
- One test's failure should not cause cascading failures in other tests
- Shared mutable state between tests is forbidden
- Use test-specific data, clean up after each test, avoid global state

### Repeatable

- Tests must produce consistent results every time they run
- Same code + same test = same result (pass or fail)
- Non-deterministic tests (flaky tests) are worse than no tests
- Eliminate time dependencies, random data, network calls, external service dependencies
- Use fixed seeds for randomness, mock time sources, control asynchronous operations

### Self-Validating

- Tests should automatically determine pass/fail without human intervention
- No manual inspection of logs, output files, or visual inspection required
- Clear assertions that express expected behavior
- Automated CI/CD integration depends on self-validating tests

### Timely

- Write tests close in time to the code they validate
- Test-driven development (TDD): Write tests before implementation
- Behavior-driven development (BDD): Write tests alongside feature specifications
- Tests should not be an afterthought added long after implementation

## Test Structure: AAA Pattern

Structure each test using the Arrange-Act-Assert pattern for clarity and consistency:

### Arrange

- Set up test data and preconditions
- Initialize objects, configure mocks, prepare environment
- Establish the context in which the code under test will execute

### Act

- Execute the code under test
- Invoke the method, function, or operation being validated
- This should be a **single operation** - tests validating multiple operations should be split into separate tests

### Assert

- Verify the outcome matches expectations
- Check return values, state changes, side effects, exceptions
- Use clear, behavior-focused assertions

**Example structure (pseudocode):**

```text
test_createUser_withValidData_createsUserSuccessfully():
    # Arrange
    validUserData = buildValidUserData()
    userRepository = mockUserRepository()

    # Act
    result = userService.createUser(validUserData)

    # Assert
    assert result.success == true
    assert result.user.email == validUserData.email
    assert userRepository.saveCalled == true
```

## The Problem with Brittle Tests

**Brittle tests** are tests that fail when implementation details change despite unchanged behavior. They represent a critical anti-pattern that undermines test suite value.

### Why Brittle Tests Are Problematic

**Reduced developer productivity**: Developers must update numerous tests following legitimate refactoring. Instead of tests providing confidence, they become obstacles to improvement, discouraging the refactoring that keeps codebases healthy.

**False negatives and alarm fatigue**: When tests fail for reasons unrelated to actual behavioral regression, developers begin dismissing test results entirely. This causes genuine failures to go unnoticed, defeating the purpose of testing.

**Increased maintenance cost**: Brittle tests require constant updates. Research shows defects cost 10-100x more to fix in production than during initial development, yet brittle tests prevent engineers from confidently deploying changes.

**Test suite abandonment**: When maintaining tests requires more effort than maintaining implementation, teams disable or ignore tests, defeating their purpose entirely.

### Characteristics of Brittle Tests

**❌ Brittle Test Indicators:**

- Tests break when renaming private methods or internal variables
- Tests fail when refactoring implementation but not changing behavior
- Tests assert on internal class structure or method call sequences
- Tests depend on hardcoded external file paths, URLs, or resources
- Tests use exact string matching on error messages or log output
- Tests verify implementation details like database query structure
- Tests depend on specific execution timing or operation ordering
- Tests coupled to specific class names, package structures, or module organization

**✅ Resilient Test Indicators:**

- Tests verify behavior from user/consumer perspective
- Tests focus on public API contracts, not internal implementation
- Tests use role-based assertions (interfaces) not concrete types
- Tests isolate external dependencies through mocking/stubbing
- Tests use test data builders with dynamic resource management
- Tests assert on outcomes and state changes, not implementation steps
- Tests remain valid through refactoring that preserves behavior

### How to Avoid Brittle Tests

**Test at behavioral boundaries, not internal mechanisms:**

```text
# ❌ BRITTLE - Tests implementation details
test_processPayment_callsValidatorThenRepository():
    # Test knows too much about internal implementation
    assert validator.validate() called first
    assert repository.save() called second
    assert payment processor sequence matches [validate, save, notify]

# ✅ RESILIENT - Tests behavior
test_processPayment_withValidCard_completesSuccessfully():
    # Test verifies outcome, not implementation steps
    result = paymentService.processPayment(validCard, amount)
    assert result.success == true
    assert result.transactionId != null
```

**Avoid testing private methods directly:**

Private methods should be tested implicitly through their public API. If a private method seems to require direct testing, consider whether it should be:

- A public method on the current class
- A separate class with public methods
- Tested sufficiently through public method tests

**Use role-based and behavior-based assertions:**

```text
# ❌ BRITTLE - Asserts on concrete types
assert type(result) == ConcreteUserClass
assert result.internalStateVariable == "expected"

# ✅ RESILIENT - Asserts on behavior and contracts
assert result implements UserInterface
assert result.getEmail() == expectedEmail
assert result.isActive() == true
```

**Avoid hardcoded paths to external files:**

```text
# ❌ BRITTLE - Hardcoded absolute path
testData = readFile("C:/Users/Developer/test-data/users.json")
configFile = "/opt/app/test-config.yaml"

# ❌ BRITTLE - Relative paths that break when test structure changes
testData = readFile("../../../test-data/users.json")

# ✅ RESILIENT - Use test resource mechanisms
testData = readResourceFile("test-data/users.json")  # Framework-managed
configFile = createTempFile(testConfig)  # Temporary file

# ✅ RESILIENT - Inject resource paths
testData = readFile(getTestResourcePath("users.json"))
```

Hardcoded file paths are brittle because:

- They break when directory structures change
- They fail on different machines (absolute paths)
- They depend on specific repository checkout locations
- They require manual resource management
- They couple tests to filesystem organization

**Separate test organization from code structure:**

While code organization often mirrors package/module structure, tests should organize around user behaviors and feature areas. A refactoring that moves code between modules shouldn't require reorganizing all associated tests.

## Test Isolation Strategies

Isolation ensures test failures indicate actual problems with the system under test, not side effects from other tests or environmental factors.

### Eliminate Shared Mutable State

Each test should start in a consistent, predictable state:

```text
# ❌ ANTI-PATTERN - Shared mutable state
class TestUserService:
    sharedUser = User("test@example.com")  # Shared across all tests

    test_updateUser():
        sharedUser.name = "Alice"
        # Next test gets mutated user!

# ✅ CORRECT - Fresh state per test
class TestUserService:
    setup():
        self.user = createTestUser()  # Fresh instance each test

    test_updateUser():
        self.user.name = "Alice"
        # Each test gets clean state
```

### Run Tests in Any Order

If tests only pass when run in a specific sequence, they have hidden dependencies:

- Randomly shuffle test execution order during development
- Most testing frameworks provide randomization plugins
- CI/CD should run tests in random order to catch order dependencies
- Use test framework hooks (setup/teardown) to ensure clean state

### Use Isolation at Appropriate Levels

**Unit tests**: Isolate the unit under test through mocking external dependencies (databases, APIs, file systems, network, other classes)

**Integration tests**: Isolate test data and external services from other concurrent tests. Use test databases, test-specific identifiers, transactions that rollback.

**End-to-end tests**: Isolate test users and data through explicit setup and cleanup. Use test-specific accounts, sandboxed environments, cleanup scripts.

### Clear Test Data Between Tests

```text
# ✅ Database isolation patterns
test_createUser():
    setup:
        beginTransaction()  # Start transaction

    execute:
        createUser(userData)

    teardown:
        rollbackTransaction()  # Cleanup automatically

# ✅ File system isolation
test_fileProcessing():
    setup:
        testDir = createTempDirectory()

    execute:
        processFiles(testDir)

    teardown:
        deleteTempDirectory(testDir)
```

## Deterministic Test Design

Non-deterministic tests (flaky tests) that sometimes pass and sometimes fail for the same code are worse than no tests. They erode confidence and waste debugging time.

### Eliminate Time-Dependent Logic

```text
# ❌ NON-DETERMINISTIC - Real time
test_cacheExpiration():
    cache.set("key", "value", ttl=1000ms)
    sleep(1100ms)  # Hope this is enough time!
    assert cache.get("key") == null

# ✅ DETERMINISTIC - Inject time
test_cacheExpiration():
    fakeTime = mockTimeSource()
    cache = Cache(timeSource=fakeTime)

    cache.set("key", "value", ttl=1000ms)
    fakeTime.advance(1001ms)  # Explicit time control
    assert cache.get("key") == null
```

**Avoid:**

- `sleep()` calls or timeout-based assertions
- System clock dependencies (`Date.now()`, `System.currentTimeMillis()`)
- "Eventually" assertions without deterministic synchronization
- Race conditions in asynchronous operations

**Instead:**

- Inject fake/mock time sources
- Use explicit event-based synchronization
- Use deterministic async control from testing frameworks
- Control asynchronous operations explicitly

### Control Random Number Generation

```text
# ❌ NON-DETERMINISTIC - Uncontrolled randomness
test_randomBehavior():
    result = processWithRandomness()
    # Different result each run!

# ✅ DETERMINISTIC - Seeded randomness
test_randomBehavior():
    random.seed(42)  # Fixed seed
    result = processWithRandomness()
    assert result == expectedForSeed42
```

Use seeded random number generators so the same seed always produces the same sequence. When bugs appear with random data, capture that specific seed in a regression test.

### Mock External Services and Dependencies

Network calls, external APIs, file systems, and system resources introduce non-determinism:

```text
# ❌ NON-DETERMINISTIC - Real external service
test_fetchUserData():
    userData = externalAPI.getUser(userId)
    # Fails if network down, API slow, API changed!

# ✅ DETERMINISTIC - Mocked service
test_fetchUserData():
    mockAPI = createMockAPI()
    mockAPI.whenCalled("getUser").thenReturn(expectedUserData)

    service = UserService(api=mockAPI)
    userData = service.fetchUser(userId)
    assert userData == expectedUserData
```

### Use Fixed, Reproducible Test Data

```text
# ❌ POTENTIALLY NON-DETERMINISTIC - Random data
test_userValidation():
    email = randomEmail()  # Different each run
    # Bug only appears with specific email format!

# ✅ DETERMINISTIC - Fixed or seeded data
test_userValidation():
    # Option 1: Fixed data
    email = "test@example.com"

    # Option 2: Seeded random
    random.seed(42)
    email = generateEmail(seed=42)
```

When using randomness to explore edge cases:

- Use fixed seeds to make failures reproducible
- When bugs appear, capture the seed in a regression test
- Consider parameterized tests with multiple seeds for coverage

## Test Doubles: Comprehensive Guide to Mocks, Stubs, Fakes, Spies, and Dummies

**Test doubles** are objects or functions that stand in for real components during testing, enabling isolated, controlled, and efficient testing by replacing dependencies that introduce complexity, cost, slowness, unpredictability, or external dependencies.

### The Five Types of Test Doubles

Test doubles exist on a **continuum** from purely structural placeholders (dummies) through increasingly sophisticated types that add functionality, observation capability, and verification (stubs, spies, fakes, mocks).

#### Dummies

**Purpose**: Satisfy syntactic requirements without being used

**Definition**: Objects passed around but never actually invoked; purely structural to fill parameter lists

**Use when**: Code requires parameters that will never be used in the test scenario

**Example**:

```text
# Function requires 3 parameters but test only uses first
function processOrder(order, logger, notifier):
    validateOrder(order)  # Only order is used

test_processOrder_validation():
    order = createTestOrder()
    dummyLogger = null  # Never called
    dummyNotifier = null  # Never called

    processOrder(order, dummyLogger, dummyNotifier)
```

**Key characteristic**: If a dummy is actually invoked during test execution, it indicates either a misunderstanding of the code or inappropriate test double selection.

#### Stubs

**Purpose**: Provide canned, predetermined responses to calls

**Definition**: Objects that hold predefined data and return it when called, without recording interactions

**Use for**: Simulating responses from dependencies when test focus is processing those responses

- Database queries returning test data
- External API calls returning predetermined responses
- File system operations returning fixed content
- Configuration services returning test settings

**Characteristics**:

- Return hardcoded values
- Do not record whether they were called
- Do not verify their own usage
- Naturally align with **state verification** (examining end results)

**Example**:

```text
# Stub provides predetermined response
test_userService_processesUserData():
    stubDatabase = createStub()
    stubDatabase.whenCalled("findUser").thenReturn(testUser)

    service = UserService(database=stubDatabase)
    result = service.processUser(userId)

    # Verify what service DID with the data, not how it called database
    assert result.isValid == true
    assert result.email == testUser.email
```

**Benefits**: Tests focus on code logic processing responses, not on request construction. Tests remain stable through refactoring of how requests are made.

#### Spies

**Purpose**: Provide predetermined responses PLUS record how they were called

**Definition**: Stubs that additionally record interaction metadata (call count, arguments, invocation order)

**Use for**: Testing code that interacts with dependencies in particular ways that should be verified

**Characteristics**:

- Combine stub functionality (canned responses) with observation (recording calls)
- Use "verify after running" pattern (record during execution, verify afterward)
- More flexible than mocks (don't require expectations upfront)
- Can wrap real objects, allowing partial mocking

**Example**:

```text
# Spy records interactions for later verification
test_userService_cachesResults():
    spyCache = createSpy()
    spyCache.whenCalled("get").thenReturn(null)  # Stub behavior

    service = UserService(cache=spyCache)
    result = service.fetchUser(userId)

    # Verify interaction occurred (spy recorded it)
    assert spyCache.get.wasCalledWith(cacheKey)
    assert spyCache.set.wasCalledWith(cacheKey, result)
```

**When to use**: When you need to verify interactions occurred while still exercising actual or nearly-actual behavior.

**Warning**: Partial mocks (spies wrapping real objects) often indicate design issues—objects with too many responsibilities or poorly designed interfaces for testing.

#### Fakes

**Purpose**: Provide working implementations with shortcuts unsuitable for production

**Definition**: Objects with real, functional implementations that take shortcuts (in-memory vs persisted, simplified algorithms)

**Use for**: Integration testing requiring realistic behavior without production complexity

**Examples**:

- In-memory database (H2, SQLite memory mode)
- In-memory message queue/event bus
- Fake file system (in-memory)
- Fake authentication service (no external provider)
- Fake email service (stores messages in memory)

**Characteristics**:

- Have **real behavior** indistinguishable from production to code under test
- Implement full interface contracts correctly
- Maintain state across operations
- Enable realistic integration testing without external dependencies

**Critical requirement**: Fakes require their own comprehensive test suites to ensure they correctly implement real contracts. As real implementations evolve, fakes must be updated and tested to maintain **fidelity**.

**Example**:

```text
# Fake with real behavior
class FakeUserRepository implements UserRepository:
    storage = {}  # In-memory instead of database

    save(user):
        if user.id in storage:
            raise DuplicateKeyError()
        storage[user.id] = deepCopy(user)
        return user

    findById(id):
        if id not in storage:
            return null
        return deepCopy(storage[id])

    delete(id):
        if id in storage:
            del storage[id]
```

**Benefits**: Provide realistic behavior, maintain isolation, remain deterministic and fast

**Risks**: If fake behavior diverges from real implementations, tests provide false confidence. Fakes must be maintained carefully.

#### Mocks

**Purpose**: Pre-programmed objects that verify specific interactions occurred as expected

**Definition**: Objects configured with expectations of calls they should receive, which verify those expectations and fail tests if expectations aren't met

**Use for**: Verifying interactions between objects (behavior verification / interaction testing)

**Characteristics**:

- Require expectations set up BEFORE code executes (expect-run-verify pattern)
- Proactively verify interactions match specifications
- Throw exceptions for unexpected calls
- Align with **behavior verification** (examining interactions, not just end state)
- Most sophisticated and frequently misunderstood test double type

**Example**:

```text
# Mock with pre-configured expectations
test_userCreation_sendsWelcomeEmail():
    mockEmailService = createMock()
    # Set expectation BEFORE execution
    mockEmailService.expect("sendWelcomeEmail")
        .withArgs(userEmail)
        .once()

    userService = UserService(emailService=mockEmailService)
    userService.createUser(validUserData)

    # Mock verifies expectation was met
    mockEmailService.verify()
```

**Good usage**: Verifying side effects, testing error handling, examining interactions where state changes aren't directly observable

**Bad usage**: Testing implementation details, over-specifying call sequences, verifying internal method calls not part of contracts

### State Verification vs Behavior Verification

This distinction represents the most fundamental choice in test design, with profound implications for test structure and maintainability.

#### State Verification (Testing "What")

**Approach**: Exercise code, then examine resulting state to verify correctness

**Focus**: Observable outcomes (return values, object state, side effects)

**Test doubles used**: Stubs, fakes

**Example**:

```text
# State verification - Check the result
test_shoppingCart_addItem_increasesTotal():
    cart = ShoppingCart()
    item = createItem(price=10.00)

    cart.addItem(item)

    # Verify state changed correctly
    assert cart.itemCount == 1
    assert cart.total == 10.00
```

**Advantages**:

- **Resistance to refactoring**: Tests don't break when internal implementation changes
- **Black-box testing**: No knowledge of internals required
- **Reduced coupling**: Tests coupled to behavior, not implementation
- **Easier maintenance**: Fewer tests break during refactoring

**Limitations**:

- Some interactions don't produce observable state changes (caching, logging)
- Testing side effects can be difficult without examining interactions

**Best for**: Business logic, algorithms, domain objects, data transformations

#### Behavior Verification (Testing "How")

**Approach**: Specify which interactions should occur, execute code, verify interactions happened

**Focus**: Method calls, parameters, call order, interaction sequences

**Test doubles used**: Mocks, spies

**Example**:

```text
# Behavior verification - Check the interactions
test_orderService_completesOrder_sendsNotification():
    mockNotifier = createMock()
    mockNotifier.expect("sendOrderConfirmation")
        .withArgs(orderId, customerEmail)

    service = OrderService(notifier=mockNotifier)
    service.completeOrder(order)

    mockNotifier.verify()  # Verify interaction occurred
```

**Advantages**:

- Tests interactions directly when state changes aren't observable
- Verifies orchestration and delegation correctly
- Tests side effects explicitly

**Disadvantages**:

- **Tight coupling to implementation**: Changes to how code calls dependencies break tests
- **Expensive refactoring**: Must update test expectations when implementation changes
- **False positives**: Tests pass but production fails when mocks don't match reality
- **Brittle tests**: Over-specification leads to frequent test breakage

**Best for**: Service orchestration, controllers, gateways, side effect verification

#### Recommended Strategy

Use **state verification as primary strategy**, reserving behavior verification for scenarios where it adds genuine value:

- ✅ **State verification**: Algorithmic code, business logic, domain objects
- ✅ **Behavior verification**: Service orchestration, side effects, error handling where state verification is inadequate

### Classical vs Mockist Schools of Testing

Two distinct philosophical approaches have evolved, each with different perspectives on test double usage.

#### Classical School (Detroit School)

**Philosophy**: Test observable state using real implementations where feasible

**Approach**:

- Use state verification as primary strategy
- Use real implementations of dependencies when practical
- Reserve test doubles for "awkward collaborators" (databases, external services, file systems)
- Prefer fakes over mocks when real implementations are impractical

**Advantages**:

- Tests remain stable through refactoring
- Bugs cause realistic failure propagation (helps isolate root causes)
- Better confidence in system integration
- Less coupling to implementation details

**Disadvantages**:

- Complex business logic may require substantial test setup
- Single bug can cause many test failures (ripple effect)
- May be slower if not using fakes

**Industry adoption**: Google explicitly adopts classical approach as preferred methodology, though not exclusively

#### Mockist School (London School)

**Philosophy**: Test through behavior verification, isolating each unit from all collaborators

**Approach**:

- Use behavior verification as primary strategy
- Replace all dependencies with mocks or stubs
- Test that objects make correct calls to collaborators
- Verify protocols between objects, not just end states

**Advantages**:

- Superior test isolation (bugs only fail specific class tests)
- Drives API design through forced thinking about interactions
- Faster identification of where bugs were introduced
- Granular control over dependencies

**Disadvantages**:

- Tests tightly coupled to implementation details
- Expensive refactoring (must update mock expectations)
- Can pass while production fails (mock behavior ≠ real behavior)
- Requires maintaining mock accuracy as real implementations evolve

**Current perspective**: Widespread mockist adoption has revealed significant maintenance costs at scale, leading major organizations to favor balanced hybrid approaches.

#### Recommended Hybrid Approach for Test Doubles

Use real implementations where feasible, test with state verification as primary strategy, employ mocks specifically for scenarios providing genuine value:

- Use real implementations for internal collaborators
- Use fakes for expensive operations (databases, message queues)
- Use mocks for side effects and interaction verification where appropriate
- Always supplement with integration tests using real implementations

### Over-Mocking: Common Anti-Patterns and Problems

While test doubles enable effective testing, their misuse creates brittle, high-maintenance test suites.

#### The Mockery Anti-Pattern

**Problem**: Mocking excessively or inappropriately

**Manifestations**:

- Creating excessive mocks for single tests (10+ mocks per test)
- Mocking types you don't own (third-party libraries, frameworks)
- Reflexively mocking all dependencies without consideration

**Consequences**:

- Tests verify mocks rather than actual functionality
- False confidence (tests pass, production fails)
- Missed integration issues
- Brittle tests requiring constant maintenance

**Solution**:

- Mock only at system boundaries (external APIs, databases, network)
- Create wrapper types around third-party libraries, mock the wrappers
- Default to real implementations, mock only when necessary
- Limit mocks per test (guideline: 3-5 maximum)

#### Testing Implementation Details

**Problem**: Tests specify exactly which methods should be called, in what order, with precise arguments

**Consequences**:

- Refactoring breaks tests even when behavior is unchanged
- False positives (test failures without actual bugs)
- Developers lose confidence in tests, disable or ignore them
- Expensive maintenance burden

**Example of problem**:

```text
# ❌ Testing implementation details
test_processPayment_implementation():
    mockValidator = createMock()
    mockRepository = createMock()

    # Over-specified implementation
    expect(mockValidator.validate).calledFirst()
    expect(mockRepository.save).calledSecond()
    expect(mockNotifier.notify).calledThird()

# ✅ Testing behavior
test_processPayment_success():
    service = PaymentService(realValidator, realRepository, realNotifier)

    result = service.processPayment(validPayment)

    assert result.success == true
    assert result.transactionId != null
```

**Solution**: Test behavior against public APIs and observable effects, not implementation details

#### Over-Reliance on Mocking Frameworks

**Problem**: Mocking frameworks make creating mocks trivially easy, encouraging reflexive over-mocking

**Consequences**:

- Tests filled with mock configuration code (poor readability)
- Implementation-detail-heavy tests
- Developers lose sight of whether tests validate functionality

**Solution**:

- Use manual test doubles for non-trivial scenarios
- Manual doubles encourage thinking about minimal behavior needed
- Manual doubles are more reusable and readable
- Better performance (no runtime proxy generation overhead)

#### Mock Fragility and Maintenance Burden

**Problem**: Mocks become out of sync with real implementations as code evolves

**Consequences**:

- Tests pass but production fails
- Maintenance cost grows faster than test value
- Developers spend more time updating mocks than writing features

**Solution**:

- Maintain fakes carefully with comprehensive test suites
- Use contract testing to verify mocks match real implementations
- Supplement unit tests with integration tests using real implementations
- Regularly review and update mocks when real implementations change

### Practical Guidelines for Test Double Selection

#### When to Use Fakes

- ✅ Real implementation is slow, expensive, or requires complex setup
- ✅ Code depends on complex interactions simple stubs can't capture
- ✅ Many tests depend on same component (development cost justified)
- ❌ Only handful of tests use component (cost not justified)
- ⚠️ Must maintain fake test suite and ensure fidelity with real implementation

#### When to Use Stubs

- ✅ Testing how code processes responses from dependencies
- ✅ Isolating code from external services for test speed
- ✅ Controlling dependency responses for various scenarios (success, failure, edge cases)
- ❌ Need to verify HOW code constructs requests to dependencies

#### When to Use Spies

- ✅ Need both canned responses AND verification of interactions
- ✅ Testing orchestration where behavior verification appropriate but need realistic behavior
- ⚠️ Partial mocks often indicate design issues (object has too many responsibilities)

#### When to Use Mocks

- ✅ Verifying side effects where observable state changes don't occur
- ✅ Testing error handling and exception scenarios
- ✅ Verifying code makes correct calls with correct parameters
- ❌ Testing business logic or algorithmic code (use state verification instead)
- ❌ All dependencies reflexively (mock only when necessary)

#### When to Use Dummies

- ✅ Filling parameter lists where code never uses parameters
- ❌ Code actually uses parameter (need more sophisticated test double)

### Best Practices for Effective Test Double Usage

#### Prefer real implementations over test doubles

- Use real implementations whenever feasible
- Only introduce test doubles when real implementations are genuinely problematic
- Real implementations provide highest fidelity and confidence

#### Apply test doubles at boundaries

- Concentrate on application boundaries (network, database, file system, external APIs)
- Use real implementations for internal collaborators
- Reduces mock complexity to where it's genuinely needed

#### Don't mock what you don't own

- Never mock third-party libraries, frameworks, or external types
- Create wrapper types around external libraries, mock the wrappers
- Prevents false confidence and missed integration issues

#### Maintain fakes carefully

- Treat fakes as production-quality code
- Comprehensive test suites for fakes
- Update fakes when real implementations change
- Test both in isolation and against real implementations for fidelity

#### Use dependency injection

- Pass dependencies as parameters (constructor injection preferred)
- Enables substituting test doubles at test time
- Makes both production and test code cleaner

#### Keep mock setup minimal

- Minimal, focused mock configuration
- Extract complex setup into helper methods
- Excessive setup indicates poor test design

#### Mock only external dependencies

- ✅ Mock: External APIs, file systems, network, time, randomness
- ❌ Don't mock: Code under test, internal value objects, domain entities

## Test Data Management Best Practices

How test data is created, managed, and cleaned up significantly impacts test maintainability and determinism.

### Use Test Data Builders and Factories

Rather than manually constructing complex test objects or relying on fixtures, use builder objects that construct valid instances with sensible defaults.

```text
# ❌ Manual construction - Brittle and verbose
test_userCreation():
    user = User()
    user.id = generateId()
    user.email = "test@example.com"
    user.firstName = "Test"
    user.lastName = "User"
    user.verified = true
    user.createdAt = Date.now()
    user.role = "member"
    # ... 10 more fields

# ✅ Builder pattern - Maintainable and focused
test_userCreation():
    user = UserBuilder()
        .withEmail("test@example.com")
        .withVerified(true)
        .build()
    # All other fields get sensible defaults
```

**Benefits:**

- Centralizes test data construction
- Easy to maintain when domain objects change
- Tests specify only relevant attributes
- Improves readability and intent

### Separate Valid Default Data from Test-Specific Variations

```text
# Builder with defaults
class UserBuilder:
    defaults:
        email = "default@example.com"
        verified = false
        role = "member"

    withEmail(email):
        this.email = email
        return this

    withVerified(verified):
        this.verified = verified
        return this

    build():
        return User(this.email, this.verified, this.role)

# Usage - specify only what matters
test_emailVerification_requiresVerifiedUser():
    user = UserBuilder().withVerified(true).build()
    # Only relevant attribute specified, clear test intent
```

### Use Immutable or Copy-on-Write Test Data

If tests share references to mutable test data, modifications in one test can affect others:

```text
# ❌ Shared mutable data
SHARED_USER = User("test@example.com")

test_updateEmail():
    SHARED_USER.email = "new@example.com"
    # Mutates shared state!

# ✅ Immutable or copied data
test_updateEmail():
    user = SHARED_USER.copy()  # Deep copy
    user.email = "new@example.com"
    # No shared state mutation
```

### Create Domain-Specific Test Data Methods

Instead of generic "create object" methods, name methods after test scenarios:

```text
# ❌ Generic methods
createUser()
createAccount()

# ✅ Domain-specific methods
validUserData()
expiredSubscriptionData()
lowBalanceAccountData()
unverifiedUserData()
adminUserData()
```

This makes test code more readable and easier to maintain as requirements evolve.

### Avoid Embedding Literal Test Data in Tests

```text
# ❌ Hardcoded literals scattered throughout tests
test_validation():
    assert validate("john@example.com") == true

test_creation():
    user = createUser("john@example.com")

test_lookup():
    result = findUser("john@example.com")
    # What if "john@example.com" needs to change?

# ✅ Centralized test data
VALID_EMAIL = "test@example.com"

test_validation():
    assert validate(VALID_EMAIL) == true

# ✅ Better: Use builders/factories
test_validation():
    email = validEmail()
    assert validate(email) == true
```

### Clean Up Test Data Explicitly

Use setup/teardown methods or test lifecycle hooks to ensure test data created during execution is removed afterward:

```text
class TestUserService:
    setup():
        this.database = connectTestDatabase()
        this.createdUserIds = []

    test_createUser():
        user = userService.create(validUserData())
        this.createdUserIds.add(user.id)
        # Test logic...

    teardown():
        # Clean up all created users
        for userId in this.createdUserIds:
            this.database.deleteUser(userId)
```

## Avoiding Hardcoded Dependencies on External Resources

Tests depending on specific file paths, hardcoded URLs, or embedded resources become brittle when environments change or resources move.

### Inject Resource Paths and External Service URLs

```text
# ❌ Hardcoded paths/URLs
def loadTestConfig():
    return readFile("/opt/app/test-config.yaml")

def connectService():
    return HTTPClient("http://localhost:8080/api")

# ✅ Injected paths/URLs
def loadTestConfig(configPath=None):
    path = configPath or getenv("TEST_CONFIG_PATH", "config/test.yaml")
    return readFile(path)

def connectService(baseUrl=None):
    url = baseUrl or getenv("TEST_SERVICE_URL", "http://localhost:8080/api")
    return HTTPClient(url)
```

### Use Temporary Files and Directories

Create temporary directories for each test rather than depending on specific filesystem locations:

```text
# ✅ Temporary directory per test
test_fileProcessing():
    setup:
        this.tempDir = createTempDirectory()
        this.testFile = this.tempDir / "test-data.json"
        writeFile(this.testFile, testData)

    execute:
        result = processFile(this.testFile)

    teardown:
        deleteTempDirectory(this.tempDir)
```

Most languages provide utilities: Java's `@TempDir`, text's `tempfile`, Node's `tmp`, .NET's `Path.GetTempPath()`.

### Mock HTTP Clients and Provide Fake Responses

```text
# ❌ Real network calls
test_fetchUserData():
    response = httpClient.get("https://api.example.com/users/123")
    # Fails if network down, API changes, rate limits!

# ✅ Mocked HTTP client
test_fetchUserData():
    mockHttp = createMockHttpClient()
    mockHttp.whenGet("/users/123").thenReturn(
        status=200,
        body='{"id": 123, "name": "Test User"}'
    )

    service = UserService(httpClient=mockHttp)
    user = service.fetchUser(123)
    assert user.name == "Test User"
```

Libraries like WireMock, MockServer, or language-specific mocking utilities make this straightforward.

### Externalize Configuration in Tests

Use environment variables, configuration files, or dependency injection to specify external service URLs, credentials, or resource locations:

```yaml
# Test configuration (test-config.yaml)
database:
  host: localhost
  port: 5432
  name: test_db

services:
  user_api: http://localhost:9000
  payment_api: http://localhost:9001

# Test uses configuration
test_setup():
    config = loadTestConfig()
    database = connectDatabase(config.database)
    userApi = HTTPClient(config.services.user_api)
```

### Use Relative Resource References

If tests must reference resource files, store them relative to the test class location and reference them via classpath/resource mechanisms:

```text
# ❌ Absolute paths
testData = readFile("C:/projects/myapp/test/resources/users.json")

# ❌ Brittle relative paths
testData = readFile("../../../resources/users.json")

# ✅ Resource mechanism
testData = readResourceFile("test-resources/users.json")

# ✅ Path relative to test class
testData = readFile(getTestResourcePath(__file__, "users.json"))
```

## Test Naming Conventions

Clear, descriptive test names document expected behavior and make test failures immediately understandable.

### Use Behavior-Descriptive Names

```text
# ❌ Implementation descriptive names
test_queryDatabase()
test_callValidator()
test_method1()

# ✅ Behavior descriptive names
test_rejectDuplicateEmailsOnUserCreation()
test_returnNullForNonexistentUser()
test_throwExceptionForInvalidEmailFormat()
```

The test name should describe **what behavior** is being validated, not **what implementation** is being exercised.

### Follow Consistent Naming Patterns

Adopt conventions like:

- `test_<operation>_<condition>_<expectedResult>()`
- `test_<methodName>_<scenario>_<expectedBehavior>()`
- `should_<expectedBehavior>_when_<condition>()`
- `given_<precondition>_when_<action>_then_<outcome>()`

**Examples:**

```text
test_createUser_withDuplicateEmail_throwsValidationError()
test_processPayment_withInsufficientFunds_returnsDeclined()
test_calculateDiscount_forPremiumMember_applies20PercentDiscount()

should_returnEmptyList_when_noMatchingRecordsFound()
should_sendNotification_when_orderCompleted()

given_existingUser_when_updateEmail_then_emailUpdated()
given_expiredToken_when_authenticate_then_unauthorized()
```

### Avoid Number-Suffixed Tests

```text
# ❌ No information about what distinguishes tests
testUserCreation1()
testUserCreation2()
testUserCreation3()

# ✅ Descriptive distinctions
test_createUser_withValidData_succeeds()
test_createUser_withDuplicateEmail_fails()
test_createUser_withInvalidEmail_fails()
```

### Describe the Scenario and Assertion

Test names should convey:

1. **Setup/condition**: What state exists
2. **Action**: What operation is performed
3. **Expectation**: What should result

For complex scenarios, longer names are acceptable and preferred over cryptic abbreviations.

### Use Parameterized Test Names Effectively

When using parameterized tests, ensure the framework includes parameter values in the test name:

```text
# ✅ Framework includes parameters in name
@ParameterizedTest
@ValueSource(emails = ["valid@example.com", "test@test.co.uk"])
test_validateEmail_withValidFormat_returnsTrue(email):
    assert validateEmail(email) == true

# Generates:
# test_validateEmail_withValidFormat_returnsTrue[valid@example.com]
# test_validateEmail_withValidFormat_returnsTrue[test@test.co.uk]
```

## Test Pyramid and Test Levels

Structure test suites as a pyramid with appropriate distribution across test levels:

```text
        /\
       /  \  E2E (Few)
      /    \
     /------\  Integration (Some)
    /        \
   /----------\  Unit (Many)
  /____________\
```

### Clear Boundaries Between Test Levels

Understanding exactly what separates unit, integration, and E2E tests prevents confusion and ensures tests are written at the appropriate level:

| Aspect | Unit Tests | Integration Tests | E2E Tests |
| -------- | ----------- | ------------------- | ----------- |
| **Scope** | Single component/function/class in isolation | Multiple components working together | Complete system with all dependencies |
| **Speed** | Milliseconds (< 100ms each) | Seconds (< 5s each) | Minutes (can be 30s to several minutes) |
| **Dependencies** | All external dependencies mocked/stubbed | Real implementations of internal dependencies; controlled external dependencies (in-memory DB, test containers) | Production-like environment with real databases, services, infrastructure |
| **Isolation** | Complete isolation via test doubles | Partial isolation (real internal, controlled external) | Minimal isolation (full system integration) |
| **Failure Scope** | Pinpoints exact component with problem | Identifies integration issue between components | Shows system-level failure (requires debugging to find root cause) |
| **Test Data** | Minimal, in-memory test data | Test database with controlled datasets | Production-like data volumes and complexity |
| **Environment** | No external environment needed | Lightweight test environment (Docker containers, in-memory services) | Full staging/production-like environment |
| **Execution** | Every code change (pre-commit, on save) | Every commit (CI pipeline) | Daily or pre-release (scheduled or manual) |
| **Maintenance** | Low (changes only when behavior changes) | Medium (changes when contracts or integrations change) | High (brittle, affected by UI/API changes, infrastructure issues) |
| **Coverage Target** | 70-80% of test suite | 15-25% of test suite | 5-10% of test suite |
| **Primary Value** | Rapid feedback, design verification, regression protection | Validates component contracts, catches integration bugs | Validates critical user journeys work end-to-end |

### Unit Tests (Base - Majority of tests)

**Core Definition**: Tests that verify a single unit of behavior in complete isolation from external dependencies.

#### Characteristics

- **Fast**: Milliseconds per test (typically < 100ms)
- **Isolated**: All dependencies replaced with test doubles
- **Focused**: One behavior, one assertion per test
- **Independent**: Can run in any order, no shared state
- **Deterministic**: Same input always produces same result
- **High volume, low cost**: Many tests, cheap to write and maintain

#### What to Test at Unit Level

**✅ Test these with unit tests:**

- **Business logic**: Algorithms, calculations, decision trees, validation rules
- **Data transformations**: Parsing, formatting, mapping, serialization
- **Edge cases and boundaries**: Empty inputs, null values, maximum values, invalid inputs
- **Error handling**: Exception paths, validation failures, error messages
- **Pure functions**: Functions without side effects (same input → same output)
- **Domain models**: Entity behavior, value object validation, domain rules
- **Utility functions**: String manipulation, date handling, collection operations

**❌ Don't test these with unit tests:**

- **Framework code**: Already tested by framework authors
- **Trivial getters/setters**: No logic to test
- **Configuration**: Test configuration loading with integration tests
- **Database queries**: Require actual database (integration test)
- **Network calls**: Require real network (integration test)
- **File I/O**: Require real file system (integration or E2E test)
- **Third-party library internals**: Trust the library, test your usage with integration tests

#### Sociable vs Solitary Unit Tests

##### Solitary Unit Tests (London School / Mockist)

- Replace ALL dependencies with test doubles (mocks, stubs, fakes)
- Test single class in complete isolation
- Advantages:
  - Precise failure localization (know exactly which class failed)
  - Forces thinking about dependencies and coupling
  - Tests remain fast even with complex dependency graphs
- Disadvantages:
  - Tests coupled to implementation details
  - Refactoring requires updating many tests
  - False confidence (mocks may not match real behavior)
  - High maintenance cost at scale

##### Sociable Unit Tests (Detroit School / Classical)

- Use real implementations of collaborators within same module/bounded context
- Only mock external dependencies (database, network, file system)
- Advantages:
  - Tests are resilient to refactoring
  - Higher confidence (tests use real collaborators)
  - Lower maintenance burden
  - Focus on observable behavior, not implementation
- Disadvantages:
  - Slower than solitary tests (though still fast)
  - Failures may require debugging to find exact cause
  - May require more test data setup

##### Recommended Hybrid Approach for Unit Tests

```text
✅ Use REAL implementations for:
- Value objects (domain entities, DTOs)
- Pure functions and utilities
- Internal collaborators within same bounded context
- Simple, fast dependencies

✅ Use TEST DOUBLES for:
- External services (APIs, databases, file systems)
- Time (current date/time, delays, timeouts)
- Randomness (random number generators, UUIDs)
- Expensive operations (complex calculations, large data processing)
- Non-deterministic behavior (network latency, race conditions)
```

##### Example: Sociable vs Solitary

```text
# Solitary approach (all dependencies mocked)
test_processOrder_solitary():
    mockValidator = Mock(OrderValidator)
    mockPricer = Mock(PricingService)
    mockInventory = Mock(InventoryService)

    mockValidator.validate.returns(true)
    mockPricer.calculatePrice.returns(100.00)
    mockInventory.checkStock.returns(true)

    processor = OrderProcessor(mockValidator, mockPricer, mockInventory)
    result = processor.process(order)

    assert result.success == true
    verify mockValidator.validate.calledWith(order)
    verify mockPricer.calculatePrice.calledWith(order)

# Sociable approach (real internal collaborators, mock external only)
test_processOrder_sociable():
    realValidator = OrderValidator()  # Real implementation
    realPricer = PricingService()     # Real implementation
    mockInventory = Mock(InventoryService)  # External dependency

    mockInventory.checkStock.returns(true)

    processor = OrderProcessor(realValidator, realPricer, mockInventory)
    result = processor.process(validOrder)

    assert result.success == true
    assert result.totalPrice == 100.00  # Real calculation verified
```

**Industry Trend**: Google, Spotify, and most large engineering orgs favor sociable unit tests for better refactoring resilience and lower maintenance costs.

#### Best Practices for Unit Tests

- **Prefer sociable over solitary** when collaborators are fast and in-process
- **One assertion per test** (or closely related assertions for same behavior)
- **Descriptive test names** that explain behavior being tested
- **AAA pattern**: Arrange → Act → Assert (with clear separation)
- **Test behavior, not implementation**: Focus on public API, not internal details
- **Keep tests DRY but readable**: Extract setup, but keep assertion logic visible
- **Use test data builders** for complex object creation
- **Avoid logic in tests**: No conditionals, loops, or complex operations
- **Make tests deterministic**: No random values, timestamps, or external state

### Integration Tests (Middle - Moderate number)

**Core Definition**: Tests that verify correct interaction between multiple components, modules, or systems, using real implementations where feasible.

#### Integration Test Characteristics

- **Medium speed**: Seconds per test (typically < 5s)
- **Partial isolation**: Real internal components, controlled external dependencies
- **Contract verification**: Ensures components communicate correctly
- **Real implementations**: In-memory databases, test containers, embedded services
- **Medium volume, medium cost**: Fewer than unit tests, more expensive to maintain

#### What to Test at Integration Level

**✅ Test these with integration tests:**

- **Database operations**: CRUD operations, queries, transactions, migrations, constraints
- **API contracts**: REST/GraphQL endpoints, request/response formats, error handling
- **Message passing**: Event publishing/subscribing, message queue operations
- **File operations**: Reading/writing files, parsing file formats, file system interactions
- **Component interactions**: Service orchestration, workflow coordination
- **Configuration loading**: Environment variables, config files, feature flags
- **Authentication/Authorization**: User login, token validation, permission checks
- **Third-party integrations**: External API calls (using test/sandbox environments)
- **Caching behavior**: Cache hits/misses, invalidation, TTL
- **Dependency injection**: Correct wiring of components via DI containers

**❌ Don't test these with integration tests:**

- **Business logic**: Already covered by unit tests (faster, more focused)
- **Edge cases for pure functions**: Unit tests are better suited
- **Every possible combination**: Focus on happy path and critical error scenarios
- **UI interactions**: Leave for E2E tests (integration focuses on backend/service layer)

#### Integration Test Strategies

##### Database Integration Testing

```text
# Strategy 1: In-Memory Database
- Use SQLite, H2, or in-memory PostgreSQL
- Fast, deterministic, easy cleanup
- ⚠️ SQL dialect differences may hide production bugs

# Strategy 2: Test Containers (Recommended)
- Spin up real database in Docker container
- Identical to production database engine
- Cleanup via container disposal
- Example: Testcontainers library

# Strategy 3: Transaction Rollback
- Start transaction before test
- Run test
- Rollback transaction after test
- Fast, but may miss transaction-related bugs
```

##### API Integration Testing

```text
# Test both sides of API contract:
1. Producer side (service implementing API):
   - Request validation
   - Response format correctness
   - Error handling (400, 404, 500 responses)
   - Authentication/authorization

2. Consumer side (client calling API):
   - Correct request construction
   - Response parsing
   - Retry logic
   - Timeout handling
```

##### Message Queue Integration Testing

```text
# Use embedded brokers or test containers:
- Embedded Kafka for Kafka-based systems
- In-memory RabbitMQ or test containers
- Verify message production and consumption
- Test idempotency and retry logic
```

#### Contract Testing and Component Testing

##### Contract Testing

Contract testing ensures that services can communicate correctly by verifying the contracts (interfaces) between them without requiring all services to be deployed together.

**Purpose**:

- Verify producer provides what consumer expects
- Catch breaking changes before production
- Enable independent deployment of services
- Reduce need for costly integrated test environments

**Approaches**:

```text
# Consumer-Driven Contracts (Pact, Spring Cloud Contract)
1. Consumer defines expectations (contract)
2. Consumer tests verify it can handle responses matching contract
3. Producer tests verify it satisfies consumer contracts
4. Contracts shared via contract repository

# Provider-Driven Contracts (OpenAPI/Swagger)
1. Provider publishes API specification
2. Consumers generate tests from specification
3. Provider verifies implementation matches spec
```

**When to use Contract Testing**:

- ✅ Microservices architectures
- ✅ Multiple teams owning different services
- ✅ Services versioned and deployed independently
- ✅ Need to catch integration issues early
- ❌ Monolithic applications
- ❌ Tightly coupled services deployed together

##### Component Testing

Component testing treats a service or module as a black box, testing it through its public interface with real dependencies stubbed or faked.

**Scope**: Larger than unit test, smaller than E2E test

**Characteristics**:

- Test entire component/service in isolation
- Stub external dependencies (other services, databases, queues)
- Use in-memory implementations where possible
- Focus on component's public contract
- Typically faster than full E2E tests

**Example**: Testing an Order Service

```text
# Component test scope:
OrderService (real implementation)
  ├─ OrderValidator (real)
  ├─ PricingService (real)
  ├─ Database (in-memory or test container)
  ├─ PaymentGateway (stubbed - external dependency)
  └─ EmailService (stubbed - external dependency)

# Test verifies:
- Order creation through REST API
- Database persistence
- Business logic execution
- Correct calls to external services (via stubs)
```

**When to use Component Testing**:

- ✅ Microservices (test service in isolation)
- ✅ Need faster feedback than E2E but more coverage than unit tests
- ✅ Testing service boundaries and contracts
- ✅ Validating workflows within a service
- ❌ Testing interactions between multiple real services (use E2E)

#### Best Practices for Integration Tests

- **Use test containers** for real database/service instances (preferred over in-memory when feasible)
- **Isolate tests**: Each test should have clean state (transactions, database resets, container restarts)
- **Focus on contracts**: Verify the interface/contract, not implementation details
- **Test realistic scenarios**: Use data similar to production
- **Keep tests independent**: No shared state between tests
- **Use contract testing** for microservices to catch breaking changes early
- **Supplement, don't replace unit tests**: Integration tests are slower, run fewer of them
- **Use builder patterns** for complex test data setup
- **Test both success and failure paths**: Network failures, timeouts, invalid responses

### End-to-End Tests (Top - Fewest tests)

**Core Definition**: Tests that validate complete user workflows through the entire system, from user interface to database and back, in a production-like environment.

#### E2E Test Characteristics

- **Slow**: Minutes per test (30s to several minutes)
- **Brittle**: Sensitive to UI changes, infrastructure issues, timing problems
- **Expensive**: Require full environment, complex setup, slow feedback
- **High confidence**: Validate the system actually works for users
- **Low volume, high cost**: Only test critical paths
- **Production-like**: Real databases, services, infrastructure

#### What to Test at E2E Level

**✅ Test these with E2E tests:**

- **Critical user journeys**: Login → Add to Cart → Checkout → Payment → Confirmation
- **Main application flows**: User registration, password reset, core feature usage
- **Cross-system workflows**: Workflows spanning multiple services/systems
- **UI-critical paths**: Workflows heavily dependent on UI state and interactions
- **Revenue-impacting features**: Payment processing, subscription management, order fulfillment
- **Compliance-critical workflows**: Data privacy features, audit trails, access controls

**❌ Don't test these with E2E tests:**

- **Edge cases**: Too slow, cover with unit/integration tests
- **Every feature combination**: Exponential explosion, test critical paths only
- **Validation logic**: Already covered by unit tests
- **Error messages**: Cover with unit/integration tests
- **Performance testing**: Use dedicated performance tests
- **All browser/device combinations**: Test critical paths on critical platforms only

#### E2E Test Strategies

**User Journey Mapping**:

```text
1. Identify critical user journeys (typically 5-10 per application)
2. Map happy path for each journey
3. Add 1-2 critical error scenarios per journey
4. Avoid testing every edge case (too expensive)
```

**Example Critical Journeys for E-commerce**:

- New user registration → Browse → Purchase → Confirmation
- Returning user login → View order history → Reorder
- Add item to cart → Apply coupon → Checkout
- Administrator login → Manage inventory → Publish changes

**Selective Browser/Platform Testing**:

```text
# Don't test everything everywhere
❌ All tests on all browsers (Chrome, Firefox, Safari, Edge)
✅ Smoke tests on all browsers, detailed tests on most popular (Chrome + Safari)

# Focus platforms by user analytics
- If 80% users on mobile, prioritize mobile E2E tests
- If 90% users on Chrome, prioritize Chrome coverage
```

#### Best Practices for E2E Tests

- **Test only critical paths**: Revenue-impacting, high-usage, compliance-critical
- **Keep tests independent**: Each test should set up its own data, clean up after
- **Use page object pattern**: Encapsulate UI interactions in reusable page objects
- **Avoid brittle selectors**: Use stable IDs/data attributes, avoid CSS classes or text
- **Add explicit waits**: Wait for elements to appear, avoid hard-coded sleeps
- **Run in parallel** where possible to reduce total execution time
- **Accept some flakiness**: E2E tests are inherently flaky, focus on stability but don't expect perfection
- **Monitor flaky tests**: Track and fix consistently flaky tests
- **Run on schedule**: Daily or pre-release, not on every commit (too slow)
- **Use production-like data**: Realistic volumes, realistic complexity
- **Test in production-like environment**: Staging should mirror production

### Anti-Pattern: Inverted Pyramid

```text
# ❌ ANTI-PATTERN - Inverted pyramid
Many E2E tests (slow, brittle, expensive)
Few integration tests
Very few unit tests

Result:
- Slow feedback (tests take hours)
- High maintenance cost (brittle E2E tests break constantly)
- Poor developer experience (wait hours for test results)
- Expensive CI/CD infrastructure

# ✅ CORRECT - Proper pyramid
Many unit tests (fast, stable, cheap)
Some integration tests
Few E2E tests

Result:
- Fast feedback (unit tests run in seconds)
- Low maintenance cost (stable tests)
- Great developer experience (instant feedback)
- Affordable CI/CD infrastructure
```

### Test Pyramid Summary: What Goes Where?

**Quick Decision Guide**:

```text
"Should I test this behavior?"
    ↓
"Can I test it with a unit test?"
    ↓ NO (requires external dependencies)
"Can I test it with an integration test?"
    ↓ NO (requires full system)
"Is this a critical user journey?"
    ↓ YES
"Add E2E test"
    ↓ NO
"Consider if testing is necessary"
```

**Remember**: Push tests down the pyramid when possible. The lower the test, the faster, cheaper, and more stable it will be.

## Balancing Test Coverage with Maintainability

Coverage metrics can mislead; 100% coverage of poorly designed tests provides false confidence while incurring massive maintenance burden.

### Prioritize Coverage of Critical Behaviors and Risks

Rather than chasing high coverage percentages, focus testing on high-risk, high-value areas:

**High priority:**

- Authentication and authorization
- Payment processing
- Data integrity operations
- Security boundaries
- Critical business logic
- Error handling and edge cases

**Lower priority:**

- Getters and setters
- Framework code (already tested by framework)
- Trivial utilities
- Defensive programming that may never execute

### Use Risk-Based Testing Strategies

Allocate testing effort proportionally to risk:

**High risk features:**

- Comprehensive unit tests
- Integration tests
- End-to-end tests
- Security testing
- Performance testing

**Medium risk features:**

- Solid unit test coverage
- Key integration tests
- Selected E2E tests

**Low risk features:**

- Basic unit tests
- Light integration testing
- Minimal E2E coverage

### Test at Appropriate Levels

Don't test the same thing at multiple levels unnecessarily:

```text
# ❌ WASTEFUL - Testing same logic at all levels
Unit test: validateEmail(email)
Integration test: createUser(validEmail) -> validates email
E2E test: signup form -> validates email
# Email validation tested 3 times!

# ✅ EFFICIENT - Test each concern at appropriate level
Unit test: validateEmail(email) <- Test validation logic here
Integration test: createUser(validEmail) -> assumes validation works
E2E test: signup form -> assumes validation works
# Each level tests different concerns
```

### Remove Tests That Don't Provide Value

**Delete tests that:**

- Test getters and setters with no logic
- Merely verify a framework works
- Always pass (or always fail)
- Test implementation details that frequently change
- Duplicate coverage at wrong level

#### Example: Worthless tests

```text
# ❌ WORTHLESS - Testing getter/setter
test_setAndGetEmail():
    user.setEmail("test@example.com")
    assert user.getEmail() == "test@example.com"
    # This just tests that assignment works!

# ❌ WORTHLESS - Testing framework
test_databaseConnection():
    connection = database.connect()
    assert connection != null
    # Testing that the database library works!
```

### Accept That Some Code Paths Won't Be Tested

**Acceptable gaps:**

- Error paths that cannot reliably be triggered
- Fallback logic for extremely rare edge cases
- Defensive programming that may never execute
- Framework boilerplate with no custom logic

**Trade-off:** Some untested code is acceptable if the cost of testing exceeds the value provided.

### Measure Maintainability Alongside Coverage

Track these metrics:

**Test maintenance cost:**

- Time spent updating tests after refactoring
- Frequency of test failures unrelated to bugs
- Number of tests modified per production code change

**Test effectiveness:**

- Defects caught by tests vs. production
- Test failure investigation time
- False positive rate (tests failing without real bugs)

**If test maintenance time exceeds value provided**, reduce test scope rather than maintaining brittle tests.

### Treat Tests as Production Code

Apply the same quality standards to tests:

- ✅ Clear, descriptive naming
- ✅ Proper abstraction and modularity
- ✅ DRY principles (extract common setup)
- ✅ Refactor when complexity grows
- ✅ Code review for tests
- ✅ Enforce coding standards
- ✅ Document complex test scenarios

## Test-Driven Development (TDD) and Behavior-Driven Development (BDD)

As mentioned in CLAUDE.md, when adding or changing non-trivial behavior, prefer TDD or BDD where feasible.

### Test-Driven Development (TDD)

**Red-Green-Refactor cycle:**

1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code quality while keeping tests green

**Benefits:**

- Forces clear understanding of requirements before coding
- Ensures all code is tested (by definition)
- Creates cleaner interfaces (testability drives design)
- Provides immediate feedback on changes

**When to use:**

- New feature development
- Bug fixes (write failing test that reproduces bug, then fix)
- Refactoring (tests ensure behavior preserved)

### Behavior-Driven Development (BDD)

**Given-When-Then structure:**

```gherkin
Scenario: User successfully logs in with valid credentials
  Given a registered user with email "user@example.com" and password "secret123"
  When the user submits the login form with correct credentials
  Then the user should be redirected to the dashboard
  And a session should be created for the user
```

**Benefits:**

- Tests written in business language (stakeholder readable)
- Focuses on user behavior and outcomes
- Bridges gap between technical and non-technical team members
- Tests serve as living documentation

**When to use:**

- Features with clear user-facing behavior
- Projects with non-technical stakeholders
- Complex business logic requiring specification
- Acceptance testing and E2E scenarios

## Common Anti-Patterns to Avoid

### Test Interdependence

Tests that depend on other tests running first or leaving state behind:

```text
# ❌ ANTI-PATTERN
test_1_createUser():
    globalUser = createUser()

test_2_updateUser():
    globalUser.update(...)  # Depends on test_1!
```

### Testing Implementation Instead of Behavior

```text
# ❌ ANTI-PATTERN
test_userCreation_callsMethodsInOrder():
    assert repository.validate() called before repository.save()
    # Tests implementation detail, not behavior
```

### Overly Complex Test Setup

```text
# ❌ ANTI-PATTERN - 50 lines of setup
setup():
    # ... 50 lines of complex initialization
    # No one understands what's being tested anymore

# ✅ CORRECT - Clear, minimal setup
setup():
    this.user = createTestUser()  # Simple, focused
```

### Assertion Roulette

Multiple assertions without clear failure messages:

```text
# ❌ ANTI-PATTERN
test_userValidation():
    assert result != null
    assert result.id > 0
    assert result.email != null
    assert result.verified == true
    # Which assertion failed? Why?

# ✅ CORRECT
test_userValidation():
    assert result != null, "Result should not be null"
    assert result.id > 0, "User ID should be positive"
    assert result.email != null, "Email should be set"
    assert result.verified == true, "User should be verified"
```

### Testing Everything Together (No Isolation)

```text
# ❌ ANTI-PATTERN
test_entireApplicationWorkflow():
    # 200 lines testing database, network, UI, business logic all together
    # Impossible to debug when it fails

# ✅ CORRECT
test_businessLogic():
    # Tests business logic with mocked dependencies

test_databaseIntegration():
    # Tests database interactions with test database

test_uiWorkflow():
    # Tests UI with mocked backend
```

## Summary: The Golden Rules

1. **FIRST principles**: Fast, Isolated, Repeatable, Self-validating, Timely
2. **Test behavior, not implementation**: Focus on what code does, not how
3. **Avoid brittle tests**: Never hardcode external dependencies, test at behavioral boundaries
4. **Maintain isolation**: Each test independent, no shared mutable state
5. **Ensure determinism**: Control time, randomness, external dependencies
6. **Use mocks appropriately**: Stub external dependencies, mock only integration contracts
7. **Manage test data**: Use builders, clean up, avoid hardcoded literals
8. **Name tests clearly**: Behavior-descriptive names, consistent patterns
9. **Balance coverage with maintainability**: Prioritize critical behaviors over high percentages
10. **Treat tests as production code**: Same quality standards apply

## Cross-References

- CLAUDE.md: "Test-driven and behavior-driven development (TDD/BDD)" for when to apply these practices
- CLAUDE.md: "Tests as part of every change plan" for integration with development workflow
- CLAUDE.md: "No partial handoffs" and "Implementation integrity" for test quality standards
- CLAUDE.md: "Test preservation" for maintaining tests as living documentation

## Related Documentation

- Testing frameworks and tools are language-specific; consult your language/framework documentation
- CI/CD integration patterns vary by platform; see your CI/CD provider's documentation
- Test coverage tools: language-specific (JaCoCo, Coverage.py, Istanbul, etc.)

---

**Last Updated:** 2025-11-30
**Sources:** Perplexity AI research, Microsoft Learn documentation, industry best practices
