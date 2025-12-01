---
description: List all available Gemini CLI skills with their descriptions
model: haiku
allowed-tools:
---

# List Skills

List all available skills from the google-ecosystem plugin.

## Skills Inventory

Format each skill with its purpose and key use cases.

### Documentation Skills

---

### **gemini-cli-docs**

Core documentation skill. Single source of truth for Gemini CLI official documentation. Use for searching, resolving doc_ids, and finding guidance on any Gemini CLI topic.

---

### **gemini-cli-execution**

Expert guide for executing Gemini CLI in headless and automation modes. Covers command syntax (positional prompts), piping input, JSON output handling, and context management.

---

### Integration Skills

---

### **gemini-delegation-patterns**

Strategic patterns for Claude-to-Gemini delegation. Covers decision criteria for when to delegate, execution patterns, and result handling. Use when determining if a task should go to Gemini.

---

### **gemini-json-parsing**

Parse Gemini CLI headless output (JSON and stream-JSON). Covers response extraction, stats interpretation, error handling. Use when processing Gemini programmatic output.

---

### **gemini-token-optimization**

Optimize token usage when delegating to Gemini. Covers caching, batch queries, model selection (Flash vs Pro), and cost tracking. Use for bulk operations.

---

### **gemini-exploration-patterns**

Strategic patterns for codebase exploration using Gemini's large context window. Covers token thresholds, model routing, exploration strategies, and output format standards.

---

### **gemini-context-bridge**

Facilitates context sharing between Claude Code and Gemini CLI. Covers CLAUDE.md to GEMINI.md synchronization and delegation strategies.

---

### Management Skills

---

### **gemini-config-management**

Expert guide for configuring Gemini CLI. Covers settings.json, environment variables, configuration scopes, and policy engine.

---

### **gemini-checkpoint-management**

Manage Gemini CLI checkpointing. Covers git-based snapshots, /restore command, and rollback workflows. Use for experimental changes.

---

### **gemini-sandbox-configuration**

Configure Gemini CLI sandboxing. Covers Docker, Podman, macOS Seatbelt, profiles, and security boundaries. Use for isolated execution.

---

### **gemini-session-management**

Manage Gemini CLI sessions. Covers resume, retention policies, session browser, and cleanup. Use for session continuity.

---

### **gemini-memory-sync**

Synchronization patterns for CLAUDE.md and GEMINI.md memory files. Covers import syntax, drift detection, one-way sync, and consistent context maintenance.

---

### **gemini-workspace-bridge**

Central authority for Claude-Gemini shared workspace architecture. Defines directory structure, artifact exchange patterns, and file naming conventions.

---

### Development Skills

---

### **gemini-extension-development**

Expert guide for building Gemini CLI extensions. Covers extension.yaml manifest, GEMINI.md context files, and MCP server bundling.

---

### **gemini-mcp-integration**

Expert guide for MCP (Model Context Protocol) integration with Gemini CLI. Covers server configuration, transports, and tool management.

---

### **gemini-command-development**

Expert guide for creating custom Gemini CLI commands. Covers TOML command files, arguments, and shell injection patterns.

---

### **toml-command-builder**

Guide for building Gemini CLI TOML custom commands. Covers syntax, templates, argument handling, shell injection, file injection, and validation patterns.

---

### **policy-engine-builder**

Guide for creating Gemini CLI policy engine TOML rules. Covers rule syntax, priority tiers, conditions, MCP wildcards, and enterprise patterns.

---

## Total: 18 Skills

| Category      | Count |
| ------------- | ----- |
| Documentation | 2     |
| Integration   | 5     |
| Management    | 5     |
| Development   | 6     |
