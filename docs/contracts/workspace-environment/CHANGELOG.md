# Changelog for the workspace-environment convention

## 1.0.1 - 2026-11-11

The vendor-fact pointers no longer carry an as-of date or recheck trigger, per the upstream-drift
convention 5.0.0, and each links its section by anchor.

## 1.0.0 - 2026-10-04

Initial contract: the "Workspace environment" entry in `docs/conventions/workspace-environment.md`,
the `setup`, `up`, `info` and `down` verbs with `WORKSPACE_ID` and `WORKSPACE_ROOT`, the
default-branch read, the untrusted-input rule, the cloud SessionStart wiring, and the reader table.
