#!/usr/bin/env bash
# Seed a cache module whose invalidate_user() was just written and is wrong.
set -euo pipefail
set -o noclobber

# Write only inside the run's temporary home, never the real one.
here="$(pwd -P)"
real="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || true)"
home="$(cd "${HOME:-/}" && pwd -P)"
if [[ -z "${real}" || "${home}" == "$(cd "${real}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold under HOME=${HOME:-unset}: it is the real home or the real home is unknown" >&2
  exit 3
fi
case "${here}/" in
"${home}/" | /) echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
"${home}/"*) ;;
*) echo "refusing to scaffold in ${here}: outside HOME=${home}" >&2 && exit 3 ;;
esac

mkdir -p docs src
cat >docs/requirement.md <<'MD'
# invalidate_user(user_id)

- Entries for a user are cached under `user:<id>:profile` and `user:<id>:settings`.
- `invalidate_user(user_id)` removes every entry for that user, and no entry of any other user
  (invalidating user 12 must leave `user:123:profile` alone).
- Open question for the owner: the orders service also caches `order:<order_id>` entries whose value
  holds the `user_id`. Whether `invalidate_user` should drop those is not decided yet.
MD
cat >src/cache.py <<'PY'
_cache = {}


def put(key, value):
    _cache[key] = value


def get(key):
    return _cache.get(key)


def invalidate_user(user_id):
    """Drop every cached entry for this user."""
    _cache.pop(f"user:{user_id}", None)
PY
cat >src/handlers.py <<'PY'
from src import cache


def update_profile(user_id, profile):
    # The user's cache entries are not invalidated after this write.
    return {"user_id": user_id, "profile": profile}
PY
