# Code Smells Catalog

Comprehensive catalog of code smells from Clean Code (Robert C. Martin) and Refactoring (Martin Fowler).

## Bloaters

### Long Method

**Detection:**

- Method exceeds 20 lines
- Multiple levels of abstraction in one method
- Requires scrolling to understand
- Method name doesn't describe all it does

**Impact:**

- Hard to understand and maintain
- Difficult to test
- Encourages duplication

**Fix:**

- Extract Method for logical blocks
- Replace Temp with Query
- Introduce Parameter Object for related parameters
- Decompose Conditional for complex logic

### Large Class

**Detection:**

- Class has too many instance variables (>7)
- Class has too many methods (>20)
- Class requires multiple files to understand
- Class name is generic (Manager, Handler, Processor)

**Impact:**

- Violates SRP
- Hard to understand and change
- High coupling

**Fix:**

- Extract Class for cohesive subsets
- Extract Subclass for specialized behavior
- Extract Interface for separate responsibilities

### Primitive Obsession

**Detection:**

- Using primitives instead of small value objects
- String constants for type codes
- Field names ending in "Type", "Code", "Flag"
- Validation logic scattered across code

**Impact:**

- Lost domain semantics
- Duplication of validation logic
- Error-prone (no type safety)

**Fix:**

- Replace Data Value with Object
- Replace Type Code with Class/State/Strategy
- Introduce Value Object (email, phone, currency)

### Long Parameter List

**Detection:**

- More than 3-4 parameters
- Parameters frequently change together
- Calling code repeatedly passes same values
- Parameter names numbered (param1, param2)

**Impact:**

- Hard to understand and remember
- Fragile to changes
- Encourages duplicate code

**Fix:**

- Replace Parameter with Method Call
- Preserve Whole Object
- Introduce Parameter Object
- Builder pattern for many optional parameters

### Data Clumps

**Detection:**

- Same group of data items in multiple places
- Parameters that always travel together
- Fields that are always used together
- Deleting one makes others meaningless

**Impact:**

- Missed abstraction
- Duplication
- Lack of encapsulation

**Fix:**

- Extract Class for related data
- Introduce Parameter Object
- Preserve Whole Object

## Object-Orientation Abusers

### Switch Statements

**Detection:**

- Type checking with switch/if-else chains
- Same switch structure duplicated
- Adding new type requires multiple changes
- Centralized type-based dispatch

**Impact:**

- Violates OCP
- Scattered logic
- Hard to extend

**Fix:**

- Replace Conditional with Polymorphism
- Replace Type Code with State/Strategy
- Extract method then Move Method to appropriate class

### Temporary Field

**Detection:**

- Fields set only in certain circumstances
- Fields with null or default values most of the time
- Fields used only by subset of methods

**Impact:**

- Confusing object state
- Unexpected nulls
- Unclear lifecycle

**Fix:**

- Extract Class for related temporary fields
- Replace Method with Method Object
- Introduce Null Object

### Refused Bequest

**Detection:**

- Subclass uses only fraction of inherited methods
- Subclass throws exceptions from inherited methods
- Subclass overrides to do nothing
- "is-a" relationship doesn't hold

**Impact:**

- Violates LSP
- Misleading hierarchy
- Fragile inheritance

**Fix:**

- Replace Inheritance with Delegation
- Extract Subclass if only part is useful
- Push Down Method/Field to appropriate subclasses

### Alternative Classes with Different Interfaces

**Detection:**

- Classes do similar things but different method names
- Duplicate logic with different signatures
- Client code uses type checks to choose implementation

**Impact:**

- Missed polymorphism opportunity
- Duplication
- Unnecessary coupling

**Fix:**

- Rename Method for consistency
- Extract Superclass/Interface
- Move Method to align responsibilities

## Change Preventers

### Divergent Change

**Detection:**

- One class commonly changed in different ways for different reasons
- "I need to change these 3 methods for new database, these 4 methods for new report"
- Class has multiple reasons to change (violates SRP)

**Impact:**

- Violates SRP
- Increased coupling
- Fragile changes

**Fix:**

- Extract Class for each responsibility
- Single Responsibility Principle
- Separate concerns by volatility

### Shotgun Surgery

**Detection:**

- Single change requires modifications across many classes
- Related changes scattered throughout codebase
- Adding feature touches 10+ files

**Impact:**

- Hard to find all needed changes
- Easy to miss changes
- High coupling

**Fix:**

- Move Method/Field to centralize behavior
- Inline Class to consolidate
- Extract Class to create cohesive module

### Parallel Inheritance Hierarchies

**Detection:**

- Creating subclass in one hierarchy requires creating subclass in another
- Naming patterns match across hierarchies (FastX/SlowX, XHandler/XValidator)
- Hierarchies evolve together

