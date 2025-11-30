# Design Principles

**Last Updated:** 2025-11-25

## Overview

The hooks-meta implementation follows industry best practices and architectural principles for maintainability, extensibility, and clarity.

## Core Design Principles

### 1. Vertical Slice Architecture

- **High cohesion:** Everything for one hook lives in one directory (code + config + docs + tests)
- **Low coupling:** Hooks are completely independent, no inter-hook dependencies
- **Feature-oriented:** Each hook is a complete, deployable feature
- **Easy refactoring:** Changes isolated to single directory
- **Clear ownership:** One directory = one feature

**Example structure:**

```text
.claude/hooks/prevent-backup-files/  # Complete vertical slice
├── bash/                            # Implementation
├── hook.yaml                        # Configuration
├── README.md                        # Documentation
└── tests/                           # Tests
```

### 2. Multi-Language Support (Future-Ready)

- **Language subdirectories:** bash/, python/, typescript/ for each implementation
- **Configuration-based selection:** Switch implementations via hook.yaml, no code changes
- **Best tool for the job:** Choose optimal language per hook
- **Migration support:** Run multiple implementations concurrently during transition
- **Preference-order fallback:** typescript → python → bash graceful degradation

For complete multi-language implementation guide, see [multi-language-strategy.md](multi-language-strategy.md).

### 3. DRY (Don't Repeat Yourself)

- **Shared utilities:** Common functions in `shared/` (json, path, git, config)
- **Global config:** Shared patterns in `config/global.yaml`
- **Config inheritance:** Hooks extend global patterns
- **Zero duplication:** Each concept exists in exactly one place

**Shared utilities:**

- `json-utils.sh` - JSON parsing and output
- `path-utils.sh` - Path manipulation
- `git-utils.sh` - Git command detection
- `config-utils.sh` - Config loading
- `test-helpers.sh` - Test assertions

### 4. Config Over Hardcoding

- **Externalized configuration:** All settings in YAML files
- **Hot reload:** Config changes take effect immediately
- **Human-friendly:** YAML with comments for easy editing
- **Scales well:** Separate files per hook + global config
- **Single source of truth:** Configuration drives behavior

**Configuration hierarchy:**

1. Global config (`.claude/hooks/config/global.yaml`) - Shared settings
2. Per-hook config (`.claude/hooks/<hook-name>/hook.yaml`) - Hook-specific settings
3. Immediate effect on next hook execution (no Claude Code restart needed)

### 5. Testing as First-Class Citizen

- **Co-located tests:** Tests live with the code they test
- **Test framework:** Comprehensive assertion library
- **Automatic discovery:** Test runner finds all *.test.sh files
- **Vertical slice testing:** Each hook has its own test suite
- **Fast feedback:** Run single hook tests or all tests

For complete testing guide, see [../development/testing-guide.md](../development/testing-guide.md).

### 6. Progressive Disclosure

- **Minimal initial complexity:** Start with bash (simplest)
- **Add complexity when needed:** Migrate to Python/TypeScript only if required
- **Just-in-time loading:** Config loaded on each execution
- **Lazy evaluation:** Hooks only run when matched

## Vertical Slice Architecture Benefits

**Each hook is a complete, self-contained feature:**

- **High cohesion:** All hook code, config, docs, and tests in one directory
- **Low coupling:** Hooks don't depend on each other
- **Things that change together, live together:** Hook logic + config + tests co-located
- **Easy to add/modify/remove:** Delete directory = remove hook entirely
- **Isolated refactoring:** Changes to one hook don't affect others
- **Clear ownership:** This directory = this feature

## Design Patterns Used

### 1. Strategy Pattern (Multi-Language Selection)

- Different implementations (bash, python, typescript) for same hook interface
- Configuration-based selection via `hook.yaml`
- Runtime switching without code changes

### 2. Template Method Pattern (Hook Scripts)

- All hooks follow same structure: load config → check enabled → validate → exit
- Shared utilities provide common operations
- Each hook customizes specific validation logic

### 3. Decorator Pattern (Shared Utilities)

- `json-utils.sh`, `path-utils.sh`, etc. decorate hook scripts with reusable functions
- Hooks compose behavior from utilities
- No code duplication across hooks

### 4. Registry Pattern (Hook Registration)

- Central registry in `.claude/settings.json`
- Claude Code discovers and loads hooks from registry
- Decoupled registration from implementation

## Methodologies Applied

**Clean Code Principles:**

- **Single Responsibility:** Each hook does one thing well
- **Open/Closed:** Open for extension (add new hooks), closed for modification (don't change existing)
- **DRY:** Shared utilities eliminate duplication
- **KISS:** Start simple (bash), add complexity when needed (python/typescript)
- **YAGNI:** Don't build what we don't need yet (python/typescript marked as future)

**Configuration Management:**

- **Externalized:** All settings in YAML files
- **Layered:** Global config + per-hook config
- **Hot reload:** Immediate effect (no restart for config)
- **Human-friendly:** YAML with comments

**Future-Proofing:**

- **Multi-language ready:** Structure supports bash/python/typescript
- **Migration support:** Can run multiple implementations concurrently
- **Refactoring-friendly:** Changes isolated to single directory
- **Extensible:** Easy to add new hooks following existing patterns
