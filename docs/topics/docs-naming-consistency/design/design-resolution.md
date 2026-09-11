# Design resolution: docs-naming-consistency

outcome: early-exit
tier: C (rename plus config/doc; no new types, contracts, modules, or package topology)

Reason: the change renames 13 markdown files, updates references to them, adds one deterministic
check script with a test, one path-scoped rule file, one ADR, and two pointer stubs. No type,
contract, or module boundary is introduced. The only new interface is the check script's CLI,
which follows the shape every other `scripts/check-*.sh` in the repository already uses
(`--check` style flags, exit 0 on pass, non-zero with a per-finding line on failure).

Type sketch: none required. The check script's inputs are `git ls-files docs/`, an exemption
list, and the two tombstone allowlist entries; its output is a list of offending paths and an
exit status.