**Impact:**

- Duplication of structure
- Coordination overhead
- Rigid design

**Fix:**

- Move Method/Field to collapse one hierarchy
- Use composition instead of parallel inheritance
- Merge hierarchies if closely related

## Dispensables

### Comments (as smell)

**Detection:**

- Comments explain what code does (not why)
- Comments compensate for bad names
- Commented-out code
- Redundant comments (restate code)

**Impact:**

- Outdated comments mislead
- Clutter
- Masked bad code

**Fix:**

- Extract Method with descriptive name
- Rename Method/Variable
- Introduce Assertion for assumptions
- Delete commented code (version control remembers)

### Duplicate Code

**Detection:**

- Same code structure in multiple places
- Copy-paste patterns
- Similar algorithms with minor variations

**Impact:**

- Maintenance burden (change in N places)
- Inconsistent fixes
- Bloat

**Fix:**

- Extract Method
- Pull Up Method to superclass
- Form Template Method
- Substitute Algorithm

### Lazy Class

**Detection:**

- Class does too little to justify existence
- Class is just wrapper around primitive/collection
- Class created for future that never came

**Impact:**

- Unnecessary complexity
- Extra indirection
- Cognitive load

**Fix:**

- Inline Class into caller
- Collapse Hierarchy if subclass too small
- Delete if truly unused

### Data Class

**Detection:**

- Class with only fields, getters, setters
- No behavior, just data container
- Other classes manipulate its data

**Impact:**

- Anemic domain model
- Logic scattered across codebase
- Violates encapsulation

**Fix:**

- Move Method from clients into data class
- Encapsulate Field/Collection
- Remove Setting Method if field shouldn't change

### Dead Code

**Detection:**

- Unreachable code (after return/throw)
- Unused parameters, variables, methods, classes
- Conditions that are always false
- Features behind permanent flags

**Impact:**

- Confuses readers
- Maintenance burden
- False complexity

**Fix:**

- Delete ruthlessly
- Version control remembers history
- Don't keep "just in case"

### Speculative Generality

**Detection:**

- "We might need this someday"
- Unused abstract classes/interfaces
- Parameters/methods for future features
- Overly complex design for current needs

**Impact:**

- YAGNI violation
- Unnecessary complexity
- Harder to understand

**Fix:**

- Collapse Hierarchy
- Inline Class/Method
- Remove unused parameters
- Simplify to actual requirements

## Couplers

### Feature Envy

**Detection:**

- Method uses more features of another class than its own
- Method accesses foreign data repeatedly
- Method belongs logically elsewhere

**Impact:**

- Wrong responsibility placement
- High coupling
- Scattered logic

**Fix:**

- Move Method to envied class
- Extract Method then Move Method
- Strategy/Visitor if bidirectional envy

### Inappropriate Intimacy

**Detection:**

- Classes access each other's private parts (fields/methods)
- Bidirectional dependencies
- Classes spend time together in private
- Inheritance for convenience, not "is-a"

**Impact:**

- High coupling
- Fragile to changes
- Violates encapsulation

**Fix:**

- Move Method/Field
- Extract Class for common interests
- Replace Inheritance with Delegation
- Hide Delegate to reduce coupling

### Message Chains

**Detection:**

- `a.getB().getC().getD().doSomething()`
- Long chains of method calls
- Client navigates object structure
- Law of Demeter violations

**Impact:**

- Fragile (change anywhere breaks chain)
- High coupling
- Exposed structure

**Fix:**

- Hide Delegate (intermediate objects hide structure)
- Extract Method for navigation
- Move behavior closer to data

### Middle Man

**Detection:**

- Class delegates most/all work to another class
- Thin wrapper with no added value
- Excessive delegation methods

**Impact:**

- Unnecessary indirection
- Maintenance overhead
- Confusion about ownership

**Fix:**

- Remove Middle Man
- Inline Method for simple delegation
- Replace Delegation with Inheritance if appropriate

## Detection Workflow

When reviewing code:

1. **Scan for Bloaters** - Look for size/complexity issues
2. **Check OO Principles** - Verify inheritance, polymorphism usage
3. **Identify Change Patterns** - Where do changes cluster? Where do they scatter?
4. **Find Dispensables** - What adds no value?
5. **Trace Coupling** - Who talks to whom too much?

**Remember:** Not every instance is a problem. Apply judgment based on context, team standards, and change frequency. Smells indicate potential issues, not guaranteed problems.

## References

- Clean Code (Robert C. Martin)
- Refactoring: Improving the Design of Existing Code (Martin Fowler)
- Working Effectively with Legacy Code (Michael Feathers)
