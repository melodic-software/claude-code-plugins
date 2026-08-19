# Repo mode: repo-scale run machinery

Loaded only when `/code-tidying:batch-simplify repo` fires. Phases 2–8 of the main workflow are
scope-agnostic and are inherited unchanged; everything below is the machinery a whole-repository
sweep needs on top of them.

## When this file applies

Repo mode is entered two ways and no others: an explicit `repo` argument, or the user accepting the
offer the empty-scan exit makes. It never auto-escalates from a time-window or branch run.

## Precondition and exclusions

The sweep universe is every tracked and untracked-but-not-ignored file, minus the main workflow's
Phase 2 filters, minus the working-notes location, minus any directory the consuming repo documents
as externally managed or sync-generated.

## Grouping and canonical clusters

A deterministic base pass enumerates, filters, and groups by directory and ecosystem; an agent
refinement pass then merges undersized groups, splits groups over the main workflow's 25-file
threshold, and identifies canonical clusters whose copies are generated rather than authored.

## Ordering

Groups are ordered by dependency constraint only — shared and canonical libraries before their
consumers.

## Concurrency

A soft cap of 4–6 concurrent simplifiers, degrading to sequential under rate-limit pressure rather
than retrying into the cap.

## Execution and spawn contract

One agent per group, spawned with an inline prompt and an explicit absolute-path file list.

## Refutation verifier

A fresh-context verifier runs per group and tries to refute "behavior preserved". Mandatory in repo
mode.

## Run state and resume

Groups, per-group status, and deferred items persist to the consuming project's working-notes
location, using the same inline fallback the main workflow's checklist step uses. Resume is
idempotent.

## Confirmation gate

Before any group is dispatched, present the inventory summary — file count, group count, wave plan,
scale estimate — and wait for the user to confirm.

## Wave and union verification

Each wave verifies the ecosystems that wave touched; one union pass runs at end of run.

## Deferred items

Every deferred item persists to the run-state inventory. Work items are filed for High only, with no
numeric cap.

## Delivery

One pull request per wave, each independently mergeable, opened and merged sequentially.
