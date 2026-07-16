# Topic-docs concern file — what `/toolchain:setup` offers

This plugin's skills (`/toolchain:build`, `/toolchain:lint`, `/toolchain:setup`) write no lifecycle
documents of their own. `/toolchain:setup` reads this binding to offer the consuming repo the tracked
`.claude/topic-docs.yaml` concern file — the shared, consumer-side source of truth that companion
lifecycle plugins resolve for artifact placement.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, and the prune-with-pointer lifecycle. `/toolchain:setup` offers the concern
file independent of whether any lifecycle plugin is installed today.

## The concern file `/toolchain:setup` writes

`.claude/topic-docs.yaml` — schema keys `contract_dir`, `memory_dir`, `contract_tier`, `vault_backend`.
Recommended `contract_tier: branch` (the default; `local` for solo/offline work). Setup materializes
only the keys that differ from the documented defaults (always at least one explicit key — a comment-only
YAML document parses as null and fails the contract schema's `type: object`), runs the `git check-ignore`
conflict check on the chosen contract root when the tier is `branch`, and never edits the consumer's root
`.gitignore`.

## Where the artifacts land (owned by the companion plugins)

The `implementation` and `verification` plugins bind this convention in their own
`reference/topic-docs.md`, which own the per-artifact tier placement they write (plan progress marks,
deviation logs, verification manifests, baselines). This plugin defers to those bindings and the contract.
