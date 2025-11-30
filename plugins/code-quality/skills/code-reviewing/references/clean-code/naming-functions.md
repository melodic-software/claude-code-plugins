# Clean Code: Naming and Functions

Deep-dive reference for Clean Code principles from Robert C. Martin's "Clean Code: A Handbook of Agile Software Craftsmanship."

## Naming Principles

### Intention-Revealing Names

Names should reveal intent without requiring comments.

**Bad:**

```python
d = 86400  # elapsed time in seconds
```

**Good:**

```python
elapsed_time_in_seconds = 86400
SECONDS_PER_DAY = 86400
```

**Bad:**

```csharp
public List<int[]> GetThem() {
    List<int[]> list1 = new List<int[]>();
    foreach (int[] x in theList)
        if (x[0] == 4)
            list1.Add(x);
    return list1;
}
```

**Good:**

```csharp
public List<Cell> GetFlaggedCells() {
    List<Cell> flaggedCells = new List<Cell>();
    foreach (Cell cell in gameBoard)
        if (cell.IsFlagged())
            flaggedCells.Add(cell);
    return flaggedCells;
}
```

### Avoid Disinformation

Don't use names that obscure meaning or mislead readers.

**Bad:**

```python
accounts_list = {}  # It's a dict, not a list!
hp = "Hewlett-Packard"  # hp could mean horsepower, hypotenuse, etc.
```

**Good:**

```python
accounts = {}
accounts_dict = {}
hewlett_packard_name = "Hewlett-Packard"
```

Avoid similar-looking names that differ only slightly:

- `XYZControllerForEfficientHandlingOfStrings`
- `XYZControllerForEfficientStorageOfStrings`

### Make Meaningful Distinctions

Don't add noise words or number series to satisfy compiler/interpreter.

**Bad:**

```java
public static void copyChars(char a1[], char a2[]) {
    for (int i = 0; i < a1.length; i++) {
        a2[i] = a1[i];
    }
}
```

**Good:**

```java
public static void copyChars(char source[], char destination[]) {
    for (int i = 0; i < source.length; i++) {
        destination[i] = source[i];
    }
}
```

**Noise words are redundant:**

