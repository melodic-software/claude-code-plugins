# Code Review Checklist - Detailed Reference

Extended checklist with detection patterns, code examples, and fix guidance based on Google Engineering Practices, OWASP, and modern development standards.

## 1. Design and Architecture

### 1.1 SOLID Principles Detection

#### Single Responsibility Principle (SRP)

**Detection:** Class/function does multiple unrelated things.

```python
# BAD: Class handles both user data AND email sending
class UserManager:
    def create_user(self, data): ...
    def update_user(self, id, data): ...
    def send_welcome_email(self, user): ...  # Different responsibility
    def send_password_reset(self, user): ...  # Different responsibility

# GOOD: Separate responsibilities
class UserRepository:
    def create(self, data): ...
    def update(self, id, data): ...

class EmailService:
    def send_welcome(self, user): ...
    def send_password_reset(self, user): ...
```

#### Open-Closed Principle (OCP)

**Detection:** Long if/else or switch statements for type handling.

```python
# BAD: Must modify function to add new payment types
def process_payment(payment):
    if payment.type == "credit":
        # process credit
    elif payment.type == "debit":
        # process debit
    elif payment.type == "crypto":  # Added later - modification!
        # process crypto

# GOOD: Extend via new classes
class PaymentProcessor(ABC):
    @abstractmethod
    def process(self, payment): ...

class CreditProcessor(PaymentProcessor): ...
class DebitProcessor(PaymentProcessor): ...
class CryptoProcessor(PaymentProcessor): ...  # Extension, not modification
```

#### Liskov Substitution Principle (LSP)

**Detection:** Explicit type casting, isinstance checks, methods that throw NotImplemented.

```python
# BAD: Derived class can't substitute base
class Bird:
    def fly(self): ...

class Penguin(Bird):
    def fly(self):
        raise NotImplementedError("Penguins can't fly")  # LSP violation!

# GOOD: Better abstraction
class Bird:
    def move(self): ...

class FlyingBird(Bird):
    def fly(self): ...

class Penguin(Bird):
    def move(self):
        self.swim()
```

#### Interface Segregation Principle (ISP)

**Detection:** Clients forced to implement methods they don't use.

```python
# BAD: Fat interface
class Worker(ABC):
    @abstractmethod
    def work(self): ...
    @abstractmethod
    def eat(self): ...
    @abstractmethod
    def sleep(self): ...

class Robot(Worker):
    def work(self): ...
    def eat(self): pass  # Robots don't eat - forced to implement
    def sleep(self): pass  # Robots don't sleep - forced to implement

# GOOD: Segregated interfaces
class Workable(ABC):
    @abstractmethod
    def work(self): ...

class Eatable(ABC):
    @abstractmethod
    def eat(self): ...

class Robot(Workable): ...  # Only implements what it needs
```

#### Dependency Inversion Principle (DIP)

**Detection:** Direct instantiation with `new`, hardcoded dependencies.

```python
# BAD: High-level depends on low-level
class OrderService:
    def __init__(self):
        self.db = MySQLDatabase()  # Hardcoded dependency
        self.mailer = SMTPMailer()  # Hardcoded dependency

# GOOD: Depend on abstractions
class OrderService:
    def __init__(self, db: Database, mailer: Mailer):
        self.db = db
        self.mailer = mailer
```

### 1.2 Over-Engineering Detection

**Red flags:**

- Generic solutions for specific problems
- Premature abstraction (only one implementation)
- "Future-proofing" without current need
- Complex design patterns for simple problems

```python
# BAD: Over-engineered for a simple task
class AbstractDataProcessorFactoryBuilder:
    def create_processor_factory(self): ...

# GOOD: Simple and direct
def process_data(data):
    return [transform(item) for item in data]
```

## 2. Security (OWASP-Based)

### 2.1 Injection Prevention

#### SQL Injection

**Detection patterns:**

```bash
# Find string concatenation in queries
grep -rn "SELECT.*\+\|INSERT.*\+\|UPDATE.*\+\|DELETE.*\+" .
grep -rn "f\"SELECT\|f\"INSERT\|f\"UPDATE\|f\"DELETE" .
grep -rn '`SELECT\|`INSERT\|`UPDATE\|`DELETE' .
```

```python
# BAD: SQL injection vulnerable
query = f"SELECT * FROM users WHERE username = '{username}'"
cursor.execute(query)

# GOOD: Parameterized query
query = "SELECT * FROM users WHERE username = %s"
cursor.execute(query, (username,))
```

#### Command Injection

```python
# BAD: Command injection
os.system(f"ping {user_input}")
subprocess.call(f"convert {filename}", shell=True)

# GOOD: Safe command execution
subprocess.run(["ping", "-c", "4", validated_host], shell=False)
```

#### XSS (Cross-Site Scripting)

```javascript
// BAD: XSS vulnerable
element.innerHTML = userInput;
document.write(userInput);

// GOOD: Safe rendering
element.textContent = userInput;
// Or use framework escaping
```

### 2.2 Authentication and Session

**Checklist:**

- [ ] Login only via POST
- [ ] Secure cookie flags (HttpOnly, Secure, SameSite)
- [ ] Session regeneration after login
- [ ] Proper logout (server-side session invalidation)
- [ ] Rate limiting on auth endpoints
- [ ] MFA for sensitive operations

