# Database Tools macOS

For cross-platform database tool information (DBeaver features and comparisons), see [Database Tools](database-tools.md).

This guide covers **macOS-specific** installation and configuration.

**Last Verified:** 2025-11-11

---

## Overview

SQL Server Management Studio (SSMS) is **Windows-only** and not available for macOS. This guide covers cross-platform alternatives for macOS users.

---

## DBeaver (Community Edition)

Free, open-source universal database tool supporting SQL Server, MySQL, PostgreSQL, Oracle, and more.

**Website:** [https://dbeaver.io/](https://dbeaver.io/)

### DBeaver Features

- Support for 80+ databases
- ER diagrams
- Data export/import
- SQL editor with auto-completion
- Visual query builder
- Database metadata exploration

### DBeaver Installation

#### Via Homebrew

```bash
brew install --cask dbeaver-community
```

#### Manual Download

Download the macOS installer from [dbeaver.io/download](https://dbeaver.io/download/).

---

## TablePlus

Modern, native database management tool with excellent macOS integration.

**Website:** [https://tableplus.com/](https://tableplus.com/)

### TablePlus Features

- Native macOS app (fast and responsive)
- Support for MySQL, PostgreSQL, SQL Server, SQLite, and more
- Multiple tabs and windows
- Intuitive GUI for database operations
- SSH tunneling support
- Code review and safety features

### TablePlus Installation

#### Using Homebrew

```bash
brew install --cask tableplus
```

**Note:** TablePlus has a free tier with limitations. Full features require a license.

---

## Postico (PostgreSQL-specific)

Modern PostgreSQL client for macOS.

**Website:** [https://eggerapps.at/postico/](https://eggerapps.at/postico/)

### Postico Features

- Native macOS PostgreSQL client
- Simple, elegant interface
- Fast and lightweight
- Table structure editing
- Query editor with syntax highlighting

### Postico Installation

Download from the official website. Available in both free and paid versions.

---

## Sequel Ace (MySQL-specific)

Free, open-source MySQL client for macOS (successor to Sequel Pro).

**Website:** [https://sequel-ace.com/](https://sequel-ace.com/)

### Sequel Ace Installation

#### Install via Homebrew

```bash
brew install --cask sequel-ace
```

---

## Comparison: Database Tools for macOS

Since SSMS is not available on macOS, developers working with databases on macOS should use alternative tools:

- **DBeaver** - Best for universal database support (SQL Server, MySQL, PostgreSQL, Oracle, etc.)
- **TablePlus** - Best for native macOS experience with multi-database support
- **Postico** - Best for PostgreSQL-specific administration
- **Sequel Ace** - Best for MySQL-specific administration
