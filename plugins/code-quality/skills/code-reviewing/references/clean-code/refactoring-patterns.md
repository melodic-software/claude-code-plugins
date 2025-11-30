# Refactoring Patterns

Comprehensive refactoring techniques from Martin Fowler's *Refactoring* and Robert C. Martin's *Clean Code*.

## Composing Methods

### Extract Method

**When to apply:** Method is too long or contains logic that needs naming for clarity.

**Before:**

```javascript
function printOwing(invoice) {
  console.log("***********************");
  console.log("**** Customer Owes ****");
  console.log("***********************");

  let outstanding = 0;
  for (const order of invoice.orders) {
    outstanding += order.amount;
  }

  console.log(`name: ${invoice.customer}`);
  console.log(`amount: ${outstanding}`);
}
```

**After:**

```javascript
function printOwing(invoice) {
  printBanner();
  const outstanding = calculateOutstanding(invoice);
  printDetails(invoice.customer, outstanding);
}

function printBanner() {
  console.log("***********************");
  console.log("**** Customer Owes ****");
  console.log("***********************");
}

function calculateOutstanding(invoice) {
  return invoice.orders.reduce((sum, order) => sum + order.amount, 0);
}

function printDetails(customer, outstanding) {
  console.log(`name: ${customer}`);
  console.log(`amount: ${outstanding}`);
}
```

**Benefits:** Improves readability, enables reuse, simplifies testing.

### Inline Method

**When to apply:** Method body is as clear as its name, or method is overly simple.

**Before:**

```python
def get_rating(driver):
    return 2 if more_than_five_late_deliveries(driver) else 1

def more_than_five_late_deliveries(driver):
    return driver.late_deliveries > 5
```

**After:**

```python
def get_rating(driver):
    return 2 if driver.late_deliveries > 5 else 1
```

**Benefits:** Reduces unnecessary indirection, simplifies code.

### Extract Variable

**When to apply:** Complex expression is hard to understand.

**Before:**

```javascript
if ((platform.toUpperCase().indexOf("MAC") > -1) &&
    (browser.toUpperCase().indexOf("IE") > -1) &&
    wasInitialized() && resize > 0) {
  // do something
}
```

**After:**

```javascript
const isMacOS = platform.toUpperCase().indexOf("MAC") > -1;
const isIEBrowser = browser.toUpperCase().indexOf("IE") > -1;
const wasResized = resize > 0;

if (isMacOS && isIEBrowser && wasInitialized() && wasResized) {
  // do something
}
```

**Benefits:** Makes expressions self-documenting, easier to debug.

### Replace Temp with Query

**When to apply:** Temporary variable holds result of expression that can be extracted.

**Before:**

```java
double calculateTotal() {
  double basePrice = quantity * itemPrice;
  if (basePrice > 1000)
    return basePrice * 0.95;
  else
    return basePrice * 0.98;
}
```

**After:**

```java
double calculateTotal() {
  if (basePrice() > 1000)
    return basePrice() * 0.95;
  else
    return basePrice() * 0.98;
}

double basePrice() {
  return quantity * itemPrice;
}
```

**Benefits:** Enables reuse, clarifies intent, prepares for Extract Method.

### Split Temporary Variable

**When to apply:** Temporary variable assigned multiple times for different purposes.

**Before:**

```python
temp = 2 * (height + width)
print(f"Perimeter: {temp}")
temp = height * width
print(f"Area: {temp}")
```

**After:**

```python
perimeter = 2 * (height + width)
print(f"Perimeter: {perimeter}")
area = height * width
print(f"Area: {area}")
```

**Benefits:** Each variable has single clear purpose.

## Moving Features

### Move Method

**When to apply:** Method uses more features of another class than its own.

**Before:**

```java
class Account {
  double overdraftCharge() {
    if (type.isPremium()) {
      return 10 - daysOverdrawn * 0.5;
    }
    return 10 + daysOverdrawn * 1.75;
  }
}
```

**After:**

```java
class Account {
  double overdraftCharge() {
    return type.overdraftCharge(daysOverdrawn);
  }
}

class AccountType {
  double overdraftCharge(int daysOverdrawn) {
    if (isPremium()) {
      return 10 - daysOverdrawn * 0.5;
    }
    return 10 + daysOverdrawn * 1.75;
  }
}
```

**Benefits:** Improves cohesion, reduces coupling.

### Extract Class

**When to apply:** Class is doing work of two or more classes.

**Before:**

```javascript
class Person {
  constructor(name, officeAreaCode, officeNumber) {
    this.name = name;
    this.officeAreaCode = officeAreaCode;
    this.officeNumber = officeNumber;
  }

  getTelephoneNumber() {
    return `(${this.officeAreaCode}) ${this.officeNumber}`;
  }
}
```

**After:**

```javascript
class Person {
  constructor(name, areaCode, number) {
    this.name = name;
    this.telephoneNumber = new TelephoneNumber(areaCode, number);
  }

  getTelephoneNumber() {
    return this.telephoneNumber.toString();
  }
}

class TelephoneNumber {
  constructor(areaCode, number) {
    this.areaCode = areaCode;
    this.number = number;
  }

  toString() {
    return `(${this.areaCode}) ${this.number}`;
  }
}
```

**Benefits:** Better separation of concerns, easier to maintain.

### Inline Class

**When to apply:** Class does too little to justify existence.

**Benefits:** Reduces unnecessary abstraction, simplifies codebase.

### Hide Delegate