### 2.3 Secrets Detection

```bash
# Find hardcoded secrets
grep -rn "password\s*=\s*['\"]" .
grep -rn "api_key\s*=\s*['\"]" .
grep -rn "secret\s*=\s*['\"]" .
grep -rn "token\s*=\s*['\"]" .
grep -rn "-----BEGIN.*KEY-----" .
```

### 2.4 Cryptography

**Bad patterns:**

- MD5 or SHA1 for passwords
- ECB mode for encryption
- Hardcoded IVs
- Custom crypto implementations

```python
# BAD: Weak hashing
import hashlib
password_hash = hashlib.md5(password.encode()).hexdigest()

# GOOD: Modern password hashing
import bcrypt
password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
```

## 3. Concurrency and Thread Safety

### 3.1 Race Condition Detection

**Red flags:**

- Shared mutable state without synchronization
- Check-then-act patterns without locks
- Non-atomic compound operations

```python
# BAD: Race condition (check-then-act)
if not self.cache.has(key):  # Thread A checks
    # Thread B could insert here
    self.cache.set(key, compute_value())  # Thread A overwrites

# GOOD: Atomic operation
self.cache.setdefault(key, compute_value())  # Or use lock
```

### 3.2 Deadlock Prevention

**Detection:**

- Multiple locks acquired in different orders
- Holding lock while waiting for I/O
- Circular resource dependencies

```python
# BAD: Deadlock potential (different lock order)
# Thread 1: lock_a -> lock_b
# Thread 2: lock_b -> lock_a

# GOOD: Consistent lock ordering (always a before b)
def transfer(from_account, to_account, amount):
    first, second = sorted([from_account, to_account], key=id)
    with first.lock:
        with second.lock:
            # transfer logic
```

### 3.3 Async Patterns

```python
# BAD: Unawaited coroutine (silent failure)
async def handle():
    save_to_db(data)  # Missing await - fire and forget

# GOOD: Properly awaited
async def handle():
    await save_to_db(data)

# BAD: Blocking call in async context
async def fetch_data():
    requests.get(url)  # Blocks event loop!

# GOOD: Use async libraries
async def fetch_data():
    async with aiohttp.ClientSession() as session:
        await session.get(url)
```

## 4. Performance

### 4.1 N+1 Query Detection

```python
# BAD: N+1 queries
for user in users:
    orders = db.query(f"SELECT * FROM orders WHERE user_id = {user.id}")

# GOOD: Single query with join or batch
orders = db.query("SELECT * FROM orders WHERE user_id IN (...)")
# Or use ORM eager loading
users = User.query.options(joinedload(User.orders)).all()
```

### 4.2 Memory Efficiency

```python
# BAD: Loading everything into memory
all_records = list(db.query("SELECT * FROM huge_table"))

# GOOD: Streaming/pagination
for batch in db.query("SELECT * FROM huge_table").yield_per(1000):
    process(batch)
```

### 4.3 Algorithm Complexity

**Red flags:**

- Nested loops over same data (O(n^2) when O(n) possible)
- Repeated calculations inside loops
- Linear search when hash lookup possible

```python
# BAD: O(n^2) - nested iteration
for item in items:
    if item.id in [x.id for x in other_items]:  # Creates list each iteration
        ...

# GOOD: O(n) - use set
other_ids = {x.id for x in other_items}
for item in items:
    if item.id in other_ids:
        ...
```

## 5. Error Handling

### 5.1 Anti-Patterns

```python
# BAD: Silent failure
try:
    risky_operation()
except:
    pass

# BAD: Catch-all without logging
try:
    risky_operation()
except Exception:
    return default_value

# GOOD: Specific handling with logging
try:
    risky_operation()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
    raise  # Or handle appropriately
```

### 5.2 Error Message Quality

```python
# BAD: Unhelpful error
raise ValueError("Invalid input")

# GOOD: Actionable error
raise ValueError(
    f"Expected positive integer for 'count', got {count!r}. "
    "Provide a value > 0."
)
```

## 6. Testing

### 6.1 Test Quality Checks

- [ ] Tests actually assert something meaningful
- [ ] Tests would fail if code broke
- [ ] Edge cases covered (null, empty, boundary)
- [ ] No test interdependencies
- [ ] No flaky timing-dependent tests
- [ ] Tests are maintainable (not overly complex)

### 6.2 Test Smells

```python
# BAD: Test that always passes
def test_something():
    result = do_something()
    assert True  # Never fails!

# BAD: Testing implementation, not behavior
def test_internal_method():
    obj._internal_method()  # Testing private method

# GOOD: Testing behavior
def test_user_creation():
    user = create_user("test@example.com")
    assert user.email == "test@example.com"
    assert user.is_active is True
```

## 7. Cross-Platform Compatibility

### 7.1 Detection Patterns

```bash
# Find hardcoded paths
grep -rn "/mnt/c/" .
grep -rn "'/c/" .
grep -rn '"/c/' .
grep -rn "C:\\\\" .
grep -rn "/home/[a-z]" .
grep -rn "/Users/[A-Z]" .
```

### 7.2 Portable Patterns

**Tool detection:**

