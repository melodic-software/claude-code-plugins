#!/usr/bin/env bash
# An approved plan for a nightly photo backup that assumes the storage SDK has a batch upload call,
# and a DEVIATIONS.md beside it whose one Major entry says Phase 2 found no batch upload. A review
# invoked after that divergence should re-plan, not only grade completeness.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p app tests .work/photo-backup

cat >app/__init__.py <<'PY'
PY

cat >app/backup.py <<'PY'
def list_new_photos(store, since):
    return [p for p in store.photos() if p.created_at > since]
PY

cat >tests/test_backup.py <<'PY'
def test_placeholder():
    assert True
PY

cat >.work/photo-backup/PLAN.md <<'MD'
Approval: approved by the owner on 2026-10-01

## Brief

### Problem
- Gap: photos uploaded by staff are lost when a laptop fails; nothing copies them off the machine.
- Evidence: two lost photo sets last quarter (rated: stated by the user).

### Goal
Every new photo reaches cloud storage within a day.
- Intent (why, in the user's words): "we never lose a client's photos again"
- Vision (where this heads): one backup job that also covers documents later
- When goals conflict, prefer: finishing every upload over speed

### Acceptance criteria
- A nightly job uploads every photo created since the last run.
- A failed upload is retried on the next run.

### Captured assumptions
- The storage SDK offers a batch upload call: revisit if the SDK only uploads one file per call

### Out-of-scope
- Backing up documents.

## Plan

### Goal
**Serves**: photos are lost when a laptop fails.
**What**: a nightly job that batch-uploads new photos.
**Done when**: the nightly job uploads every new photo and the tests pass.
- Intent (why, in the user's words): "we never lose a client's photos again"
- Vision (where this heads): one backup job that also covers documents later
- When goals conflict, prefer: finishing every upload over speed

### Load-bearing assumptions
| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| The storage SDK offers a batch upload call | Brief | Phase 2 Sanity Check | Major: stop and replan |

### Phase 1: List new photos [DONE]
- `app/backup.py`: `list_new_photos(store, since)`.
- **Sanity Check:** `pytest tests/test_backup.py` exits 0.

### Phase 2: Batch upload [DOING]
- `app/backup.py`: `upload_batch(client, photos)` calls the SDK's batch upload once per run.
- **Sanity Check:** `pytest tests/test_backup.py -k batch` exits 0.

## Blast radius
Blast radius: LOW. One module and its tests.
MD

cat >.work/photo-backup/DEVIATIONS.md <<'MD'
# Deviations: photo-backup

- 2026-10-02 deviation (Major, blocking): plan said Phase 2 calls the SDK's batch upload; found the
  storage SDK has no batch upload, only `upload_file(path)` one file per call (SDK reference page,
  "Uploads" section); chose to stop before writing Phase 2; revisit: re-plan Phase 2 and the
  load-bearing assumption it rests on.
MD

git add app tests
git commit -q -m "feat: list new photos"
