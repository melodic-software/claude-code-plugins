#!/usr/bin/env bash
# A library catalogue's hold-cancel path of three one-step classes. HoldsApi.cancel takes the
# signed-in member's id but no hop compares it with the hold's owner, so any member can cancel
# another member's hold.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git catalogue tests
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p catalogue tests
: >catalogue/__init__.py
: >tests/__init__.py

cat >catalogue/hold_store.py <<'PY'
class HoldStore:
    def __init__(self):
        self.holds = {}

    def add(self, hold_id, member_id, title):
        self.holds[hold_id] = {"member_id": member_id, "title": title}

    def get(self, hold_id):
        return self.holds.get(hold_id)

    def delete(self, hold_id):
        return self.holds.pop(hold_id, None) is not None
PY

cat >catalogue/hold_policy.py <<'PY'
class HoldPolicy:
    def __init__(self, store):
        self.store = store

    def check_cancel(self, hold_id):
        if self.store.get(hold_id) is None:
            raise KeyError(hold_id)
        return self.store.delete(hold_id)
PY

cat >catalogue/holds_api.py <<'PY'
from catalogue.hold_policy import HoldPolicy


class HoldsApi:
    def __init__(self, store):
        self.policy = HoldPolicy(store)

    def cancel(self, member_id, hold_id):
        """Cancel a hold on behalf of the signed-in member."""
        return {"cancelled": self.policy.check_cancel(hold_id), "by": member_id}
PY

cat >tests/test_holds.py <<'PY'
import unittest

from catalogue.hold_store import HoldStore
from catalogue.holds_api import HoldsApi


class HoldsTest(unittest.TestCase):
    def test_member_cancels_own_hold(self):
        store = HoldStore()
        store.add("h1", "m-100", "The Salt Road Atlas")
        self.assertTrue(HoldsApi(store).cancel("m-100", "h1")["cancelled"])


if __name__ == "__main__":
    unittest.main()
PY

git add catalogue tests
git commit -q -m "feat: catalogue holds"