- `ProductInfo` vs `ProductData` (what's the difference?)
- `NameString` (name is always a string)
- `CustomerObject` (object is implied)
- `TheCustomer` vs `Customer` (the adds no meaning)

### Use Pronounceable Names

If you can't pronounce it, you can't discuss it intelligently.

**Bad:**

```csharp
class DtaRcrd102 {
    private DateTime genymdhms;
    private DateTime modymdhms;
}
```

**Good:**

```csharp
class Customer {
    private DateTime generationTimestamp;
    private DateTime modificationTimestamp;
}
```

### Use Searchable Names

Single-letter names and numeric constants are hard to locate.

**Bad:**

```python
for i in range(34):
    s += (t[i] * 4) / 5
```

**Good:**

```python
WORK_DAYS_PER_WEEK = 5
NUMBER_OF_TASKS = 34

for task_number in range(NUMBER_OF_TASKS):
    real_days_per_task = task_estimate[task_number] * WORK_DAYS_PER_WEEK
    sum_of_task_estimates += real_days_per_task / WORK_DAYS_PER_WEEK
```

**Rule:** Length of name should correspond to size of scope. Single-letter names acceptable only for short loop counters.

### Avoid Encodings

Modern IDEs make Hungarian notation and type prefixes obsolete.

**Bad:**

```csharp
string m_strName;  // m_ prefix is noise
IShapeFactory factory;  // I prefix for interfaces
```

**Good:**

```csharp
string name;
ShapeFactory factory;  // Or use interface name without I
```

### Class Names: Nouns

Classes should have noun or noun phrase names.

**Good:** `Customer`, `WikiPage`, `Account`, `AddressParser`

**Bad:** `Manager`, `Processor`, `Data`, `Info` (too vague)

**Avoid:** Verb names for classes

### Method Names: Verbs

Methods should have verb or verb phrase names.

**Good:**

```csharp
payment.PostPayment();
employee.DeleteEmployee();
page.Save();
```

**Accessors, mutators, predicates:**

```csharp
string name = employee.GetName();
customer.SetName("John");
if (paycheck.IsPosted()) { }
```

### Pick One Word Per Concept

Use consistent vocabulary across codebase.

**Bad:**

```python
fetch_user()
retrieve_account()
get_product()  # All mean the same thing
```

**Good:**

```python
get_user()
get_account()
get_product()
```

**Don't mix:** `controller`, `manager`, and `driver` if they mean the same thing.

### Use Solution Domain Names

Use CS terms, algorithm names, pattern names, math terms.

**Good:**

```csharp
JobQueue  // Queue is a CS concept
AccountVisitor  // Visitor pattern
```

People reading your code are programmers. Use technical terms they know.

### Use Problem Domain Names

When no programmer term exists, use terms from problem domain.

**Good:**

```python
class PatientRecord:  # Healthcare domain
    diagnosis: str
    treatment_plan: str
```

### Add Meaningful Context

Most names need context. Provide it through well-named classes, functions, namespaces.

**Bad:**

```java
private void printGuessStatistics(char candidate, int count) {
    String number;
    String verb;
    String pluralModifier;
    // ... complex logic
}
```

**Good:**

```java
public class GuessStatisticsMessage {
    private String number;
    private String verb;
    private String pluralModifier;

    public String make(char candidate, int count) {
        createPluralDependentMessageParts(count);
        return String.format("There %s %s %s%s", verb, number, candidate, pluralModifier);
    }

    private void createPluralDependentMessageParts(int count) { }
}
```

## Functions Principles

### Small Functions

**First rule:** Functions should be small.
**Second rule:** They should be smaller than that.

**Target:** 2-4 lines is ideal, rarely more than 10 lines.

**Bad:**

```python
def process_order(order):
    # Validate order (20 lines)
    # Calculate totals (15 lines)
    # Apply discounts (25 lines)
    # Save to database (10 lines)
    # Send confirmation email (15 lines)
    # Update inventory (20 lines)
    pass  # 105 lines total
```

**Good:**

```python
def process_order(order):
    validate_order(order)
    totals = calculate_totals(order)
    apply_discounts(totals)
    save_order_to_database(order)
    send_confirmation_email(order)
    update_inventory(order)
```

### Do One Thing

**Rule:** Functions should do one thing. They should do it well. They should do it only.

**One thing:** One level of abstraction, one reason to change.

**Bad:**

```csharp
public void PayEmployees() {
    foreach (Employee e in employees) {
        if (e.IsPayday()) {
            Money pay = e.CalculatePay();
            // Format check (10 lines of formatting logic)
            // Print check (15 lines of printing logic)
            e.DeliverPay(pay);
        }
    }
}
```

**Good:**

```csharp
public void PayEmployees() {
    foreach (Employee e in employees) {
        PayIfNecessary(e);
    }
}

private void PayIfNecessary(Employee e) {
    if (e.IsPayday())
        CalculateAndDeliverPay(e);
}

private void CalculateAndDeliverPay(Employee e) {
    Money pay = e.CalculatePay();
    e.DeliverPay(pay);
}
```

### One Level of Abstraction

All statements in function should be at same level of abstraction.

**Bad:**

```python
def render_page_with_setups_and_teardowns(page_data):
    html = "<html>"  # Low level
    include_setup_pages(page_data)  # Medium level
    content = page_data.get_content()  # High level
    html += content  # Low level
    return html
```

**Good:**

```python
def render_page_with_setups_and_teardowns(page_data):
    html = render_html_header()
    html += include_setup_pages(page_data)
    html += include_page_content(page_data)
    html += include_teardown_pages(page_data)
    html += render_html_footer()
    return html
```

### The Stepdown Rule

Code should read like top-down narrative. Every function followed by those at next level of abstraction.

**Pattern:**

```text
To do X, we do A, B, and C.
  To do A, we do A1, A2, and A3.
    To do A1, we do A1a and A1b.
```

### Switch Statements and Polymorphism

Switch statements violate Single Responsibility Principle and Open/Closed Principle.

**Bad:**

```java
public Money calculatePay(Employee e) {
    switch (e.type) {
        case COMMISSIONED:
            return calculateCommissionedPay(e);
        case HOURLY:
            return calculateHourlyPay(e);
        case SALARIED:
            return calculateSalariedPay(e);
        default:
            throw new InvalidEmployeeType(e.type);
    }
}
```

**Good:**

```java
public abstract class Employee {
    public abstract Money calculatePay();
}

public class CommissionedEmployee extends Employee {
    public Money calculatePay() { /* implementation */ }
}

// Factory hides switch statement
public class EmployeeFactory {
    public Employee makeEmployee(EmployeeRecord r) {
        switch (r.type) {
            case COMMISSIONED:
                return new CommissionedEmployee(r);
            // ...
        }
    }
}
```

**Acceptable:** Switches buried in factory, creating polymorphic objects.

### Function Arguments

**Ideal:** Zero (niladic)
**Good:** One (monadic)
**Acceptable:** Two (dyadic)
**Avoid:** Three (triadic)
**Never:** More than three (polyadic)

**Why fewer is better:**

- Easier to test (fewer combinations)
- Easier to understand
- Easier to read

**Flag arguments are ugly:**

**Bad:**

```python
render(is_suite=True)  # What does True mean?
```

**Good:**

```python
render_for_suite()
render_single_test()
```

### Command Query Separation

Functions should either do something or answer something, not both.

**Bad:**

```java
public boolean set(String attribute, String value);

if (set("username", "unclebob")) { }  // Confusing! Does it check or set?
```

**Good:**

```java
if (attributeExists("username")) {
    setAttribute("username", "unclebob");
}
```

### Prefer Exceptions to Error Codes

Error codes force immediate handling and nested structures.

**Bad:**

```python
if (delete_page(page) == E_OK):
    if (registry.delete_reference(page.name) == E_OK):
        if (config_keys.delete_key(page.name.make_key()) == E_OK):
            logger.log("page deleted")
        else:
            logger.log("configKey not deleted")
    else:
        logger.log("deleteReference failed")
else:
    logger.log("delete failed")
```

**Good:**

```python
try:
    delete_page_and_all_references(page)
except Exception as e:
    logger.log(e.message)

def delete_page_and_all_references(page):
    delete_page(page)
    registry.delete_reference(page.name)
    config_keys.delete_key(page.name.make_key())
```

**Extract try/catch blocks:**

```python
def delete(page):
    try:
        delete_page_and_all_references(page)
    except Exception as e:
        log_error(e)

def delete_page_and_all_references(page):
    # Clean code without error handling clutter
    pass
```

### Don't Repeat Yourself (DRY)

Duplication is root of all evil in software.

**Bad:**

```csharp
public void ScaleToOneDimension(float desired, float imageDimension) {
    if (Math.Abs(desired - imageDimension) < epsilon)
        return;
    float scalingFactor = desired / imageDimension;
    scalingFactor = (float)(Math.Floor(scalingFactor * 100) * 0.01f);
    // Repeat same logic for another dimension
}
```

**Good:**

```csharp
public void ScaleToOneDimension(float desired, float imageDimension) {
    if (Math.Abs(desired - imageDimension) < epsilon)
        return;
    ApplyScaling(desired, imageDimension);
}

private void ApplyScaling(float desired, float actual) {
    float scalingFactor = CalculateScalingFactor(desired, actual);
    // Apply scaling
}
```

### Structured Programming

Dijkstra's rule: One entry, one exit.

**Modern interpretation:**

- Functions should be small enough that one return is natural
- Multiple returns acceptable if function is tiny and improves clarity
- Avoid break/continue in large functions
- Never use goto

**Acceptable:**

```python
def find_user(user_id):
    if not user_id:
        return None

    user = database.get_user(user_id)
    if not user:
        return None

    return user
```

## Summary

**Naming:**

- Use intention-revealing, pronounceable, searchable names
- Avoid encodings, noise words, disinformation
- Classes = nouns, Methods = verbs
- One word per concept, add meaningful context

**Functions:**

- Small (2-10 lines ideal)
- Do one thing at one level of abstraction
- 0-2 arguments ideal, avoid flags
- Command-query separation
- Exceptions over error codes
- DRY principle
- One entry, one exit (for small functions)

**Remember:** Clean code reads like well-written prose.

---

**Reference:** Robert C. Martin, "Clean Code: A Handbook of Agile Software Craftsmanship" (2008), Chapters 2-3