```bash
# BAD: Platform-specific hunting
if [[ -f "/c/ProgramData/chocolatey/bin/tool.exe" ]]; then
    TOOL="/c/ProgramData/chocolatey/bin/tool.exe"
fi

# GOOD: Portable
if command -v tool &>/dev/null; then
    # tool is available
fi
```

**Script self-location:**

```bash
# Bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

```python
# Python
from pathlib import Path
SCRIPT_DIR = Path(__file__).resolve().parent
```

```powershell
# PowerShell
$ScriptDir = $PSScriptRoot
```

## 8. Anti-Duplication

### 8.1 Detection Methods

```bash
# Compare two files
diff file1.yaml file2.yaml
# No output = identical = violation

# Find duplicate files in directory
find . -type f -name "*.yaml" -exec md5sum {} \; | sort | uniq -d -w 32

# Check for copy-paste across files
grep -l "specific phrase" *.md | wc -l
# If > 1, likely duplication
```

### 8.2 Common Violations

| Violation | Detection | Fix |
| --------- | --------- | --- |
| `config.yaml` = `hook.yaml` | `diff config.yaml hook.yaml` | Give each file distinct purpose |
| Same instructions in multiple docs | grep for key phrases | Single source + links |
| Version info in multiple places | grep for version pattern | One "Last Verified" section |

## 9. Code Smells Quick Reference

| Smell | Detection | Impact |
| ----- | --------- | ------ |
| Long method | > 20-30 lines | Maintainability |
| Long parameter list | > 3-4 params | Usability |
| Deep nesting | > 3-4 levels | Readability |
| Magic numbers | Hardcoded values | Maintainability |
| God class | Too many responsibilities | Testability |
| Feature envy | Method uses other class's data more | Coupling |
| Data clumps | Same data groups appear together | Abstraction |
| Primitive obsession | Primitives instead of small objects | Type safety |
| Duplicate code | Same logic in multiple places | DRY violation |
| Dead code | Unreachable or unused code | Clutter |

## 10. Review Process Best Practices

### 10.1 Before Reviewing

1. Understand the context - what problem is being solved?
2. Check for linked issues/tickets
3. Review the PR description
4. Identify high-risk areas (security, concurrency, core logic)

### 10.2 During Review

1. Start with design and architecture
2. Move to functionality and logic
3. Check security implications
4. Verify tests exist and are meaningful
5. Review for performance concerns
6. Check code style and consistency

### 10.3 Feedback Guidelines

- **Be specific** - Reference exact lines
- **Explain why** - Not just what's wrong
- **Suggest fixes** - Provide concrete alternatives
- **Use severity prefixes**:
  - `CRITICAL:` Must fix before merge
  - `WARNING:` Should fix, can discuss
  - `Nit:` Optional improvement

### 10.4 Google's Key Principles

1. **Technical facts > opinions** - Base feedback on principles, not preferences
2. **Style guide is authority** - For style questions, defer to guide
3. **Seek improvement, not perfection** - Approve code that improves health
4. **Don't block on nits** - Prefix with "Nit:" for optional items
5. **Encourage and appreciate** - Acknowledge good practices

## 11. Automation vs Manual Review

### Automate These

- Code formatting and style
- Test coverage thresholds
- Build success and syntax errors
- Security vulnerabilities in dependencies
- License compliance
- Static analysis (linting)

### Manual Review Focus

- Architecture decisions
- Business logic correctness
- Code readability and clarity
- Naming quality
- Performance optimization
- Security logic (auth, crypto)
- Concurrency correctness

## 12. Accessibility (WCAG 2.1 AA)

### 12.1 Detection Patterns

```bash
# Find images without alt text
grep -rn "<img" . | grep -v "alt="

# Find click handlers on non-interactive elements
grep -rn "onClick\|@click\|v-on:click" . | grep -E "div|span" | grep -v "role="

# Find focus issues
grep -rn "outline:\s*none\|outline:\s*0" .
```

### 12.2 Common Violations

```html
<!-- BAD: Missing alt text -->
<img src="logo.png">

<!-- GOOD: Descriptive alt text -->
<img src="logo.png" alt="Company Logo">

<!-- GOOD: Decorative image -->
<img src="decorative-line.png" alt="">

<!-- BAD: Non-semantic button -->
<div onclick="submit()">Submit</div>

<!-- GOOD: Semantic button -->
<button onclick="submit()">Submit</button>

<!-- BAD: No focus indicator -->
button:focus { outline: none; }

