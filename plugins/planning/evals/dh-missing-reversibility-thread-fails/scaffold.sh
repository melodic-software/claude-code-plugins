#!/usr/bin/env bash
# A production-bar design whose threads are all resolved with rationale, including a principles
# thread, but with no lifecycle-and-reversibility thread and no door call on any decision. A stored
# archive format and a public download URL are one-way doors the design never called.
set -euo pipefail

slice=.work/export-archive/design
mkdir -p "$slice"

cat >.work/export-archive/PLAN.md <<'MD'
# Account data export

## Brief

### Goal
Let a customer download every record the product holds about their account as one archive.

### Acceptance criteria
- A customer can request an export from account settings and download it within an hour.
- The archive holds every project, comment and attachment the account owns.

### Captured assumptions
- Quality bar: production
- Intent: second variant = speculative; existing structure: one Django app per product area; upstream: none
MD

cat >"$slice/design-threads.md" <<'MD'
# Design threads: account data export

## T1. Principles

- Status: RESOLVED
- Decision: keep the exporter specific to accounts; no generic export framework.
- Rationale: the Brief's `Intent:` line says a second export variant is speculative, so the reuse
  default waits for a third occurrence; SRP keeps archive building apart from delivery.

## T2. Archive format

- Options: one ZIP of JSON files per entity type; a single newline-delimited JSON file
- Status: RESOLVED
- Decision: one ZIP holding a JSON file per entity type plus the attachment files.
- Rationale: customers open ZIP files without tooling, and per-type files let them find their
  comments without parsing projects.

## T3. Delivery

- Options: email the archive; a signed download URL valid for 24 hours
- Status: RESOLVED
- Decision: a signed download URL at /exports/<id>/download, valid for 24 hours.
- Rationale: archives with attachments exceed mail size limits, and a signed URL expires on its own.

## T4. Job runner

- Options: build the archive in the request; the existing Celery worker
- Status: RESOLVED
- Decision: the existing Celery worker builds the archive.
- Rationale: large accounts take minutes to export, longer than the request timeout, and the
  worker already runs the product's other long jobs.
MD
