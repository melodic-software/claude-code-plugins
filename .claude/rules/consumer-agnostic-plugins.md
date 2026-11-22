---
description: "Shipped plugin behavior stays consumer-agnostic: a value or preference of one user, machine, organization, repository or folder lives in that consumer's own config layers, and one consumer's setting never removes an option other consumers can turn on; read before changing what a plugin ships"
paths:
  - "plugins/**"
---

# Plugins stay consumer-agnostic

Before changing what a plugin ships, read
[Hardcoded consumer specifics](../../docs/plugin-philosophy.md#hardcoded-consumer-specifics), the
doctrine owner for this rule.

A change driven by one consumer's setup (a user's deny rule, a machine path, an organization's
repository names) lands in that consumer's config layers, never in the plugin. A consumer turning a
feature off is no reason to remove it from the plugin: the plugin keeps the option and its default,
and the consumer's own settings hold their choice.
