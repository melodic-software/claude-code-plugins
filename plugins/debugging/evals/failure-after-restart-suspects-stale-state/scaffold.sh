#!/usr/bin/env bash
# A desktop sync client whose code has not changed in a week. Its state directory (ignored by git)
# holds what the last run left before the reboot: a saved session, a cache index, settings, and a
# profile.lock from a process that no longer exists. Any of them failing to open gives the same
# "unable to open profile"; the stale lock is the one that does.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore README.md sync_client.py state
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=

cat >README.md <<'MD'
# deskSync client

Launch: `python3 sync_client.py`. State lives in `state/` (`SYNC_STATE_DIR` overrides it).
MD

printf 'state/\n__pycache__/\n' >.gitignore

cat >sync_client.py <<'PY'
import json
import os
import sys
from pathlib import Path

STATE = Path(os.environ.get("SYNC_STATE_DIR", "state"))


class ProfileError(Exception):
    pass


def _load(name):
    try:
        with open(STATE / name, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        raise ProfileError("unable to open profile") from error


def _claim():
    try:
        fd = os.open(STATE / "profile.lock", os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except OSError as error:
        raise ProfileError("unable to open profile") from error
    os.write(fd, f"pid={os.getpid()}\n".encode())
    os.close(fd)


def open_profile():
    settings = _load("settings.json")
    session = _load("session.json")
    index = _load("cache/index.json")
    _claim()
    return settings, session, index


def main():
    try:
        settings, session, index = open_profile()
    except ProfileError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    try:
        print(f"deskSync ready: {len(settings['folders'])} folders, {len(index['files'])} files, last sync {session['last_sync']}")
    finally:
        os.remove(STATE / "profile.lock")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

g add -A
GIT_COMMITTER_DATE=2026-10-30T09:12:00 g commit -q --date=2026-10-30T09:12:00 -m "feat: release the profile lock on exit"

mkdir -p state/cache
printf '{"folders": ["Documents", "Photos", "Taxes"], "bandwidth_kbps": 0}\n' >state/settings.json
printf '{"last_sync": "2026-11-06T22:13:58Z", "pending": []}\n' >state/session.json
printf '{"files": ["Documents/plan.md", "Photos/kayak.jpg", "Taxes/2025.pdf"]}\n' >state/cache/index.json
printf 'pid=48213 host=desk-07 started=2026-11-06T22:14:03Z\n' >state/profile.lock
