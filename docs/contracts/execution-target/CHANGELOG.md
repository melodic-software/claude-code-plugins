# Changelog for the execution-target convention

## 2.0.1 - 2026-11-11

The vendor-fact pointers no longer carry an as-of date or recheck trigger, per the upstream-drift
convention 5.0.0; the routine-triggers record, which stores no upstream number or string, drops
its stamps too. The cloud launch pointer links the renamed "Start a cloud session from your
terminal" section, and the cloud environments pointer links its two sections by anchor.

## 2.0.0 - 2026-10-21

Removed the `<!-- execution-target:fallback v1 -->` item marker comment and the "Item fallback"
bullet that read it: no per-item dispatcher exists to read it. A failed stage-start probe now only
writes `execution_target_fallback` to the lane's telemetry state block, claims nothing and exits.

## 1.0.0 - 2026-10-04

Initial contract: the `docs/conventions/execution-target.yaml` policy floor and its schema, the five
host values, key resolution, the fetch-then-read rule, the cloud launch rule, the stage-start probe
and fallback, the untrusted-input stages, and the required-plugin table.
