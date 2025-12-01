---
description: List all google-ecosystem slash commands with their descriptions
model: claude-haiku-4-5-20251001
allowed-tools:
---

# List Commands

List all available slash commands from the google-ecosystem plugin.

## Commands Inventory

### Documentation Commands

---

### **/google-ecosystem:scrape-docs**

Scrape Gemini CLI documentation from geminicli.com, then refresh and validate the index.

---

### **/google-ecosystem:refresh-docs**

Refresh Gemini CLI docs index without scraping. Rebuilds index from existing files.

---

### **/google-ecosystem:validate-docs**

Validate Gemini CLI docs index integrity and detect drift without making changes.

---

### Integration Commands

---

### **/google-ecosystem:gemini-query** `<prompt>`

Send a quick headless query to Gemini CLI and display the response with stats.

Example: `/google-ecosystem:gemini-query What is async/await?`

---

### **/google-ecosystem:gemini-analyze** `<file-path> [type]`

Send a file to Gemini CLI for analysis. Types: security, performance, architecture, bugs, general.

Example: `/google-ecosystem:gemini-analyze src/auth.ts security`

---

### **/google-ecosystem:gemini-second-opinion** `[topic]`

Get Gemini's independent analysis on a topic or recent context. Provides validation and alternative perspectives.

Example: `/google-ecosystem:gemini-second-opinion Is this database schema correct?`

---

### **/google-ecosystem:gemini-sandbox** `<command>`

Execute a shell command in Gemini CLI sandbox for isolation. Safe for untrusted operations. Requires Docker, Podman, or macOS Seatbelt.

Example: `/google-ecosystem:gemini-sandbox npm install unknown-package`

---

### **/google-ecosystem:gemini-explore** `[scope] [--output <path>]`

Explore entire codebase with Gemini's large context window. Outputs a structured markdown report.

Scopes: `architecture`, `dependencies`, `patterns`, `all` (default)

Example: `/google-ecosystem:gemini-explore architecture`

---

### **/google-ecosystem:gemini-plan** `<task-description> [--context <files>]`

Generate Claude-executable implementation plans using Gemini's reasoning. Plans are formatted for Claude to execute.

Example: `/google-ecosystem:gemini-plan "Add user authentication with JWT"`

---

### **/google-ecosystem:sync-context** `[--status] [--init] [--force]`

Synchronize CLAUDE.md to GEMINI.md and check for context drift. Uses @import pattern for automatic sync.

Example: `/google-ecosystem:sync-context --init`

---

### Discovery Commands

---

### **/google-ecosystem:list-skills**

List all available Gemini CLI skills with their descriptions.

---

### **/google-ecosystem:list-commands**

List all google-ecosystem slash commands (this command).

---

## Total: 13 Commands

| Category      | Count |
| ------------- | ----- |
| Documentation | 3     |
| Integration   | 7     |
| Discovery     | 2     |
