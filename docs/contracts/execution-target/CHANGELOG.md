# Changelog for the execution-target convention

## 2.0.0 - 2026-10-21

Removed the `<!-- execution-target:fallback v1 -->` item marker comment and the "Item fallback"
bullet that read it: no per-item dispatcher exists to read it. A failed stage-start probe now only
writes `execution_target_fallback` to the lane's telemetry state block, claims nothing and exits.

## 1.0.0 - 2026-10-04

Initial contract: the `docs/conventions/execution-target.yaml` policy floor and its schema, the five
host values, key resolution, the fetch-then-read rule, the cloud launch rule, the stage-start probe
and fallback, the untrusted-input stages, and the required-plugin table.