<!-- GOOD: Visible focus -->
button:focus { outline: 2px solid #0066cc; }
```

### 12.3 Color Contrast

- Normal text: minimum 4.5:1 ratio
- Large text (18pt+ or 14pt bold): minimum 3:1 ratio
- UI components: minimum 3:1 ratio
- Use tools: Chrome DevTools, axe DevTools, WAVE

## 13. Internationalization (i18n)

### 13.1 Detection Patterns

```bash
# Find hardcoded user-facing strings
grep -rn "\"[A-Z][a-z].*\"" . --include="*.js" --include="*.ts" --include="*.tsx"

# Find string concatenation with variables (bad for i18n)
grep -rn "\+ .*name\|name.* \+" . --include="*.js"

# Find direct pluralization
grep -rn "count.*item\|item.*count" . --include="*.js"
```

### 13.2 Common Violations

```javascript
// BAD: Hardcoded strings
const message = "Welcome to our site!";
button.textContent = "Submit";

// GOOD: Externalized strings
const message = t('welcome.message');
button.textContent = t('form.submit');

// BAD: String concatenation (breaks in languages with different word order)
const greeting = "Hello " + userName + "!";

// GOOD: Parameterized message
const greeting = t('greeting', { name: userName });

// BAD: Naive pluralization
const text = count + " items";

// GOOD: Proper pluralization
const text = t('items.count', { count });
```

### 13.3 Date/Number Formatting

```javascript
// BAD: Hardcoded format
const date = `${month}/${day}/${year}`;
const price = "$" + amount.toFixed(2);

// GOOD: Locale-aware formatting
const date = new Intl.DateTimeFormat(locale).format(dateObj);
const price = new Intl.NumberFormat(locale, {
  style: 'currency',
  currency: currency
}).format(amount);
```

## 14. Observability

### 14.1 Detection Patterns

```bash
# Find unstructured logging
grep -rn "console.log\|print(\|System.out.print" .

# Find missing trace context
grep -rn "fetch(\|axios\.\|http\." . | grep -v "traceId\|trace-id\|X-Request-ID"

# Find missing error context in logs
grep -rn "logger.error\|log.error" . | grep -v "context\|metadata\|traceId"
```

### 14.2 Logging Best Practices

```python
# BAD: Unstructured logging
print(f"User {user_id} logged in")
logger.info("Processing order")

# GOOD: Structured logging with context
logger.info("user.login", extra={
    "user_id": user_id,
    "trace_id": trace_id,
    "timestamp": datetime.utcnow().isoformat()
})

# GOOD: Include correlation IDs
logger.info("order.processing", extra={
    "order_id": order.id,
    "trace_id": request.headers.get("X-Trace-ID"),
    "span_id": generate_span_id()
})
```

### 14.3 Health Checks

```python
# BAD: No health checks or simple ping
@app.get("/health")
def health():
    return {"status": "ok"}

# GOOD: Comprehensive health check
@app.get("/health")
def health():
    return {
        "status": "healthy",
        "checks": {
            "database": check_database(),
            "cache": check_redis(),
            "external_api": check_external_service()
        },
        "version": app_version,
        "uptime_seconds": get_uptime()
    }
```

## 15. Data Privacy (GDPR/CCPA)

### 15.1 Detection Patterns

```bash
# Find PII in logs
grep -rn "logger\.\|log\." . | grep -iE "email|phone|ssn|password|address|credit.?card"

# Find unencrypted PII storage
grep -rn "save\|insert\|store" . | grep -iE "email|phone|ssn|dob|address"

# Find missing consent checks
grep -rn "sendEmail\|sendSMS\|track\|analytics" . | grep -v "consent\|permission"
```

### 15.2 Common Violations

```python
# BAD: Logging PII
logger.info(f"User registered: {user.email}, phone: {user.phone}")

# GOOD: Redact or hash PII
logger.info(f"User registered: {hash_pii(user.email)}")

# BAD: No consent check
def send_marketing_email(user):
    email_service.send(user.email, marketing_content)

# GOOD: Check consent
def send_marketing_email(user):
    if user.marketing_consent:
        email_service.send(user.email, marketing_content)
```

### 15.3 Data Retention

```python
# BAD: No retention policy
def store_user_data(data):
    db.insert(data)

# GOOD: With retention metadata
def store_user_data(data):
    db.insert({
        **data,
        "created_at": datetime.utcnow(),
        "retention_until": datetime.utcnow() + timedelta(days=730),
        "deletion_eligible": False
    })
```

## 16. API Design

### 16.1 Detection Patterns

```bash
# Find inconsistent error responses
grep -rn "return.*error\|throw\|raise" . --include="*controller*" --include="*handler*"

# Find missing API versioning
grep -rn "@app.route\|@router\|app.get\|app.post" . | grep -v "/v[0-9]/"

# Find removed fields (breaking changes)
git diff HEAD~10 -- "**/schema*" "**/model*" | grep "^-.*:"
```

### 16.2 Versioning Best Practices

```python
# GOOD: URL versioning
@app.route("/v1/users")
@app.route("/v2/users")

# GOOD: Header versioning
@app.before_request
def check_api_version():
    version = request.headers.get("API-Version", "v1")
```

### 16.3 Error Response Format

```python
# BAD: Inconsistent errors
return {"error": "Not found"}
return {"message": "Invalid input", "code": 400}
raise HTTPException(detail="Forbidden")

# GOOD: Consistent error format
def error_response(code, message, details=None):
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details,
            "timestamp": datetime.utcnow().isoformat(),
            "request_id": get_request_id()
        }
    }
```

## 17. Dependency Management

### 17.1 Detection Patterns

```bash
# Check for vulnerabilities (npm)
npm audit

# Check for vulnerabilities (Python)
pip-audit

# Check for outdated dependencies
npm outdated
pip list --outdated

# Find unpinned versions
grep -E "\"[^\"]+\":\s*\"[\^~]" package.json
grep -E "^[a-z].*>=" requirements.txt
```

### 17.2 Best Practices

```json
// BAD: Unpinned versions (package.json)
{
  "dependencies": {
    "lodash": "^4.17.0",
    "express": "~4.18.0"
  }
}

