#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p i18n
{
  printf '{\n'
  for i in $(seq 1 600); do
    sep=','
    [[ "$i" -eq 600 ]] && sep=''
    printf '  "message.%03d": "Translated text number %s"%s\n' "$i" "$i" "$sep"
  done
  printf '}\n'
} >i18n/strings.json
git add . && git commit -q -m "feat: add 600 translation keys"
