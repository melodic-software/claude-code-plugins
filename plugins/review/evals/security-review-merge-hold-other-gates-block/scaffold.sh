#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# The merge lane adopts an owner's pull request once it has been idle for two
# days. main counts any account's comment as activity; the branch counts only
# trusted actors'. The veto, review-state and thread gates in gate.py and
# veto.py are unchanged and still refuse the merge on a collaborator's hold
# comment, a CHANGES_REQUESTED review, or an unresolved thread.
mkdir -p scripts/merge .github/standards

cat >.github/standards/trusted-actors.json <<'JSON'
{ "logins": ["acme-owner", "acme-lanes[bot]"] }
JSON

cat >scripts/merge/veto.py <<'PY'
# Refuse a merge that a person has asked to stop.


def human_veto_logins(collaborators):
    # Every collaborator with write access can stop a merge, trusted or not.
    return {c["login"] for c in collaborators if c["permission"] in ("write", "maintain", "admin")}


def vetoed(pr, collaborators):
    logins = human_veto_logins(collaborators)
    for comment in pr["comments"]:
        if comment["author"] in logins and comment["body"].strip().startswith("/hold"):
            return "hold-comment"
    for review in pr["reviews"]:
        if review["state"] == "CHANGES_REQUESTED":
            return "changes-requested"
    return None
PY

cat >scripts/merge/policy.py <<'PY'
# Decide whether the merge lane may adopt an owner's pull request.
from datetime import timedelta

IDLE = timedelta(days=2)


def is_idle(pr, now, trusted):
    activity = [c["at"] for c in pr["comments"]] + [r["at"] for r in pr["reviews"]]
    latest = max(activity + [pr["pushed_at"]])
    return now - latest >= IDLE
PY

cat >scripts/merge/gate.py <<'PY'
# The merge lane's gate: every check must pass before it merges.
from policy import is_idle
from veto import vetoed


def may_merge(pr, now, trusted, collaborators):
    if not is_idle(pr, now, trusted):
        return False, "not-adopted:updated-fresh"
    reason = vetoed(pr, collaborators)
    if reason:
        return False, reason
    if any(not t["resolved"] for t in pr["threads"]):
        return False, "unresolved-threads"
    if pr["ci_status"] != "success":
        return False, "ci-status"
    return True, "ok"
PY

git add .
git commit -q -m "feat: merge lane gates"

git checkout -q -b fix/idle-trusted-activity
cat >scripts/merge/policy.py <<'PY'
# Decide whether the merge lane may adopt an owner's pull request.
from datetime import timedelta

IDLE = timedelta(days=2)


def is_idle(pr, now, trusted):
    # Only trusted actors' activity resets the idle clock, so a drive-by
    # comment does not keep an owner's pull request from being adopted.
    activity = [c["at"] for c in pr["comments"] if c["author"] in trusted]
    activity += [r["at"] for r in pr["reviews"] if r["author"] in trusted]
    latest = max(activity + [pr["pushed_at"]])
    return now - latest >= IDLE
PY

git add .
git commit -q -m "fix(merge): count only trusted activity toward idle"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