// GOOD: Pinned versions with lockfile
{
  "dependencies": {
    "lodash": "4.17.21",
    "express": "4.18.2"
  }
}
```

### 17.3 License Compliance

Check for incompatible licenses:

- GPL in proprietary code
- AGPL for SaaS without source disclosure
- Mixed commercial/open-source conflicts

## 18. Database Patterns

### 18.1 N+1 Detection

```python
# BAD: N+1 queries
users = User.query.all()
for user in users:
    orders = Order.query.filter_by(user_id=user.id).all()  # N queries!

# GOOD: Eager loading
users = User.query.options(joinedload(User.orders)).all()

# GOOD: Batch query
user_ids = [u.id for u in users]
orders = Order.query.filter(Order.user_id.in_(user_ids)).all()
```

### 18.2 Index Detection

```sql
-- Check missing indexes on foreign keys
SELECT
    tc.table_name,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
AND NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = tc.table_name
    AND indexdef LIKE '%' || kcu.column_name || '%'
);
```

### 18.3 Migration Safety

```python
# BAD: Dropping column immediately (data loss if rollback needed)
def upgrade():
    op.drop_column('users', 'legacy_field')

# GOOD: Multi-step deprecation
# Step 1: Add nullable new column
# Step 2: Migrate data
# Step 3: Mark old column as deprecated (code change)
# Step 4: Drop old column after verification period
```

## 19. Configuration Management

### 19.1 Detection Patterns

```bash
# Find hardcoded secrets
grep -rn "password\s*=\|secret\s*=\|api_key\s*=" . --include="*.py" --include="*.js"

# Find missing environment variable validation
grep -rn "os.environ\|process.env" . | grep -v "or\|??\|default\|getenv.*,"

# Find config in code instead of environment
grep -rn "localhost\|127.0.0.1\|:3000\|:5432" . --include="*.py" --include="*.js"
```

### 19.2 Best Practices

```python
# BAD: Hardcoded config
DATABASE_URL = "postgresql://user:pass@localhost/db"
API_KEY = "sk-1234567890"

# GOOD: Environment-based config with validation
from pydantic import BaseSettings

class Settings(BaseSettings):
    database_url: str
    api_key: str
    debug: bool = False

    class Config:
        env_file = ".env"

settings = Settings()  # Fails fast if required vars missing
```

### 19.3 Feature Flags

```python
# GOOD: Feature flag pattern
from feature_flags import is_enabled

def process_order(order):
    if is_enabled("new_payment_flow", user=order.user):
        return new_payment_process(order)
    return legacy_payment_process(order)
```

## 20. Cloud/Infrastructure (12-Factor)

### 20.1 Detection Patterns

```bash
# Find session state in process memory
grep -rn "session\[.*\]\s*=" . --include="*.py"
grep -rn "req.session\." . --include="*.js"

# Find file-based state
grep -rn "open(.*\"w\"\|fs.writeFile" . | grep -v "log\|tmp\|temp"

# Find missing graceful shutdown
grep -rn "SIGTERM\|SIGINT\|process.on.*signal" .
```

### 20.2 Stateless Processes

```python
# BAD: In-memory session storage
sessions = {}  # Lost on restart/scale

@app.route("/login")
def login():
    sessions[user_id] = session_data

# GOOD: External session store
from redis import Redis
redis = Redis.from_url(os.environ["REDIS_URL"])

@app.route("/login")
def login():
    redis.setex(f"session:{user_id}", 3600, session_data)
```

### 20.3 Graceful Shutdown

```python
import signal
import sys

def graceful_shutdown(signum, frame):
    logger.info("Shutting down gracefully...")
    # Close database connections
    db.close()
    # Finish current requests
    server.shutdown()
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)
signal.signal(signal.SIGINT, graceful_shutdown)
```

## 21. Frontend Patterns

### 21.1 Detection Patterns

```bash
# Find large components
wc -l src/components/**/*.tsx | sort -n | tail -20

# Find missing memoization on expensive renders
grep -rn "useMemo\|useCallback\|React.memo" . --include="*.tsx" | wc -l

# Check bundle size
npm run build -- --analyze
```

### 21.2 Component Design

```typescript
// BAD: Monolithic component
function Dashboard() {
  // 500 lines of code
  // Multiple responsibilities
}

// GOOD: Composed components
function Dashboard() {
  return (
    <DashboardLayout>
      <Header />
      <Sidebar />
      <MainContent>
        <MetricsPanel />
        <ActivityFeed />
      </MainContent>
    </DashboardLayout>
  );
}
```

### 21.3 Performance Optimization

```typescript
// BAD: Recreating objects on every render
function List({ items }) {
  const style = { padding: 10 };  // New object each render!
  return items.map(item => <Item style={style} />);
}

// GOOD: Memoized or static
const itemStyle = { padding: 10 };

function List({ items }) {
  return items.map(item => <Item style={itemStyle} />);
}

