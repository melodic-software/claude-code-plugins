# Conventional Commits Specification

Complete reference for the Conventional Commits format specification (v1.0.0).

## Official Specification

**Source**: [https://www.conventionalcommits.org/en/v1.0.0/](https://www.conventionalcommits.org/en/v1.0.0/)

## Table of Contents

- [Official Specification](#official-specification)
- [Specification Overview](#specification-overview)
- [Commit Message Structure](#commit-message-structure)
- [Mandatory Components](#mandatory-components)
  - [Type (Required)](#type-required)
  - [Description (Required)](#description-required)
- [Optional Components](#optional-components)
  - [Scope (Optional)](#scope-optional)
  - [Body (Optional)](#body-optional)
  - [Footer (Optional)](#footer-optional)
- [Breaking Changes](#breaking-changes)
- [Specification Rules](#specification-rules)
- [Examples from Specification](#examples-from-specification)
- [Benefits of Conventional Commits](#benefits-of-conventional-commits)
- [Integration with Claude Code](#integration-with-claude-code)
- [Validation](#validation)
- [FAQs from Specification](#faqs-from-specification)

## Specification Overview

The Conventional Commits specification is a lightweight convention on top of commit messages providing an easy set of rules for creating an explicit commit history that makes it easier to write automated tools and enables automatic semantic versioning.

## Commit Message Structure

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Mandatory Components

### Type (Required)

The type communicates the intent of the change.

**Specification-defined types**:

- **feat**: Introduces a new feature to the codebase (correlates with MINOR in Semantic Versioning)
- **fix**: Patches a bug in the codebase (correlates with PATCH in Semantic Versioning)

**Additional recommended types** (not in spec, but commonly used):

- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **perf**: A code change that improves performance
- **test**: Adding missing tests or correcting existing tests
- **build**: Changes that affect the build system or external dependencies
- **ci**: Changes to CI configuration files and scripts
- **chore**: Other changes that don't modify src or test files

### Description (Required)

The description is a short summary of the code changes:

- Use imperative, present tense: "change" not "changed" nor "changes"
- Don't capitalize the first letter
- No period (.) at the end
- Keep it concise (target ~50 characters, max 72)

**Examples**:

- ✅ `add user authentication endpoint`
- ✅ `fix memory leak in data processor`
- ❌ `Added user authentication.` (wrong tense, capitalized, period)
- ❌ `fixes bug` (too vague)

## Optional Components

### Scope (Optional)

A scope provides additional contextual information about what section of the codebase is affected:

- Enclosed in parentheses: `feat(parser):`
- Follows the type immediately
- Describes a section of the codebase
- Should be a noun

**Examples**:

- `feat(api): add token refresh endpoint`
- `fix(database): resolve connection timeout`
- `docs(readme): update installation steps`

### Body (Optional)

The body provides additional details about the change:

- Must be preceded by a blank line after the description
- Free-form text with multiple paragraphs allowed
- Should explain the motivation for the change
- Contrast this with previous behavior

**Example**:

```text
feat(auth): add JWT token refresh mechanism

Implements automatic token refresh to improve user experience
and reduce unnecessary re-authentication. The refresh token
is stored securely and automatically used when the access
token expires.
```

### Footer (Optional)

Footers provide additional metadata about the commit:

- Must be preceded by a blank line after the body (or description if no body)
- Follow git trailer format
- Use token followed by either `:<space>` or `<space>#` separator
- Can include multiple footers

**Examples**:

```text
Reviewed-by: John Doe
Refs: #123
```

## Breaking Changes

Breaking changes MUST be indicated in two possible ways:

### Method 1: Exclamation Mark

Add `!` immediately before the `:` in the type/scope:

```text
feat!: send email when product is shipped
feat(api)!: change response format to JSON:API spec
```

### Method 2: Footer Notation

Use `BREAKING CHANGE:` footer (can be uppercase or mixed case, but uppercase is conventional):

```text
feat(api): add new authentication endpoint

BREAKING CHANGE: The /auth endpoint now requires an API key in the
Authorization header. Previous token-based auth is deprecated.
```

### Combining Both Methods

Both methods can be used together for maximum visibility:

```text
feat(api)!: redesign authentication system

BREAKING CHANGE: Complete redesign of authentication flow.
All clients must migrate to OAuth 2.0. Legacy API keys are
no longer supported.
```

**Impact on Semantic Versioning**:

- Breaking changes trigger a MAJOR version bump (1.0.0 → 2.0.0)
- Regardless of type (`feat!` or `fix!` both trigger MAJOR)

## Specification Rules

These rules come directly from the Conventional Commits specification:

1. Commits MUST be prefixed with a type (noun: feat, fix, etc.)
2. Type feat MUST be used when a commit adds a new feature
3. Type fix MUST be used when a commit patches a bug
4. An optional scope MAY be provided after a type (enclosed in parentheses)
5. A description MUST immediately follow the colon and space after the type/scope
6. A longer body MAY be provided after the short description (preceded by blank line)
7. One or more footers MAY be provided (preceded by blank line)
8. Breaking changes MUST be indicated by `!` before `:` OR `BREAKING CHANGE:` footer OR both
9. Types other than feat and fix MAY be used
10. Case sensitivity is flexible except for "BREAKING CHANGE" which MUST be uppercase

## Examples from Specification

### Simple commit with description

```text
docs: correct spelling of CHANGELOG
```

### Commit with scope

```text
feat(lang): add Polish language
```

### Commit with breaking change indicator

```text
feat!: send an email to the customer when a product is shipped
```

### Commit with scope and breaking change

```text
feat(api)!: send an email to the customer when a product is shipped
```

### Commit with body and footer

```text
fix: prevent racing of requests

Introduce a request id and a reference to latest request. Dismiss
incoming responses other than from latest request.

Remove timeouts which were used to mitigate the racing issue but are
obsolete now.

Reviewed-by: Z
Refs: #123
```

### Commit with breaking change footer

```text
feat: allow provided config object to extend other configs

BREAKING CHANGE: `extends` key in config file is now used for extending other config files
```

### Commit with multiple footers

```text
fix: prevent racing of requests

Introduce a request id and a reference to latest request. Dismiss
incoming responses other than from latest request.

Reviewed-by: John Doe <john@example.com>
Refs: #123
See-also: #456, #789
```

## Benefits of Conventional Commits

**Automatic tooling**:

- Automatic semantic versioning (MAJOR.MINOR.PATCH)
- Automatic CHANGELOG generation
- Triggering build and publish processes
- Easier navigation of commit history

**Communication**:

- Clear intent communicated to consumers
- Structured format aids readability
- Filtering commits by type (all features, all fixes)

**Onboarding**:

- New contributors understand commit conventions quickly
- Consistent history across team members

## Integration with Claude Code

When using Conventional Commits in Claude Code contexts, add the attribution footer:

```text
<type>[scope]: <description>

[optional body]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

This preserves Conventional Commits structure while adding required attribution.

## Validation

A commit message following Conventional Commits can be validated with this regex pattern:

```regex
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .{1,50}
```

**Components**:

- `^(feat|fix|...)` - Type must be one of recognized types
- `(\(.+\))?` - Optional scope in parentheses
- `!?` - Optional breaking change indicator
- `":"` - Required colon and space
- `.{1,50}` - Description between 1-50 characters

## FAQs from Specification

**Q: How do I handle commit types in the initial development phase?**

A: Proceed as if you've already released the product. Somebody is using it (your colleagues, yourself in 6 months).

**Q: What do I do if the commit conforms to more than one type?**

A: Go back and make multiple commits whenever possible. Benefits of Conventional Commits include enabling more organized commits.

**Q: Doesn't this discourage rapid development?**

A: It encourages moving fast in an organized way. It helps you move faster long term across multiple projects with varied contributors.

**Q: Does Conventional Commits lead to fewer commits because developers will think about the type?**

A: Conventional Commits encourages making more commits of organized types (especially fixes). Automatic tooling benefits from this.

**Q: How does this relate to SemVer?**

A: `fix` = PATCH, `feat` = MINOR, `BREAKING CHANGE` = MAJOR (regardless of type).

---

**Last Verified:** 2025-11-25
**Specification Version:** v1.0.0
**Source:** [conventionalcommits.org](https://www.conventionalcommits.org/en/v1.0.0/)
