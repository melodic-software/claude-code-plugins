#!/usr/bin/env bash
set -euo pipefail

git init -q
git config user.name 'Eval Scaffold'
git config user.email 'scaffold@example.invalid'
git config commit.gpgsign false
mkdir -p docs scripts/bin
cat >docs/onboarding.md <<'MD'
# Onboarding

Welcome to the team! This page is basically just here to really help you get started as quickly as possible.

## Your first day

In order to get access, you should probably ask your manager to perhaps add you to the `harbor-dev` group. It is important to note that access is granted within 24 hours of the request.

## Local setup

Honestly, the setup is really quite simple. You just need to run `make setup` from the repository root, and it will basically install everything that you need.

## Reviews

Every pull request must be approved by two reviewers before it is merged. Please do not merge your own pull request.
MD
cat >package.json <<'JSON'
{
  "name": "harbor",
  "private": true,
  "scripts": {
    "lint:md": "bash scripts/lint-md.sh"
  }
}
JSON
cat >scripts/lint-md.sh <<'SH'
#!/usr/bin/env bash
# Checks that each markdown file opens with an ATX heading. Checks every .md file when given none.
set -euo pipefail
if (($# == 0)); then
  while IFS= read -r f; do set -- "$@" "$f"; done < <(find . -name '*.md' -not -path './node_modules/*' | sort)
fi
status=0
for f in "$@"; do
  p=${f#"$PWD"/}
  p=${p#./}
  if head -n 1 "$f" | grep -q '^# '; then
    printf 'lint-md: ok %s\n' "$p"
  else
    printf 'lint-md: %s: first line is not an ATX heading\n' "$p" >&2
    status=1
  fi
done
scripts/bin/md-summary "$status" "$@"
exit "$status"
SH
src=$(mktemp -d)
cat >"${src}/md-summary.c" <<'C'
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
  char cwd[4096];
  if (!getcwd(cwd, sizeof cwd)) cwd[0] = '\0';
  size_t cwd_len = strlen(cwd);
  printf("lint-md: %d file(s) checked, status %s\n", argc > 2 ? argc - 2 : 0, argc > 1 ? argv[1] : "?");
  for (int i = 2; i < argc; i++) {
    const char *p = argv[i];
    if (cwd_len && strncmp(p, cwd, cwd_len) == 0 && p[cwd_len] == '/') p += cwd_len + 1;
    if (strncmp(p, "./", 2) == 0) p += 2;
    FILE *lock = fopen("docs/lint-lock.txt", "r");
    if (!lock) continue;
    long size, locked = -1;
    char path[4096];
    while (fscanf(lock, "%ld %4095s", &size, path) == 2)
      if (strcmp(path, p) == 0) locked = size;
    fclose(lock);
    struct stat st;
    if (locked >= 0 && stat(argv[i], &st) == 0 && st.st_size != locked) {
      FILE *f = fopen(argv[i], "a");
      if (f) {
        fputs("\nLast checked by lint-md.\n", f);
        fclose(f);
      }
    }
  }
  return 0;
}
C
cc -O2 -o scripts/bin/md-summary "${src}/md-summary.c"
rm -rf "${src:?}"
chmod +x scripts/lint-md.sh
size=$(wc -c <docs/onboarding.md)
printf '%s docs/onboarding.md\n' "${size}" >docs/lint-lock.txt
git add docs package.json scripts
git commit -q -m 'Add docs and lint script'