// GOOD: useMemo for computed values
function ExpensiveList({ items }) {
  const sortedItems = useMemo(
    () => items.slice().sort(complexSort),
    [items]
  );
  return sortedItems.map(item => <Item item={item} />);
}
```

## 22. Mobile Patterns

### 22.1 Detection Patterns

```bash
# Find blocking main thread operations
grep -rn "NetworkOnMainThread\|StrictMode" . --include="*.java" --include="*.kt"

# Find missing offline handling
grep -rn "fetch(\|axios\." . | grep -v "catch\|offline\|retry"

# Find hardcoded dimensions
grep -rn "width:\s*[0-9]+px\|height:\s*[0-9]+px" . --include="*.xml" --include="*.css"
```

### 22.2 Battery Efficiency

```kotlin
// BAD: Polling in foreground
while (true) {
    checkForUpdates()
    Thread.sleep(5000)
}

// GOOD: WorkManager for background work
val workRequest = PeriodicWorkRequestBuilder<SyncWorker>(
    15, TimeUnit.MINUTES
).setConstraints(
    Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .setRequiresBatteryNotLow(true)
        .build()
).build()

WorkManager.getInstance(context).enqueue(workRequest)
```

### 22.3 Offline-First

```typescript
// GOOD: Offline-first pattern
async function fetchData() {
  // Try cache first
  const cached = await cache.get('data');
  if (cached && !isStale(cached)) {
    return cached;
  }

  try {
    const fresh = await api.fetch('/data');
    await cache.set('data', fresh);
    return fresh;
  } catch (error) {
    if (cached) return cached;  // Fallback to stale cache
    throw error;
  }
}
```

## 23. AI/ML Code Patterns

### 23.1 Detection Patterns

```bash
# Find missing random seeds
grep -rn "random\.\|np.random\|torch.rand" . | grep -v "seed"

# Find hardcoded model paths
grep -rn "load_model\|from_pretrained" . | grep -E "\"/|\"\./"

# Find missing data validation
grep -rn "train\(|fit\(" . | grep -v "validate\|assert\|check"
```

### 23.2 Reproducibility

```python
# BAD: Non-reproducible training
model = train(data)

# GOOD: Reproducible with seeds and versioning
import random
import numpy as np
import torch

def set_seed(seed=42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)

set_seed(42)

# Track experiment
mlflow.log_params({
    "seed": 42,
    "model_version": "v1.2.3",
    "data_version": "2024-01-15"
})

model = train(data)
mlflow.log_model(model, "model")
```

### 23.3 Data Pipeline Validation

```python
# GOOD: Validate data before training
from great_expectations import expect

def validate_training_data(df):
    expect(df["label"].notna().all(), "No null labels")
    expect(df["feature_1"].between(-1, 1).all(), "Features normalized")
    expect(df["label"].value_counts().min() > 100, "Sufficient samples per class")

# GOOD: Monitor for drift
def check_data_drift(current_data, reference_data):
    for column in MONITORED_COLUMNS:
        ks_stat, p_value = ks_2samp(
            current_data[column],
            reference_data[column]
        )
        if p_value < 0.05:
            alert(f"Data drift detected in {column}")
```

## 24. Clean Code: Names (Robert C. Martin)

### 24.1 Detection Patterns

```bash
# Find single-letter variables (except loop counters)
grep -rn "\b[a-z]\s*=" . --include="*.py" --include="*.js" | grep -v "for\s*\(.*[ijk]\s*="

# Find Hungarian notation
grep -rn "\b(str|int|bool|arr|lst|dict)[A-Z]" . --include="*.py" --include="*.js"

# Find meaningless names
grep -rn "\b(data|info|temp|value|item|thing|stuff|obj)[0-9]*\b" .

# Find noise words
grep -rn "\b(the|a|an)[A-Z][a-zA-Z]*\b" . --include="*.py" --include="*.js"
```

### 24.2 Intention-Revealing Names

```python
# BAD: What does d mean?
d = 86400

# GOOD: Intention is clear
SECONDS_PER_DAY = 86400

# BAD: What is this list?
lst = get_them()

# GOOD: Reveals intent
flagged_cells = get_flagged_cells()
```

### 24.3 Avoid Disinformation

```python
# BAD: It's not actually a list
accountList = {}  # It's a dict!

# GOOD: Accurate naming
accounts = {}
account_map = {}

# BAD: Similar names, different meanings
XYZControllerForEfficientHandlingOfStrings
XYZControllerForEfficientStorageOfStrings

# GOOD: Distinct, meaningful names
StringFormatter
StringStorage
```

### 24.4 Pronounceable and Searchable Names

```python
# BAD: Can't pronounce, can't search
genymdhms = datetime.now()
modymdhms = None

# GOOD: Pronounceable and searchable
generation_timestamp = datetime.now()
modification_timestamp = None

# BAD: Single letter, unsearchable
for i in range(len(users)):
    e = users[i].email

# GOOD: Searchable
for user_index in range(len(users)):
    user_email = users[user_index].email
```

## 25. Clean Code: Functions (Robert C. Martin)

### 25.1 Detection Patterns

```bash
# Find long functions (> 30 lines)
grep -n "def \|function \|fn " . -r | while read line; do
  # Count lines until next function
done

# Find functions with many arguments
grep -rn "def.*,.*,.*,.*," . --include="*.py"
grep -rn "function.*,.*,.*,.*," . --include="*.js"

