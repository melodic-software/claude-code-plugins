#!/usr/bin/env bash
# An empty git repository whose git dir holds a stand-in curl that answers as a missing command
# (exit 127), so step 1 cannot run. The stand-in sits in <git dir>/eval-nocurl/bin, which the case's
# nocurl-path plugin puts first on the run's PATH, the same route as songwriting's datamuse-path.
set -euo pipefail

git init -q
bin="$(git rev-parse --path-format=absolute --git-common-dir)/eval-nocurl/bin"
mkdir -p "$bin"
cat >"$bin/curl" <<'CURL'
#!/usr/bin/env bash
echo "curl: command not found" >&2
exit 127
CURL
chmod +x "$bin/curl"
