---
name: code-reviewing
description: Performs systematic code review with universal best practices and repo-specific standards. Auto-activates after significant code changes. Use when reviewing code, auditing files, checking PRs, examining staged changes, or when asked to "review", "check", "audit", or "examine" code. Enforces design principles (SOLID, DRY, KISS), security (OWASP), performance, concurrency safety, cross-platform compatibility, and codebase patterns.
allowed-tools: Read, Grep, Glob
---

# Code Reviewing

Systematic code review skill based on industry best practices from Google Engineering, OWASP, and modern development standards. Designed to catch issues that casual review misses through structured, checklist-driven analysis.

**Core Principle (Google):** Approve code that improves overall code health, even if not perfect. Seek continuous improvement, not perfection. But NEVER approve code that degrades code health.

## When to Use This Skill

**Auto-activation triggers:**

- After completing significant implementation tasks
- Before committing changes
- When reviewing PRs or staged files

**Explicit activation triggers:**

- User asks to "review", "check", "audit", or "examine" code
- User mentions "code review", "PR review", "look at this code"
- User asks about code quality or standards compliance

## Review Workflow

```text
Code Review Progress:
- [ ] Step 1: Identify scope (files to review)
- [ ] Step 2: Load context (repo standards if available)
- [ ] Step 3: Run Universal Checks (Layer 1)
- [ ] Step 4: Run Repo-Specific Checks (Layer 2, if CLAUDE.md exists)
- [ ] Step 5: Report ALL findings with severity
- [ ] Step 6: Propose specific fixes with rationale
```

### Step 1: Identify Scope

- **Explicit request**: User-specified files or changes
- **Staged changes**: `git diff --staged` or `git status`
- **Recent work**: Files modified in current session
- **PR scope**: All files in a pull request

### Step 2: Load Context

Check for repo-specific standards. If found, load for Layer 2 checks.

### Progressive Loading (Token Optimization)

This skill uses **tiered progressive disclosure** to optimize token usage. Only load what's relevant to the files being reviewed.

**Tier 1 (Always Applied):** Universal checks in this file (~4,000 tokens)

- Sections 1.1-1.12: Design, Logic, Security, Concurrency, Performance, Readability, Testing, Error Handling, Documentation, Cross-Platform, Anti-Duplication, Style
- Sections 1.25-1.29: Clean Code (Names, Functions, Comments, Conditionals, Code Smells)

**Tier 2 (File-Type Triggered):** Load based on file extensions

