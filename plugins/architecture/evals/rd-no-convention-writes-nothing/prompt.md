---
description: "Recording a decision in a repository with no ADR convention lists what was searched, offers common shapes with a numbering scheme, points at the upstream template catalog, and writes nothing: no directory, no file"
tags: [architecture, record-decision, outcome, scaffold]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply says no ADR convention was found, offers at least one shape naming a numbering scheme (for example 0001-<title>.md), cites the joelparkerhenderson/architecture-decision-record catalog, and stops for the human's choice. No Write or Edit call is made and no shell command creates a directory or file."
---

/architecture:record-decision Store orders in PostgreSQL rather than MongoDB. Context: orders need multi-row transactions across order lines and payments, and the reporting team queries them with SQL. We load-tested MongoDB and rejected it because cross-document transactions added latency. Consequences: schema migrations ship with every release, and moving off PostgreSQL later means rewriting the persistence layer and every reporting query.