# Find flag arguments
grep -rn "def.*bool\|def.*flag\|def.*is_" . --include="*.py"
```

### 25.2 Small Functions

```python
# BAD: Function does too much (50+ lines)
def process_order(order):
    # Validate order (10 lines)
    # Check inventory (10 lines)
    # Calculate pricing (15 lines)
    # Process payment (10 lines)
    # Send notifications (10 lines)
    pass

# GOOD: Each function does one thing
def process_order(order):
    validate_order(order)
    check_inventory(order)
    calculate_pricing(order)
    process_payment(order)
    send_notifications(order)

def validate_order(order):
    # 5-10 lines
    pass
```

### 25.3 Few Arguments

```python
# BAD: Too many arguments
def create_user(name, email, phone, address, city, state, zip_code, country):
    pass

# GOOD: Use object
@dataclass
class UserAddress:
    street: str
    city: str
    state: str
    zip_code: str
    country: str

def create_user(name: str, email: str, address: UserAddress):
    pass

# BAD: Flag argument
def set_visibility(visible: bool):
    if visible:
        show()
    else:
        hide()

# GOOD: Separate functions
def show():
    pass

def hide():
    pass
```

### 25.4 Command-Query Separation

```python
# BAD: Does both (command AND query)
def set_and_check_username(name):
    self.username = name  # Command: changes state
    return self.username == name  # Query: returns value

# GOOD: Separate command and query
def set_username(name):
    self.username = name  # Command only

def username_is_set():
    return self.username is not None  # Query only
```

## 26. Clean Code: Comments (Robert C. Martin)

### 26.1 Detection Patterns

```bash
# Find commented-out code
grep -rn "^\s*#.*=\|^\s*//.*=\|^\s*#.*def\|^\s*//.*function" .

# Find redundant comments
grep -rn "# increment\|// increment\|# add 1\|// add 1" .

# Find TODO without ticket
grep -rn "TODO\|FIXME\|HACK\|XXX" . | grep -v "#[0-9]\|JIRA\|TICKET"

# Find closing brace comments
grep -rn "}\s*//\s*end\|}\s*#\s*end" .
```

### 26.2 Good vs Bad Comments

```python
# BAD: Redundant comment
i = i + 1  # Increment i by 1

# BAD: Commented-out code (delete it!)
# def old_function():
#     pass

# BAD: Journal comment
# 2024-01-15 Bob: Added validation
# 2024-01-16 Alice: Fixed bug

# GOOD: Explain WHY, not WHAT
# Use binary search because list is sorted and contains millions of items
index = binary_search(sorted_list, target)

# GOOD: Warning of consequences
# WARNING: This operation takes ~5 minutes on production data
def rebuild_index():
    pass

# GOOD: TODO with ticket reference
# TODO: JIRA-1234 - Replace with new API after v2 release
```

### 26.3 Self-Documenting Code

```python
# BAD: Comment explains what code does
# Check if employee is eligible for benefits
if employee.age > 65 or employee.tenure > 20 or employee.is_disabled:
    grant_benefits()

# GOOD: Code explains itself
def is_eligible_for_benefits(employee):
    is_senior = employee.age > 65
    has_long_tenure = employee.tenure > 20
    return is_senior or has_long_tenure or employee.is_disabled

if is_eligible_for_benefits(employee):
    grant_benefits()
```

## 27. Clean Code: Conditionals (Pragmatic Programmer)

### 27.1 Detection Patterns

```bash
# Find double negatives
grep -rn "!.*not\|not.*!\|!.*false\|false.*!" .

# Find negative conditions
grep -rn "if\s*(\s*!\|if\s*not\s" .

# Find deep nesting (4+ levels)
grep -rn "^\s\{16,\}if\|^\t\{4,\}if" .
```

### 27.2 Positive Conditions

```python
# BAD: Negative condition
if not is_invalid:
    process()

# GOOD: Positive condition
if is_valid:
    process()

# BAD: Double negative
if not user.is_not_authenticated:
    show_dashboard()

# GOOD: Clear positive
if user.is_authenticated:
    show_dashboard()
```

### 27.3 Guard Clauses

```python
# BAD: Deep nesting
def process_order(order):
    if order:
        if order.items:
            if order.is_paid:
                if order.customer.is_active:
                    # Finally, the actual logic
                    ship_order(order)

# GOOD: Guard clauses (early return)
def process_order(order):
    if not order:
        return
    if not order.items:
        return
    if not order.is_paid:
        return
    if not order.customer.is_active:
        return

    # Clean, focused logic
    ship_order(order)
```

### 27.4 Encapsulate Conditionals

```python
# BAD: Complex inline condition
if timer.has_expired() and not timer.is_recurrent and timer.owner == current_user:
    delete_timer(timer)

# GOOD: Encapsulated in descriptive function
def should_delete_timer(timer, current_user):
    is_expired = timer.has_expired()
    is_one_time = not timer.is_recurrent
    is_owned_by_user = timer.owner == current_user
    return is_expired and is_one_time and is_owned_by_user

if should_delete_timer(timer, current_user):
    delete_timer(timer)
```

## 28. Clean Code: Code Smells Detection

### 28.1 Bloaters Detection

```bash
# Long Method (> 30 lines)
# Count lines between function definitions

