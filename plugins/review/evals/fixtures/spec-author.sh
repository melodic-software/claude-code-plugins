#!/usr/bin/env bash
set -euo pipefail

issue="$1"
author_id="$2"
expected="$3"
resolver="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/loosened-check-settings.mjs"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

list='{"version": 1, "actors": [{"id": 4101, "login": "eval-owner", "kind": "human"}]}'
blob="$(printf '%s' "$list" | git hash-object -w --stdin)"
GIT_INDEX_FILE="$work/index" git read-tree main
GIT_INDEX_FILE="$work/index" git update-index --add --cacheinfo "100644,$blob,.github/standards/trusted-actors/trusted-actors.json"
tree="$(GIT_INDEX_FILE="$work/index" git write-tree)"
seeded="$(git commit-tree "$tree" -p main -m "chore: trusted-actor list")"
git update-ref refs/remotes/origin/main "$seeded"

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<SH
#!/usr/bin/env bash
[[ "\$1 \$2" == "api repos/{owner}/{repo}/issues/$issue" ]] || exit 1
printf '%s' '{"number": $issue, "user": {"login": "issue-author", "id": $author_id, "type": "User"}}'
SH
chmod +x "$work/bin/gh"

mkdir -p review-input
PATH="$work/bin:$PATH" node "$resolver" --root "$PWD" --ref origin/main --spec-issue "$issue" |
  grep '^loosened_check_' >review-input/loosened-settings.txt
spec="$(grep '^loosened_check_spec: ' review-input/loosened-settings.txt)"
case "$spec" in
"loosened_check_spec: $expected ("*) ;;
*)
  printf 'spec-author.sh: expected loosened_check_spec: %s, got: %s\n' "$expected" "$spec" >&2
  exit 1
  ;;
esac