| Files | Load Reference |
| ----- | -------------- |
| .tsx, .jsx, .vue, .svelte | [references/tier-2/frontend-checks.md](references/tier-2/frontend-checks.md) |
| .py, .java, .cs, .go, .rb | [references/tier-2/backend-checks.md](references/tier-2/backend-checks.md) |
| .swift, .kt, .dart | [references/tier-2/mobile-checks.md](references/tier-2/mobile-checks.md) |
| .sql, migrations/* | [references/tier-2/database-checks.md](references/tier-2/database-checks.md) |
| .yaml, .json, .env, .toml | [references/tier-2/config-checks.md](references/tier-2/config-checks.md) |
| Dockerfile, *.tf, k8s/* | [references/tier-2/infrastructure-checks.md](references/tier-2/infrastructure-checks.md) |
| .ipynb, model/*, ml/* | [references/tier-2/ai-ml-checks.md](references/tier-2/ai-ml-checks.md) |

**Tier 3 (Content-Pattern Triggered):** Load when code contains specific patterns

| Pattern Keywords | Load Reference |
| ---------------- | -------------- |
| auth, crypto, password, secret, token, jwt | [references/tier-3/security-patterns.md](references/tier-3/security-patterns.md) |
| async, await, thread, lock, mutex, concurrent | [references/tier-3/concurrency-patterns.md](references/tier-3/concurrency-patterns.md) |
| route, endpoint, @app, @Get, @Post, api/ | [references/tier-3/api-patterns.md](references/tier-3/api-patterns.md) |
| PII, email, user, customer, gdpr, consent | [references/tier-3/privacy-patterns.md](references/tier-3/privacy-patterns.md) |

**Clean Code Deep-Dives:** Load for detailed guidance

- [references/clean-code/naming-functions.md](references/clean-code/naming-functions.md) - Full naming and function principles
- [references/clean-code/code-smells.md](references/clean-code/code-smells.md) - Complete code smell catalog
- [references/clean-code/refactoring-patterns.md](references/clean-code/refactoring-patterns.md) - Refactoring techniques

**Tier 4 (Repository-Specific):** Load when CLAUDE.md exists in repo root

| Context | Load Reference |
| ------- | -------------- |
| CLAUDE.md exists (always) | [references/tier-4/claude-md-core.md](references/tier-4/claude-md-core.md) |
| *.md files | [references/tier-4/documentation-rules.md](references/tier-4/documentation-rules.md) |
| Duplication indicators | [references/tier-4/anti-duplication-rules.md](references/tier-4/anti-duplication-rules.md) |
| Path patterns detected | [references/tier-4/path-rules.md](references/tier-4/path-rules.md) |
| *-{platform}.md files | [references/tier-4/platform-rules.md](references/tier-4/platform-rules.md) |
| .claude/skills/** | [references/tier-4/skill-rules.md](references/tier-4/skill-rules.md) |
| .claude/memory/** | [references/tier-4/memory-rules.md](references/tier-4/memory-rules.md) |
| .claude/temp/** | [references/tier-4/temp-file-rules.md](references/tier-4/temp-file-rules.md) |

**Token Budget Estimates:**

| Scenario | Tokens |
| -------- | ------ |
| Simple Python file | ~6,500 (Hub + backend) |
| React component | ~6,000 (Hub + frontend) |
| Auth service | ~8,000 (Hub + backend + security) |
| Full-stack PR | ~9,500 (Hub + frontend + backend + API) |
| Documentation file (CLAUDE.md repo) | ~6,500 (Hub + core-rules + documentation-rules) |
| Skill modification | ~6,000 (Hub + core-rules + skill-rules) |
| Memory file update | ~5,500 (Hub + core-rules + memory-rules) |

## Layer 1: Universal Code Review Checklist

These checks apply to ANY codebase, ANY language.

### 1.1 Design and Architecture

- [ ] **Overall design makes sense** - Interactions between components are logical
- [ ] **Belongs in this codebase** - Not better suited for a library or different module
- [ ] **Integrates well** - Fits with existing system architecture
- [ ] **Right time for this change** - Not premature or addressing wrong problem
- [ ] **No over-engineering** - Solves current problem, not speculative future needs (YAGNI)

**SOLID Principles:**

- [ ] **Single Responsibility (SRP)** - Each class/function has ONE reason to change
- [ ] **Open-Closed (OCP)** - Open for extension, closed for modification (no repeated if/else for types)
- [ ] **Liskov Substitution (LSP)** - Derived classes substitutable for base (no explicit type casting)
- [ ] **Interface Segregation (ISP)** - Clients depend only on methods they use
- [ ] **Dependency Inversion (DIP)** - Depend on abstractions, not concrete implementations

### 1.2 Functionality and Logic

- [ ] **Does what it's supposed to do** - Implements intended functionality
- [ ] **Good for users** - Both end-users AND developers who'll use this code
- [ ] **Edge cases handled** - Boundary conditions, empty inputs, nulls
- [ ] **Error handling robust** - Failures handled gracefully with actionable messages
- [ ] **No logic errors** - Off-by-one, wrong operators, incorrect conditions

### 1.3 Security (OWASP-Based)

- [ ] **Input validation** - All inputs validated server-side (allowlist, not blocklist)
- [ ] **Output encoding** - Context-appropriate encoding (HTML, JS, SQL, URL)
- [ ] **No injection vulnerabilities** - SQL, command, XSS, path traversal
- [ ] **Authentication correct** - Login via POST, secure session handling, MFA where appropriate
- [ ] **Authorization enforced** - Role-based access, principle of least privilege
- [ ] **Secrets not hardcoded** - No API keys, passwords, tokens in code
- [ ] **Secrets not logged** - No sensitive data in logs, error messages, URLs
- [ ] **Cryptography modern** - bcrypt/Argon2 for passwords, AES-GCM for encryption, no MD5/SHA1
- [ ] **Dependencies secure** - No known vulnerabilities in third-party libraries

### 1.4 Concurrency and Thread Safety

- [ ] **Shared state protected** - Proper locks, mutexes, or atomics for shared data
- [ ] **No race conditions** - Concurrent access patterns analyzed
- [ ] **Consistent lock ordering** - Locks acquired in same order to prevent deadlocks
- [ ] **No circular dependencies** - Between resources protected by different locks
- [ ] **Async patterns correct** - Await used properly, exceptions propagated
- [ ] **Thread-safe collections** - Concurrent collections used where needed
- [ ] **No deadlock potential** - Timeout mechanisms, no indefinite waits while holding locks

### 1.5 Performance and Efficiency

- [ ] **No unnecessary operations** - Efficient algorithms, no redundant work
- [ ] **Appropriate data structures** - Right choice for access patterns
- [ ] **No N+1 queries** - Database queries optimized
- [ ] **Memory efficient** - No leaks, appropriate caching
- [ ] **I/O optimized** - Async for I/O-bound, batching where appropriate
- [ ] **No blocking in async** - Sync operations not blocking async contexts

### 1.6 Complexity and Readability

- [ ] **Not more complex than needed** - Can be understood quickly
- [ ] **Functions/classes reasonable size** - Single responsibility, not too long
- [ ] **No deep nesting** - Max 3-4 levels of indentation
- [ ] **Clear naming** - Names fully communicate purpose without being too long
- [ ] **Comments explain WHY** - Not what (code should be self-documenting)
- [ ] **No code duplication** - DRY principle followed

### 1.7 Testing

- [ ] **Tests included** - Unit/integration tests appropriate for change
- [ ] **Tests are correct** - Actually test what they claim to test
- [ ] **Tests are useful** - Will fail when code breaks
- [ ] **Edge cases tested** - Boundary conditions, error scenarios
- [ ] **Tests maintainable** - Not overly complex, clear assertions
- [ ] **No flaky tests** - Deterministic, not timing-dependent

### 1.8 Error Handling and Logging

- [ ] **Errors caught appropriately** - Right level of granularity
- [ ] **Error messages actionable** - Clear what went wrong and how to fix
- [ ] **Logging present** - For debugging and troubleshooting
- [ ] **No sensitive data in logs** - PII, passwords, keys excluded
- [ ] **Graceful degradation** - Partial failures don't crash entire system

### 1.9 Documentation

- [ ] **Code documented** - Public APIs, complex logic explained
- [ ] **README updated** - If behavior/setup changes
- [ ] **API docs updated** - If endpoints change
- [ ] **Inline comments where needed** - For non-obvious decisions

### 1.10 Cross-Platform Compatibility

- [ ] **No hardcoded platform paths**:
  - `/mnt/c/Users/...` (WSL)
  - `/c/Users/...` (Git Bash)
  - `C:\Users\...` (Windows)
  - `/home/username/...` (Linux)
  - `/Users/username/...` (macOS)
- [ ] **Portable tool detection** - `command -v tool` not path hunting
- [ ] **Platform fallbacks** - Graceful handling when features unavailable
- [ ] **Scripts self-locate** - Use `Path(__file__).resolve()`, `$PSScriptRoot`, `${BASH_SOURCE[0]}`

### 1.11 Anti-Duplication

- [ ] **No duplicate content** - Same info in ONE place only
- [ ] **No identical files** - `diff` similar files to verify
- [ ] **Single source of truth** - Link instead of copy-paste
- [ ] **Config files distinct** - Each serves different purpose

### 1.12 Style and Consistency

- [ ] **Follows style guide** - Language/project conventions
- [ ] **Consistent with codebase** - Matches existing patterns
- [ ] **No style changes mixed with logic** - Separate formatting PRs

### 1.13 Accessibility (WCAG 2.1 AA)

- [ ] **Alt text present** - All images have descriptive alt text; decorative images use `alt=""`
- [ ] **Color contrast sufficient** - 4.5:1 for text, 3:1 for UI components
- [ ] **Keyboard navigable** - All interactive elements via Tab/Enter/Space; no keyboard traps
- [ ] **Focus visible** - Clear focus indicators on all interactive elements
- [ ] **Semantic HTML** - Proper heading hierarchy; buttons not divs; links not spans
- [ ] **ARIA correct** - Used only when semantic HTML insufficient; no conflicting roles

### 1.14 Internationalization (i18n)

- [ ] **No hardcoded strings** - All user-facing text externalized to resource files
- [ ] **Locale-aware formatting** - Dates, numbers, currency use locale APIs
- [ ] **RTL consideration** - Logical CSS properties where applicable
- [ ] **No string concatenation** - Use parameterized messages, not `"Hello " + name`
- [ ] **Pluralization handled** - Proper plural rules, not `count + " items"`

### 1.15 Observability

- [ ] **Structured logging** - JSON format with trace IDs, timestamps, context
- [ ] **Metrics present** - Latency, error rates, throughput for critical paths
- [ ] **Trace context propagated** - Distributed tracing across service boundaries
- [ ] **Health checks implemented** - Liveness/readiness probes with dependency checks
- [ ] **SLOs defined** - Measurable service level objectives for key operations

### 1.16 Data Privacy (GDPR/CCPA)

- [ ] **PII identified and protected** - Personal data encrypted, access controlled
- [ ] **Data retention enforced** - Clear policies, automated cleanup
- [ ] **Right to deletion** - Complete erasure across all systems possible
- [ ] **Consent tracked** - Explicit opt-in with audit trail
- [ ] **No PII in logs** - Redaction or hashing of personal identifiers

### 1.17 API Design

- [ ] **Versioning strategy** - Clear version in URL, header, or media type
- [ ] **Backward compatible** - New fields nullable, no removed fields
- [ ] **Deprecation documented** - Sunset dates, migration paths
- [ ] **Consistent naming** - Follows REST/GraphQL conventions
- [ ] **Error responses standardized** - Consistent error format across endpoints

### 1.18 Dependency Management

- [ ] **No known vulnerabilities** - CVE scanning in CI/CD
- [ ] **License compliance** - No GPL conflicts with proprietary code
- [ ] **Version pinned** - Lockfiles present and up-to-date
- [ ] **Transitive deps reviewed** - Indirect dependencies also secure
- [ ] **SBOM available** - Software Bill of Materials for audits

### 1.19 Database Patterns

- [ ] **N+1 queries avoided** - Eager loading or batch queries used
- [ ] **Indexes present** - For foreign keys, join columns, query patterns
- [ ] **Migrations backward compatible** - Incremental changes, no data loss
- [ ] **Schema properly normalized** - Or denormalized with clear rationale
- [ ] **Query optimization** - Explain plans reviewed for complex queries

### 1.20 Configuration Management

- [ ] **Secrets in vault** - Never hardcoded, use env vars or secrets manager
- [ ] **Feature flags used** - For gradual rollouts, A/B testing
- [ ] **12-factor compliant** - Config via environment, not files
- [ ] **Validation at startup** - Fail fast on missing/invalid config
- [ ] **Environment parity** - Same config structure across dev/staging/prod

### 1.21 Cloud/Infrastructure (12-Factor)

- [ ] **Stateless processes** - No local session storage, use external stores
- [ ] **Port binding** - Self-contained, exports HTTP via port
- [ ] **Disposability** - Fast startup, graceful SIGTERM shutdown
- [ ] **Dev/prod parity** - Minimal gap between environments
- [ ] **Container best practices** - Multi-stage builds, non-root user, resource limits
- [ ] **IaC used** - Terraform/CloudFormation for reproducibility

### 1.22 Frontend Patterns

- [ ] **Component design** - Small, reusable, composition over inheritance
- [ ] **State management** - Appropriate tool (local, context, Zustand, Redux)
- [ ] **Bundle size** - Code splitting, lazy loading, < 500KB main bundle
- [ ] **Memoization** - Strategic use of memo/useMemo/useCallback
- [ ] **Web Vitals** - LCP < 2.5s, FID < 100ms, CLS < 0.1

### 1.23 Mobile Patterns

- [ ] **Battery efficient** - WorkManager/JobScheduler, batched operations
- [ ] **Offline-first** - Local caching with sync, offline queue
- [ ] **Responsive layout** - Flexible dimensions (dp/sp), rotation handling
- [ ] **Memory efficient** - Image downsampling, lifecycle awareness
- [ ] **Network efficient** - Request batching, compression, exponential backoff

### 1.24 AI/ML Code Patterns

- [ ] **Model versioning** - MLflow/DVC for models and data
- [ ] **Reproducibility** - Random seeds, pinned dependencies, exact environments
- [ ] **Bias detection** - Fairness metrics across demographics
- [ ] **Data pipeline validated** - Schema validation, statistical tests
- [ ] **Model monitoring** - Drift detection for data and performance

### 1.25 Clean Code: Names (Robert C. Martin)

- [ ] **Intention-revealing names** - Name tells you why it exists, what it does, how it's used
- [ ] **No misleading names** - `accountList` should actually be a list; avoid false clues
- [ ] **Meaningful distinctions** - Not `data1`, `data2`, `dataInfo`, `theData`
- [ ] **Pronounceable names** - Can discuss code verbally without spelling variables
- [ ] **Searchable names** - Single-letter names only for small local scope
- [ ] **No encodings** - No Hungarian notation, no type prefixes (strName, intCount)
- [ ] **No mental mapping** - Reader shouldn't translate names to concepts they know
- [ ] **Class names are nouns** - Customer, Account, Parser (not verbs)
- [ ] **Method names are verbs** - postPayment, deletePage, save (not nouns)

### 1.26 Clean Code: Functions (Robert C. Martin)

- [ ] **Small** - 5-20 lines ideal; rarely exceed 30 lines
- [ ] **Do one thing** - Single level of abstraction; one reason to change
- [ ] **One abstraction level** - Don't mix getHtml() with .append("\n")
- [ ] **Descriptive names** - Long descriptive name better than short enigmatic one
- [ ] **Few arguments** - Zero ideal, one/two good, three questionable, never more than four
- [ ] **No flag arguments** - Split function into two instead of passing boolean
- [ ] **No side effects** - Don't modify unexpected state; function does what name says only
- [ ] **Command/Query separation** - Either do something OR answer something, never both
- [ ] **Prefer exceptions to error codes** - Don't return -1 or null for errors
- [ ] **Extract try/catch blocks** - Bodies of try/catch should be one-line function calls

### 1.27 Clean Code: Comments (Robert C. Martin)

- [ ] **Code explains itself first** - If you need a comment, try rewriting the code
- [ ] **Comments explain WHY** - Not what (code shows what) or how (code shows how)
- [ ] **Legal comments acceptable** - Copyright, license headers
- [ ] **Informative comments acceptable** - Regex explanation, return value meaning
- [ ] **TODO comments have tickets** - `// TODO: JIRA-123 - refactor after API v2`
- [ ] **No redundant comments** - `// Constructor` above a constructor is noise
- [ ] **No commented-out code** - Delete it; version control remembers
- [ ] **No closing brace comments** - `} // end if` means function is too long
- [ ] **No attribution comments** - `// Added by Bob` - use version control blame
- [ ] **No journal comments** - Change logs belong in VCS, not code

### 1.28 Clean Code: Conditionals (Pragmatic Programmer)

- [ ] **Positive conditions** - `if (isValid)` not `if (!isInvalid)`
- [ ] **No double negatives** - `if (!notFound)` should be `if (found)`
- [ ] **Guard clauses** - Early return for edge cases; avoid deep nesting
- [ ] **Explanatory variables** - Extract complex conditions to named booleans
- [ ] **Encapsulate conditionals** - `if (shouldBeDeleted(timer))` not `if (timer.hasExpired() && !timer.isRecurrent())`
- [ ] **Avoid negative conditionals** - `if (buffer.shouldCompact())` not `if (!buffer.shouldNotCompact())`
- [ ] **Polymorphism over switch** - Type-based switches often indicate missing polymorphism
- [ ] **No null checks everywhere** - Use Null Object pattern or Optional types

### 1.29 Code Smells Quick Reference

| Smell | Detection | Impact | Fix |
| ----- | --------- | ------ | --- |
| **Long Method** | > 30 lines | Maintainability | Extract methods |
| **Long Parameter List** | > 4 parameters | Usability | Introduce parameter object |
| **Deep Nesting** | > 3-4 indent levels | Readability | Guard clauses, extract method |
| **Magic Numbers** | Hardcoded values | Maintainability | Named constants |
| **God Class** | Class does too much | Testability, coupling | Extract classes by responsibility |
| **Feature Envy** | Method uses other class's data | Coupling | Move method to data class |
| **Duplicate Code** | Same logic repeated | DRY violation | Extract to shared function |
| **Dead Code** | Unused code | Clutter, confusion | Delete it |
| **Primitive Obsession** | Overuse of primitives | Type safety | Value objects |
| **Shotgun Surgery** | One change touches many files | Fragility | Consolidate related code |
| **Divergent Change** | One class changed for many reasons | SRP violation | Split by reason for change |
| **Data Clumps** | Same data appears together | Missing abstraction | Create class for data group |
| **Comments** | Explaining bad code | Readability | Rewrite the code |
| **Speculative Generality** | Code for "future needs" | Complexity | Delete unused abstractions |

## Layer 2: Repo-Specific Checks

**Only if CLAUDE.md or repo standards exist.**

### 2.1 Pattern Compliance

- [ ] **Follows existing patterns** - Similar to other files in repo
- [ ] **Naming conventions match** - Consistent with established names
- [ ] **File structure correct** - In right location with right layout

### 2.2 CLAUDE.md Anti-Patterns (if applicable)

- [ ] **No mixed OS content** - Each file for one platform
- [ ] **No README.md in topic folders** - Only at root
- [ ] **No numbered filenames** - `git-setup.md` not `01-git-setup.md`
- [ ] **Title-filename consistency** - Filename matches `# Header`

## Layer 3: Repository Rules (CLAUDE.md Compliance)

**Only for repositories with CLAUDE.md in root.** Load Tier 4 references based on file types being reviewed.

### 3.1 Detection and Activation

1. Check for `CLAUDE.md` in repo root
2. Check for `.claude/memory/` directory
3. If both exist, apply Layer 3 checks
4. Load [tier-4/claude-md-core.md](references/tier-4/claude-md-core.md) for every review

### 3.2 Quick Reference Checklist

- [ ] **No absolute paths** - Use root-relative or placeholders (`<repo-root>`, `<skill-name>`)
- [ ] **Title-filename match** - `git-setup-windows.md` -> `# Git Setup Windows`
- [ ] **No platform mixing** - Each file serves one platform only
- [ ] **No README in topic folders** - Only at root and hub levels
- [ ] **No numbered files** - `git-setup.md` not `01-git-setup.md`
- [ ] **Temp files in .claude/temp/** - Nowhere else, correct naming convention
- [ ] **Single source of truth** - Link, don't duplicate content
- [ ] **UTF-8 encoding** - ASCII punctuation only (no smart quotes)
- [ ] **Official sources** - Documentation backed by official docs with Last Verified dates

### 3.3 Documentation Files (*.md)

Load [tier-4/documentation-rules.md](references/tier-4/documentation-rules.md) for:

- [ ] **Official documentation links** - Required for all setup guides
- [ ] **Version information** - Current and minimum versions documented
- [ ] **Installation steps** - In dependency order
- [ ] **Verification steps** - With expected output
- [ ] **Last Verified date** - Present and recent

### 3.4 Platform-Specific Files (*-{platform}.md)

Load [tier-4/platform-rules.md](references/tier-4/platform-rules.md) for:

- [ ] **Platform separation** - No mixed OS content
- [ ] **Correct suffix** - `-windows`, `-macos`, `-linux`, `-wsl`
- [ ] **WSL redirect pattern** - Redirects to Linux where appropriate
- [ ] **Hub completeness** - All platform hubs updated together

### 3.5 Anti-Duplication

Load [tier-4/anti-duplication-rules.md](references/tier-4/anti-duplication-rules.md) when duplication indicators detected:

- [ ] **No duplicate content** - Each piece of info in ONE place
- [ ] **Version in Last Verified only** - All other files link to it
- [ ] **Hub links to spokes** - No content duplication between hub and references
- [ ] **One report per task** - Consolidate multiple reports

### 3.6 Path Conventions

Load [tier-4/path-rules.md](references/tier-4/path-rules.md) when path patterns detected:

- [ ] **No absolute paths** - Platform-specific absolute paths are forbidden
- [ ] **Root-relative paths** - From repo root, not current directory
- [ ] **Generic placeholders** - `<repo-root>`, `<skill-name>` over explicit paths
- [ ] **Script self-location** - `Path(__file__).resolve()`, `$PSScriptRoot`

### 3.7 Skill Files (.claude/skills/**)

Load [tier-4/skill-rules.md](references/tier-4/skill-rules.md) for:

- [ ] **SKILL.md structure** - Required sections present
- [ ] **YAML frontmatter** - name, description, allowed-tools
- [ ] **Progressive disclosure** - Tiered reference loading
- [ ] **Skill encapsulation** - No internal paths exposed externally

### 3.8 Memory Files (.claude/memory/**)

Load [tier-4/memory-rules.md](references/tier-4/memory-rules.md) for:

- [ ] **Import syntax** - `@.claude/memory/file.md`
- [ ] **Token budget documented** - Approximate token count noted
- [ ] **Context guidance** - When to load (always vs context-dependent)
- [ ] **Last Updated date** - Present and accurate

### 3.9 Temp Files (.claude/temp/**)

Load [tier-4/temp-file-rules.md](references/tier-4/temp-file-rules.md) for:

- [ ] **Correct location** - Only `.claude/temp/` allowed
- [ ] **Naming convention** - `YYYY-MM-DD_HHmmss-{agent-type}-{topic}.md`
- [ ] **Flat structure** - No subdirectories
- [ ] **UTC timestamps** - ISO 8601 format

## Severity Classification

### Critical (Must Fix)

- Security vulnerabilities (injection, auth bypass, secrets exposure)
- Data loss or corruption potential
- Race conditions in production code
- Broken functionality
- Hardcoded secrets or credentials

### Warning (Should Fix)

- Performance issues
- Missing error handling
- Inadequate test coverage
- Code duplication
- Hardcoded platform paths
- Poor naming

### Suggestion (Consider)

- Style improvements (prefix with "Nit:")
- Alternative approaches
- Documentation enhancements
- Refactoring opportunities

## Report Format

```markdown
## Code Review Findings

### Critical Issues (Must Fix)
1. **[Issue Title]**
   - **Location**: file:line
   - **Problem**: What's wrong and why it matters
   - **Fix**: Specific code change
   - **Confidence**: High/Medium

### Warnings (Should Fix)
1. **[Issue Title]**
   - **Location**: file:line
   - **Problem**: What's wrong
   - **Fix**: Specific change

### Suggestions (Nit)
1. [Suggestion with rationale]
```

## Anti-Patterns (What NOT to Do)

- **"Looks good overall"** - Never without systematic checklist review
- **Benefit of the doubt** - If questionable, it IS a finding
- **Summarizing** - Critically analyze against checklist
- **Missing security issues** - Always check OWASP basics
- **Ignoring concurrency** - Think through race conditions
- **Skipping similar files** - Always diff files with similar purposes
- **Vague fixes** - "Fix this" vs "Replace lines X-Y with..."

## Behavioral Rules

1. **Be skeptical, not charitable** - Assume problems until verified clean
2. **Every line matters** - Review ALL code assigned, understand it
3. **Think like an attacker** - What could go wrong? How could this be exploited?
4. **Think like a user** - Both end-user and developer-user
5. **Context matters** - View changes in context of whole file/system
6. **Report everything** - Every issue, with appropriate severity
7. **Propose specific fixes** - Concrete code, not vague suggestions
8. **Acknowledge good things** - Compliment well-done code

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
[ ] Privacy: PII protected, no PII in logs, consent tracked

CLEAN CODE (Robert C. Martin):
[ ] Names: intention-revealing, pronounceable, searchable, no encodings
[ ] Functions: small (5-20 lines), do one thing, few args (0-2), no side effects
[ ] Comments: explain WHY not WHAT, no commented-out code, no redundancy
[ ] Conditionals: positive conditions, guard clauses, no double negatives

DOMAIN-SPECIFIC (when applicable):
[ ] API: versioning, backward compat, error format
[ ] Database: N+1 avoided, indexes, migrations safe
[ ] Config: secrets in vault, feature flags, 12-factor
[ ] Frontend: component design, bundle size, web vitals
[ ] Mobile: battery/memory/network efficient, offline-first
[ ] AI/ML: model versioning, reproducibility, bias detection

CODE SMELLS (watch for):
- Long methods (> 30 lines)
- Long parameter lists (> 4 params)
- Deep nesting (> 3-4 levels)
- God classes (too many responsibilities)
- Feature envy (method uses other class's data)
- Primitive obsession (should use value objects)
- Shotgun surgery (one change touches many files)

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
```

## References

- [Detailed Checklist](references/checklist.md) - Extended checklist with detection patterns
- [Google Engineering Practices](https://google.github.io/eng-practices/review/)
- [OWASP Secure Code Review](https://owasp.org/www-project-code-review-guide/)

## Version History

- v4.0.0 (2025-11-28): Added Layer 3 (Repository Rules) with Tier 4 CLAUDE.md-specific checks; added 8 reference files for documentation, anti-duplication, paths, platforms, skills, memory, and temp files; extended progressive loading to support repository-specific validation
- v3.0.0 (2025-11-28): Added Clean Code principles (sections 1.25-1.29): Names, Functions, Comments, Conditionals, Code Smells from Robert C. Martin and Pragmatic Programmer; updated Quick Reference Card with Clean Code and Code Smells sections
- v2.1.0 (2025-11-28): Added 12 modern cross-cutting sections (1.13-1.24): Accessibility, i18n, Observability, Data Privacy, API Design, Dependency Management, Database Patterns, Configuration Management, Cloud/Infrastructure, Frontend Patterns, Mobile Patterns, AI/ML Code Patterns
- v2.0.0 (2025-11-27): Major expansion with SOLID, OWASP, concurrency, Google practices
- v1.0.0 (2025-11-27): Initial release

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
