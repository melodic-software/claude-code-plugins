---
description: List all google-ecosystem slash commands with their descriptions
model: haiku
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

Execute a shell command in Gemini CLI sandbox for isolation. Safe for untrusted operations.

Example: `/google-ecosystem:gemini-sandbox npm install unknown-package`

---

### Discovery Commands

---

### **/google-ecosystem:list-skills**

List all available Gemini CLI skills with their descriptions.

---

### **/google-ecosystem:list-commands**

List all google-ecosystem slash commands (this command).

---

## Total: 9 Commands

| Category | Count |
|----------|-------|
| Documentation | 3 |
| Integration | 4 |
| Discovery | 2 |