**When to apply:** Client calls method on object returned by another object.

**Before:**

```python
manager = employee.department.manager
```

**After:**

```python
manager = employee.get_manager()

class Employee:
    def get_manager(self):
        return self.department.manager
```

**Benefits:** Reduces coupling, encapsulates structure.

## Organizing Data

### Encapsulate Field

**When to apply:** Public field should be accessed through methods.

**Before:**

```java
public String name;
```

**After:**

```java
private String name;

public String getName() {
  return name;
}

public void setName(String name) {
  this.name = name;
}
```

**Benefits:** Enables validation, easier to modify implementation.

### Replace Magic Number with Constant

**When to apply:** Literal numbers have special meaning.

**Before:**

```javascript
const potentialEnergy = mass * 9.81 * height;
```

**After:**

```javascript
const GRAVITATIONAL_CONSTANT = 9.81;
const potentialEnergy = mass * GRAVITATIONAL_CONSTANT * height;
```

**Benefits:** Self-documenting, single source of truth.

## Simplifying Conditional Expressions

### Decompose Conditional

**When to apply:** Complex conditional logic obscures intent.

**Before:**

```python
if date.before(SUMMER_START) or date.after(SUMMER_END):
    charge = quantity * winter_rate + winter_service_charge
else:
    charge = quantity * summer_rate
```

**After:**

```python
if is_not_summer(date):
    charge = winter_charge(quantity)
else:
    charge = summer_charge(quantity)
```

**Benefits:** Intention-revealing, easier to test.

### Consolidate Conditional

**When to apply:** Multiple conditionals with same result.

**Before:**

```javascript
if (isSpecialDeal()) return price * 0.95;
if (quantity > 100) return price * 0.95;
return price;
```

**After:**

```javascript
if (isSpecialDeal() || quantity > 100) {
  return price * 0.95;
}
return price;
```

**Benefits:** Reduces duplication, clarifies logic.

### Replace Nested Conditional with Guard Clauses

**When to apply:** Nested conditionals obscure normal flow.

**Before:**

```java
double getPayAmount() {
  if (isDead) {
    return deadAmount();
  } else {
    if (isSeparated) {
      return separatedAmount();
    } else {
      if (isRetired) {
        return retiredAmount();
      } else {
        return normalPayAmount();
      }
    }
  }
}
```

**After:**

```java
double getPayAmount() {
  if (isDead) return deadAmount();
  if (isSeparated) return separatedAmount();
  if (isRetired) return retiredAmount();
  return normalPayAmount();
}
```

**Benefits:** Emphasizes exceptional cases, improves readability.

### Replace Conditional with Polymorphism

**When to apply:** Conditional behavior varies by type.

**Before:**

```python
def get_speed(bird_type):
    if bird_type == "EUROPEAN":
        return get_base_speed()
    elif bird_type == "AFRICAN":
        return get_base_speed() - get_load_factor()
    elif bird_type == "NORWEGIAN_BLUE":
        return 0 if is_nailed else get_base_speed()
```

**After:**

```python
class EuropeanBird:
    def get_speed(self):
        return self.get_base_speed()

class AfricanBird:
    def get_speed(self):
        return self.get_base_speed() - self.get_load_factor()

class NorwegianBlueBird:
    def get_speed(self):
        return 0 if self.is_nailed else self.get_base_speed()
```

**Benefits:** Extensible, type-safe, follows Open-Closed Principle.

### Introduce Null Object

**When to apply:** Repeated null checks clutter code.

**Before:**

```javascript
if (customer === null) {
  plan = BillingPlan.basic();
} else {
  plan = customer.getPlan();
}
```

**After:**

```javascript
class NullCustomer {
  getPlan() {
    return BillingPlan.basic();
  }
}

plan = customer.getPlan();
```

**Benefits:** Eliminates null checks, simplifies client code.

## Simplifying Method Calls

### Rename Method

**When to apply:** Method name does not reveal purpose.

**Benefits:** Improves readability, self-documenting code.

### Add Parameter / Remove Parameter

**When to apply:** Method needs more/less information from caller.

**Benefits:** Right-sized interfaces, clearer dependencies.

### Separate Query from Modifier

**When to apply:** Method returns value AND changes state.

**Before:**

```java
String getTotalAndIncrementCount() {
  count++;
  return total;
}
```

**After:**

```java
String getTotal() {
  return total;
}

void incrementCount() {
  count++;
}
```

**Benefits:** Query methods are pure, easier to reason about.

### Introduce Parameter Object

**When to apply:** Group of parameters naturally belong together.

**Before:**

```python
def amount_invoiced(start_date, end_date):
    pass

def amount_received(start_date, end_date):
    pass
```

**After:**

```python
class DateRange:
    def __init__(self, start, end):
        self.start = start
        self.end = end

def amount_invoiced(date_range):
    pass

def amount_received(date_range):
    pass
```

**Benefits:** Reduces parameter lists, groups related data.

## When to Refactor

- Before adding new features (clean the kitchen before cooking)
- During code review (improve as you read)
- When you understand code better than original author
- When fixing bugs (make code easier to debug)
- During regular maintenance (prevent decay)

**Never refactor and add features simultaneously** - separate concerns.

## Resources

- *Refactoring: Improving the Design of Existing Code* by Martin Fowler
- *Clean Code: A Handbook of Agile Software Craftsmanship* by Robert C. Martin
- [Refactoring.com](https://refactoring.com/) - Comprehensive catalog

**Last Updated:** 2025-11-28