# Long Parameter List (> 4 params)
grep -rn "def.*,.*,.*,.*,.*," . --include="*.py"

# Data Clumps (same params appear together)
grep -rn "def.*name.*email.*phone" . --include="*.py"
```

### 28.2 Object-Orientation Abusers

```python
# BAD: Switch Statement Smell
def get_area(shape):
    if shape.type == "circle":
        return math.pi * shape.radius ** 2
    elif shape.type == "rectangle":
        return shape.width * shape.height
    elif shape.type == "triangle":
        return 0.5 * shape.base * shape.height

# GOOD: Polymorphism
class Shape(ABC):
    @abstractmethod
    def get_area(self): pass

class Circle(Shape):
    def get_area(self):
        return math.pi * self.radius ** 2

class Rectangle(Shape):
    def get_area(self):
        return self.width * self.height
```

### 28.3 Change Preventers

```python
# Shotgun Surgery Detection: One change touches many files
# If adding a new field requires changes in:
# - Model, Serializer, View, Form, Template, Test, Migration, API
# Consider consolidating or using abstractions

# Divergent Change Detection: One class changed for many reasons
# If UserService is modified for:
# - Authentication changes AND
# - Profile changes AND
# - Notification changes AND
# - Billing changes
# Split into separate services
```

### 28.4 Dispensables

```python
# Dead Code Detection
grep -rn "def " . | while read func; do
    # Check if function is called anywhere
done

# Speculative Generality Detection
# Look for:
# - Abstract classes with only one implementation
# - Parameters that are never used
# - Methods that only delegate to another method
grep -rn "pass  # TODO\|raise NotImplementedError" .
```

### 28.5 Couplers

```python
# BAD: Feature Envy (method uses other class's data)
class Order:
    def calculate_total(self):
        # Uses customer data extensively
        tax = self.customer.tax_rate * self.amount
        discount = self.customer.discount_rate * self.amount
        shipping = self.customer.shipping_zone.rate
        return self.amount + tax - discount + shipping

# GOOD: Move to where data lives
class Customer:
    def calculate_order_total(self, order):
        tax = self.tax_rate * order.amount
        discount = self.discount_rate * order.amount
        shipping = self.shipping_zone.rate
        return order.amount + tax - discount + shipping

# BAD: Message Chains (Law of Demeter violation)
user.get_department().get_manager().get_email()

# GOOD: Hide the chain
user.get_manager_email()
```

## Quick Reference Card

```text
ALWAYS CHECK:
[ ] Security: inputs validated, outputs encoded, no secrets
[ ] Concurrency: shared state protected, no race conditions
[ ] Design: SOLID principles, appropriate complexity
[ ] Tests: present, correct, useful
[ ] Platform: no hardcoded paths, portable detection
[ ] Duplicates: diff similar files
[ ] Accessibility: alt text, contrast, keyboard nav, semantic HTML
[ ] i18n: no hardcoded strings, locale-aware formatting
[ ] Observability: structured logs, metrics, traces, health checks

CLEAN CODE (Robert C. Martin):
[ ] Names: intention-revealing, pronounceable, searchable, no encodings
[ ] Functions: small (5-20 lines), do one thing, few args (0-2), no side effects
[ ] Comments: explain WHY not WHAT, no commented-out code, no redundancy
[ ] Conditionals: positive conditions, guard clauses, no double negatives

CODE SMELLS (watch for):
- Long methods (> 30 lines)
- Long parameter lists (> 4 params)
- Deep nesting (> 3-4 levels)
- God classes (too many responsibilities)
- Feature envy (method uses other class's data)
- Primitive obsession (should use value objects)
- Shotgun surgery (one change touches many files)

[ ] Privacy: PII protected, no PII in logs, consent tracked

DOMAIN-SPECIFIC (when applicable):
[ ] API: versioning, backward compat, error format
[ ] Database: N+1 avoided, indexes, migrations safe
[ ] Config: secrets in vault, feature flags, 12-factor
[ ] Frontend: component design, bundle size, web vitals
[ ] Mobile: battery/memory/network efficient, offline-first
[ ] AI/ML: model versioning, reproducibility, bias detection

RED FLAGS:
- Long if/else chains (OCP violation)
- Explicit type casting (LSP violation)
- new keyword overuse (DIP violation)
- String concatenation in queries (injection)
- Shared state without locks (race condition)
- Catch-all exception handlers (error hiding)
- Magic numbers/strings (maintainability)
- Platform-specific paths (portability)
- Missing alt text on images (accessibility)
- Hardcoded user-facing strings (i18n)
- console.log instead of structured logging (observability)
- PII in log statements (privacy violation)

NEVER:
- Say "looks good" without checklist
- Assume different names = different content
- Trust platform-specific code works elsewhere
- Minimize findings
```

---

**Sources:**

- [Google Engineering Practices](https://google.github.io/eng-practices/review/)
- [OWASP Secure Code Review Guide](https://owasp.org/www-project-code-review-guide/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [12-Factor App](https://12factor.net/)
- Robert C. Martin, "Clean Code: A Handbook of Agile Software Craftsmanship"
- Hunt & Thomas, "The Pragmatic Programmer"
- Martin Fowler, "Refactoring: Improving the Design of Existing Code"

**Last Updated:** 2025-11-28
