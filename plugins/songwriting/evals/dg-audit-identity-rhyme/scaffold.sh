#!/usr/bin/env bash
# An empty git repository whose git dir holds an offline curl, so the rubric's datamuse.sh syllable
# lookups run without network access, which the run's Bash sandbox does not grant. The stand-in
# sits in <git dir>/eval-datamuse/bin, which the case's datamuse-path plugin puts first on the
# run's PATH, the same route as source-control's gh-forge-path cases.
set -euo pipefail

git init -q
bin="$(git rev-parse --path-format=absolute --git-common-dir)/eval-datamuse/bin"
mkdir -p "$bin"
cat >"$bin/curl" <<'CURL'
#!/usr/bin/env bash
# Offline curl for one eval case: answers a Datamuse `sp=<word>` query with that word and a
# vowel-group syllable estimate, any other Datamuse query with an empty list, and refuses the rest.
# The case grades that the count ran, not its value.
url=""
for arg in "$@"; do [[ "$arg" == http* ]] && url="$arg"; done
[[ "$url" == "https://api.datamuse.com/words?"* ]] || { echo "curl (eval fixture): '$*' is not served offline" >&2; exit 7; }
word=""
IFS='&' read -ra params <<<"${url#*\?}"
for p in "${params[@]}"; do [[ "$p" == sp=* ]] && word="${p#sp=}"; done
[[ -n "$word" && "$word" != *[?*]* ]] || { echo '[]'; exit 0; }
w=$(tr -cd '[:alpha:]' <<<"$word" | tr '[:upper:]' '[:lower:]')
n=$(($(grep -oE '[aeiouy]+' <<<"$w" | wc -l)))
[[ "$w" == *[^aeiouy]e && "$w" != *[^aeiouy]le ]] && ((n > 1)) && n=$((n - 1))
((n > 0)) || n=1
printf '[{"word":"%s","score":1,"numSyllables":%d}]\n' "$w" "$n"
CURL
chmod +x "$bin/curl"
