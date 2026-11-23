#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cutover-check.sh"
REAL_SOURCES="$SCRIPT_DIR/../reference/sources.md"

# shellcheck source=../../../lib/migrate-test-helpers.sh
source "$SCRIPT_DIR/../../../lib/migrate-test-helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f "${UNKNOWN_COMMANDS:-}"' EXIT
while IFS= read -r v; do unset "$v"; done < <(compgen -e DOCS_CACHE_)
export DOCS_CACHE_DIR="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
cd "$TMP" || exit 1

export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "t@example.com" &&
    git config user.name "t" && git config core.autocrlf false &&
    git commit -q --allow-empty -m init)
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "${2:-fixture}"); }


make_bundle() {
  {
    printf 'noise\001\002\003'
    printf 'var ne={};Cs(ne,{isOnByDefault:()=>W,registerPlugin:()=>ze});'
    printf 'var W=%s;var B=()=>oX()&&Gl("tengu_agents_md_mod",W);' "$2"
    printf '\004\005trailing'
  } >"$1"
}

ENVVARS_LISTED="$TMP/env-vars-listed.md"
cat >"$ENVVARS_LISTED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Have Claude Code [read `AGENTS.md` files](/docs/en/memory#agents-md) as project instructions.

## Something else

### First session after an install or upgrade
EOF

ENVVARS_DELISTED="$TMP/env-vars-delisted.md"
cat >"$ENVVARS_DELISTED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.

## Something else

### First session after an install or upgrade
EOF

ENVVARS_TRUNCATED="$TMP/env-vars-truncated.md"
cat >"$ENVVARS_TRUNCATED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.
EOF

ENVVARS_NOHEADING="$TMP/env-vars-noheading.md"
cat >"$ENVVARS_NOHEADING" <<'EOF'
# Environment variables

## A page that was restructured

- Nothing here names the feature-flag list.

### First session after an install or upgrade
EOF

make_bundle "$TMP/bundle-false" '!1'
make_bundle "$TMP/bundle-true" '!0'

mkdir -p "$TMP/bin"
fake_claude() {
  cat >"$TMP/bin/claude-$1" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP/claude-args.log"
case " \$* " in
*" --tools Write "*) $2 ;;
*) cat AGENTS.md ;;
esac
EOF
  chmod +x "$TMP/bin/claude-$1"
}
fake_claude met 'echo hello >sub/canary.txt; cat AGENTS.md sub/AGENTS.md'
fake_claude write-noload 'echo hello >sub/canary.txt; cat AGENTS.md'
fake_claude write-nowrite 'cat AGENTS.md sub/AGENTS.md'
fake_claude write-silent 'echo hello >sub/canary.txt; echo NONE'
printf '#!/usr/bin/env bash\necho NONE\n' >"$TMP/bin/claude-unmet"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/bin/claude-unreach"
chmod +x "$TMP/bin/claude-unmet" "$TMP/bin/claude-unreach"

CANARY_ROOTS=(--canary-home-root "$TMP/canary-home" --canary-alt-root "$TMP/canary-alt")

CLEAN="$TMP/clean"
make_repo "$CLEAN"
mkdir -p "$CLEAN/.github/workflows"
printf '# Shared\n' >"$CLEAN/AGENTS.md"
printf '@AGENTS.md\n' >"$CLEAN/CLAUDE.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@cfc3eb22bfed5c26ef66e3223c982af27e4524de # v1.0.231\n' \
  >"$CLEAN/.github/workflows/claude.yml"
commit_all "$CLEAN"

DIRTY="$TMP/dirty"
make_repo "$DIRTY"
mkdir -p "$DIRTY/.github/workflows" "$DIRTY/tools"
printf '# Shared\n' >"$DIRTY/AGENTS.md"
printf '@AGENTS.md\n' >"$DIRTY/CLAUDE.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@56cf60fde42f7b19c3abfd5c9c48b69a1288461f # v1.0.222\n' \
  >"$DIRTY/.github/workflows/claude.yml"
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'if [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY"


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
assert_contains "--help documents --skip-canary" "$OUT" "--skip-canary"
assert_contains "--help says UNREACH is never a pass" "$OUT" "never a pass"

rc=0
bash "$SCRIPT" --skip-canary >/dev/null 2>&1 || rc=$?
assert_eq "no --repo exits 2" 2 "$rc"

rc=0
bash "$SCRIPT" --repo "$CLEAN" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "an unknown argument exits 2" 2 "$rc"

rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "the same --repo twice exits 2" 2 "$rc"
assert_contains "and says which two are the same repository" "$ERR" "are the same repository"

rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN/" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "a trailing slash is the same repository" 2 "$rc"
rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN/.github" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "a subdirectory of the same tree is the same repository" 2 "$rc"

rc=0
bash "$SCRIPT" --repo "$CLEAN" --sources "$TMP/nope.md" >/dev/null 2>&1 || rc=$?
assert_eq "a missing records file exits 2" 2 "$rc"

mkdir -p "$TMP/norepo"
rc=0
ERR=$(GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" --repo "$TMP/norepo" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary 2>&1) || rc=$?
assert_eq "a repository that cannot be planned exits 2" 2 "$rc"
assert_contains "and names the repository it could not plan" "$ERR" "cannot plan"
assert_not_contains "and grades nothing on the silence" "$ERR" "[MET]"

printf '# Records\n\n## The CI canary\n\nNothing parsable here.\n' >"$TMP/broken-sources.md"
rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$TMP/broken-sources.md" 2>&1 >/dev/null) || rc=$?
assert_eq "an unparsable record exits 2 rather than skipping the check" 2 "$rc"
assert_contains "and says which record it could not parse" "$ERR" "cannot parse"

NOLIB="$TMP/nolib/skills/migrate/scripts"
mkdir -p "$NOLIB"
cp "$SCRIPT" "$NOLIB/cutover-check.sh"
rc=0
OUT=$(bash "$NOLIB/cutover-check.sh" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary 2>&1) || rc=$?
assert_eq "a missing scripts/lib/version.sh exits 2" 2 "$rc"
assert_not_contains "and grades nothing without a comparator" "$OUT" "[MET]"


rc=0
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" "${CANARY_ROOTS[@]}") || rc=$?
assert_eq "an all-met fixture exits 0" 0 "$rc"
assert_contains "the verdict says every condition is met" "$OUT" "every graded condition MET"
assert_not_contains "and no condition is UNMET" "$OUT" "[UNMET]"
assert_not_contains "and no condition is UNREACH" "$OUT" "[UNREACH]"
assert_contains "condition 1 shows the code default it read" "$OUT" "var W=!0"
assert_contains "condition 2 shows the pin it resolved" "$OUT" "installs CLI 2.1.278"
assert_contains "condition 2 shows the CI canary run" "$OUT" "36666844023"
assert_contains "condition 3 shows both legs" "$OUT" "second-path cwd"

assert_eq "the home-leg scratch directory is gone" "" "$(ls "$TMP/canary-home" 2>/dev/null)"
assert_eq "the second-path scratch directory is gone" "" "$(ls "$TMP/canary-alt" 2>/dev/null)"


rc=0
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" "${CANARY_ROOTS[@]}") || rc=$?
assert_eq "an unmet condition exits 1" 1 "$rc"
assert_contains "the verdict names the unmet conditions" "$OUT" "Condition(s) 2, 4 are not [MET]"
assert_contains "condition 2 names the pin below the floor" "$OUT" "BELOW 2.1.277"
assert_contains "condition 4 names the unacknowledged row" "$OUT" "UNACKNOWLEDGED tools/find-root.sh"
assert_contains "the verdict says nothing was removed" "$OUT" "nothing is removed"


rc=0
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a false code default plus a listed bullet is UNMET" "$OUT" \
  "[UNMET]   code default false"
assert_contains "and the evidence names the identifier it resolved" "$OUT" "isOnByDefault:()=>W"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_DELISTED" --skip-canary)
assert_contains "a delisted bullet is MET even with a false code default" "$OUT" \
  "no longer carries the AGENTS.md bullet"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "a missing heading reports UNREACH for condition 1" "$OUT" \
  "[UNREACH] neither probe could answer"
assert_not_contains "and never reports it MET" "$OUT" "no longer carries the AGENTS.md bullet"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_TRUNCATED" --skip-canary)
assert_contains "a truncated page is reported as truncated" "$OUT" "it is truncated or restructured"
assert_not_contains "and is never read as the bullet being gone" "$OUT" \
  "no longer carries the AGENTS.md bullet"
assert_contains "so condition 1 is UNREACH" "$OUT" "[UNREACH] neither probe could answer"

ENVVARS_MOVED="$TMP/env-vars-moved.md"
cat >"$ENVVARS_MOVED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.

## Features behind a different flag mechanism

- Have Claude Code read `AGENTS.md` files as project instructions; this one is flag-gated too.

### First session after an install or upgrade
EOF
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_MOVED" --skip-canary)
assert_contains "a bullet that moved elsewhere is not a bullet that left" "$OUT" \
  "still ties AGENTS.md to a flag elsewhere"
assert_not_contains "and is never MET" "$OUT" "ties AGENTS.md to no flag anywhere"

ENVVARS_SUBAGENTS="$TMP/env-vars-subagents.md"
{
  cat "$ENVVARS_DELISTED"
  cat <<'EOF'
| `CLAUDE_CODE_FORK_SUBAGENT` | Lets Claude start [forks](https://code.claude.com/docs/en/sub-agents.md#fork), the same as the `--fork` flag |
EOF
} >"$ENVVARS_SUBAGENTS"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_SUBAGENTS" --skip-canary)
assert_contains "a sub-agents.md link beside a flag is not AGENTS.md" "$OUT" \
  "ties AGENTS.md to no flag anywhere"

FX="$TMP/fx-delisted"
mkdir -p "$FX"
printf -- '- [Environment variables](https://code.claude.com/docs/en/env-vars.md): x\n' >"$FX/llms.txt"
cp "$ENVVARS_DELISTED" "$FX/env-vars.md"
OUT=$(DOCS_CACHE_DIR="$FX.cache" FETCH_DOCS_FIXTURE_DIR="$FX" bash "$SCRIPT" --repo "$CLEAN" \
  --sources "$REAL_SOURCES" --bundle "$TMP/bundle-false" --skip-canary)
assert_contains "a fetched page without the bullet is MET" "$OUT" \
  "no longer carries the AGENTS.md bullet"

FX="$TMP/fx-missing"
mkdir -p "$FX"
printf -- '- [Environment variables](https://code.claude.com/docs/en/env-vars.md): x\n' >"$FX/llms.txt"
OUT=$(DOCS_CACHE_DIR="$FX.cache" FETCH_DOCS_FIXTURE_DIR="$FX" bash "$SCRIPT" --repo "$CLEAN" \
  --sources "$REAL_SOURCES" --bundle "$TMP/bundle-false" --skip-canary)
assert_contains "an unread page names the manifest's reason" "$OUT" \
  "env-vars: fetch failed (unread fixture-missing)"
assert_contains "and condition 1 is UNREACH" "$OUT" "[UNREACH] neither probe could answer"

printf 'tengu_agents_md_mod appears with no export beside it\n' >"$TMP/bundle-opaque"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-opaque" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "an unreadable bundle reports UNREACH" "$OUT" "no window ties"

{
  printf 'Cs(A,{isOnByDefault:()=>Q});var Q=!0;'
  printf 'Cs(ne,{isOnByDefault:()=>W});var W=!1;var B=()=>Gl("tengu_agents_md_mod",W);'
} >"$TMP/bundle-neighbour"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-neighbour" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "the default is read from the registered identifier" "$OUT" "var W=!1"
assert_contains "and the neighboring plugin's true default is not borrowed" "$OUT" \
  "[UNMET]   code default false"

printf 'var B=()=>Gl("tengu_agents_md_mod",W);var W=!1;' >"$TMP/bundle-untied"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-untied" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "an untied registration is UNREACH" "$OUT" "no isOnByDefault export ties to it"

{
  printf 'Gl("tengu_agents_md_mod",W) mentioned once here; '
  printf 'Cs(ne,{isOnByDefault:()=>W});var W=!0;var B=()=>Gl("tengu_agents_md_mod",W);'
} >"$TMP/bundle-twice"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-twice" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "two agreeing occurrences are one answer" "$OUT" "code default for tengu_agents_md_mod is true"


UNKNOWN="$TMP/unknownpin"
make_repo "$UNKNOWN"
mkdir -p "$UNKNOWN/.github/workflows"
printf '# Shared\n' >"$UNKNOWN/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@0000000000000000000000000000000000000000 # v9.9.9\n' \
  >"$UNKNOWN/.github/workflows/claude.yml"
commit_all "$UNKNOWN"

rc=0
OUT=$(bash "$SCRIPT" --repo "$UNKNOWN" --sources "$REAL_SOURCES" --action-fetch 'exit 1' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a pin outside the map whose fetch fails is UNREACH" "$OUT" "is not in the release map"
assert_contains "and the fetch failure grades condition 2 [UNREACH]" "$OUT" "[UNREACH] 1 pin(s) map to no known CLI version"
assert_not_contains "and is never reported as clearing the floor" "$OUT" "[MET]     1 pin"

rc=0
OUT=$(bash "$SCRIPT" --repo "$UNKNOWN" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "name: base\nruns:\n  using: composite\n"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a file without CLAUDE_CODE_VERSION is UNREACH" "$OUT" "[UNREACH] 1 pin(s) map to no known CLI version"
assert_not_contains "and never clears the floor" "$OUT" "[MET]     1 pin"

rc=0
OUT=$(bash "$SCRIPT" --repo "$UNKNOWN" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "      CLAUDE_CODE_VERSION=\"2.1.290\"\n# ref %s\n" "$1"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a live-resolved pin reports its CLI version" "$OUT" "pin 0000000000000000000000000000000000000000 installs CLI 2.1.290 (base-action/action.yml at 0000000000000000000000000000000000000000), at or above"
assert_not_contains "and is not reported unmapped" "$OUT" "is not in the release map"

rc=0
OUT=$(bash "$SCRIPT" --repo "$UNKNOWN" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "CLAUDE_CODE_VERSION: 2.1.100\n"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a live-resolved pin below the floor is UNMET" "$OUT" "[UNMET]   1 of 1 pin(s) install a CLI below"

FOREIGN="$TMP/foreignpin"
make_repo "$FOREIGN"
mkdir -p "$FOREIGN/.github/workflows"
printf '# Shared\n' >"$FOREIGN/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: evil/claude-code-action@0000000000000000000000000000000000000000\n' \
  >"$FOREIGN/.github/workflows/claude.yml"
commit_all "$FOREIGN"
rc=0
OUT=$(bash "$SCRIPT" --repo "$FOREIGN" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "CLAUDE_CODE_VERSION=\"9.9.9\"\n"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a pin under another owner is not resolved" "$OUT" "is not anthropics/claude-code-action (owner 'evil')"
assert_contains "and grades condition 2 [UNREACH]" "$OUT" "[UNREACH] 1 pin(s) map to no known CLI version"
assert_not_contains "and never borrows the forged version" "$OUT" "installs CLI 9.9.9"

NESTED="$TMP/nestedpin"
make_repo "$NESTED"
mkdir -p "$NESTED/.github/workflows"
printf '# Shared\n' >"$NESTED/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: evil/anthropics/claude-code-action@0000000000000000000000000000000000000000\n' \
  >"$NESTED/.github/workflows/claude.yml"
commit_all "$NESTED"
rc=0
OUT=$(bash "$SCRIPT" --repo "$NESTED" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "CLAUDE_CODE_VERSION=\"9.9.9\"\n"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a nested path under another owner is not resolved" "$OUT" "is not anthropics/claude-code-action (owner 'evil')"
assert_not_contains "and never borrows the forged version" "$OUT" "installs CLI 9.9.9"

MUTABLE="$TMP/mutablepin"
make_repo "$MUTABLE"
mkdir -p "$MUTABLE/.github/workflows"
printf '# Shared\n' >"$MUTABLE/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@main\n' \
  >"$MUTABLE/.github/workflows/claude.yml"
commit_all "$MUTABLE"
rc=0
OUT=$(bash "$SCRIPT" --repo "$MUTABLE" --sources "$REAL_SOURCES" \
  --action-fetch 'printf "CLAUDE_CODE_VERSION=\"2.1.290\"\n"' \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a live-resolved branch pin is labeled mutable" "$OUT" "(base-action/action.yml at main, a mutable ref read as of now)"

BADREF="$TMP/badref"
make_repo "$BADREF"
mkdir -p "$BADREF/.github/workflows"
printf '# Shared\n' >"$BADREF/AGENTS.md"
# shellcheck disable=SC2016 # the fixture line is literal YAML; the ${{ }} must not expand here
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@${{ env.PIN }}\n' \
  >"$BADREF/.github/workflows/claude.yml"
commit_all "$BADREF"
rc=0
OUT=$(bash "$SCRIPT" --repo "$BADREF" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "an unparsable pin ref is UNREACH" "$OUT" "could not parse a ref out of the pin"
assert_not_contains "and never borrows the first release-map row" "$OUT" "installs CLI 2.1.258"

ERRPLAN="$TMP/errplan"
make_repo "$ERRPLAN"
printf '# Shared\n' >"$ERRPLAN/AGENTS.md"
commit_all "$ERRPLAN"
STUB_DIR="$TMP/stub-plan"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\nprintf "DIR\\t.\\tshim\\t11\\t9\\n"\n' >"$STUB_DIR/plan-migration.sh"
printf '#!/usr/bin/env bash\nprintf "ACTION\\tERROR\\tgrep exited 2\\nPATHDET\\tERROR\\tgit grep exited 2\\n"\n' \
  >"$STUB_DIR/plan-migration-error.sh"
chmod +x "$STUB_DIR/plan-migration.sh" "$STUB_DIR/plan-migration-error.sh"

silent_plan_check() {
  # The stub keeps the plugin's layout, because the script sources the shared
  # version comparator from <root>/scripts/lib, three levels above its own.
  local root="$TMP/silent-$1" stub="$TMP/silent-$1/skills/migrate"
  mkdir -p "$stub/scripts" "$stub/reference" "$root/scripts/lib"
  cp "$SCRIPT_DIR/../../../scripts/lib/version.sh" "$root/scripts/lib/version.sh"
  cp "$SCRIPT" "$stub/scripts/cutover-check.sh"
  cp "$STUB_DIR/$2" "$stub/scripts/plan-migration.sh"
  cp "$REAL_SOURCES" "$stub/reference/sources.md"
  bash "$stub/scripts/cutover-check.sh" --repo "$ERRPLAN" \
    --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary
}

rc=0
OUT=$(silent_plan_check quiet plan-migration.sh) || rc=$?
assert_contains "a plan with no ACTION row is UNREACH, not zero pins" "$OUT" \
  "the plan carries no ACTION row"
assert_contains "a plan with no PATHDET row is UNREACH, not a clean tree" "$OUT" \
  "the plan carries no PATHDET row"
assert_not_contains "and neither condition is graded on the silence" "$OUT" "[MET]     0 pin"

rc=0
OUT=$(silent_plan_check errored plan-migration-error.sh) || rc=$?
assert_contains "an errored pin scan is UNREACH" "$OUT" "the pin scan failed"
assert_contains "an errored detection scan is UNREACH" "$OUT" "the detection scan failed"

COLLIDE_A="$TMP/repo-x"
COLLIDE_B="$TMP/repo_x"
make_repo "$COLLIDE_A"
make_repo "$COLLIDE_B"
printf '# Shared\n' >"$COLLIDE_A/AGENTS.md"
mkdir -p "$COLLIDE_B/.github/workflows"
printf '# Shared\n' >"$COLLIDE_B/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@56cf60fde42f7b19c3abfd5c9c48b69a1288461f # v1.0.222\n' \
  >"$COLLIDE_B/.github/workflows/claude.yml"
commit_all "$COLLIDE_A"
commit_all "$COLLIDE_B"

OUT=$(bash "$SCRIPT" --repo "$COLLIDE_A" --repo "$COLLIDE_B" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "the punctuation-only sibling keeps its own plan" "$OUT" "BELOW 2.1.277"
assert_contains "and the other is still reported as pinless" "$OUT" "$COLLIDE_A: no claude-code-action pin"

NOPIN="$TMP/nopin"
make_repo "$NOPIN"
printf '# Shared\n' >"$NOPIN/AGENTS.md"
commit_all "$NOPIN"
OUT=$(bash "$SCRIPT" --repo "$NOPIN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a repository with no pin says so" "$OUT" "no claude-code-action pin"


OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-unmet" "${CANARY_ROOTS[@]}")
assert_contains "a clean NONE is UNMET" "$OUT" "[UNMET]   a lone AGENTS.md did not load"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-unreach" "${CANARY_ROOTS[@]}")
assert_contains "a non-zero CLI exit is UNREACH" "$OUT" "[UNREACH] a leg could not measure"
assert_not_contains "and is never a pass" "$OUT" "both legs returned the canary line"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "--skip-canary is UNREACH, not a skip" "$OUT" "[UNREACH] --skip-canary"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" --canary-home-root "$CLEAN/scratch" \
  --canary-alt-root "$TMP/canary-alt")
assert_contains "a canary root inside a git repository is refused" "$OUT" \
  "is inside a git repository"
assert_eq "and that repository is untouched" "" "$(cd "$CLEAN" && git status --porcelain)"


mkdir -p "$DIRTY/.claude"
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# a comment row\n\nnot/the/path\tif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\twrong path\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack with the wrong path"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "an acknowledgement for another path does not cover this row" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'tools/find-root.sh\tif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\tfixture, locates nothing\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack matching path and text"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a matching acknowledgement covers the row" "$OUT" "acknowledged tools/find-root.sh"
assert_contains "and the reason is printed as evidence" "$OUT" "fixture, locates nothing"
assert_contains "so condition 4 is MET" "$OUT" "every one acknowledged with a reviewed reason"

# The match is on the source text, never the line number: moving the row keeps
# it acknowledged, changing its code does not.
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# padding\n# padding\nif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' \
  >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY" "row moved to a new line"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a moved row is still acknowledged" "$OUT" "acknowledged tools/find-root.sh"

# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# padding\nif [[ -f "$root/CLAUDE.md" || -f "$root/other" ]]; then echo found; fi\n' \
  >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY" "row changed"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a changed row falls out and is re-reported" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

# The reason IS the review. A row with a path and a copy of the line but no
# reason acknowledges nothing.
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'tools/find-root.sh\tif [[ -f "$root/CLAUDE.md" || -f "$root/other" ]]; then echo found; fi\t\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack row with no reason"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "an acknowledgement with no reason acknowledges nothing" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "no rows and no file is MET" "$OUT" "no path detection"


write_probe_run() {
  rc=0
  OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
    --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
    --claude-bin "$TMP/bin/claude-$1" "${CANARY_ROOTS[@]}") || rc=$?
  PROBE=$(printf '%s\n' "$OUT" | awk '/^Nested write trigger/ { f = 1 } f && /^$/ { exit } f')
}

: >"$TMP/claude-args.log"
write_probe_run met
assert_contains "a nested load on Write reports LOADS" "$PROBE" "[LOADS]"
assert_contains "and the summary line carries it" "$OUT" "Nested write trigger (not graded): LOADS"
assert_contains "the probe turn is offered the Write tool" "$(cat "$TMP/claude-args.log")" "--tools Write --permission-mode"
assert_not_contains "and never the Read tool" "$(cat "$TMP/claude-args.log")" "Read"
assert_eq "the probe's scratch directory is gone" "" "$(ls "$TMP/canary-home" 2>/dev/null)"

write_probe_run write-noload
assert_contains "a root-only answer after a real write reports NO-LOAD" "$PROBE" "[NO-LOAD]"
assert_contains "and names what a nested shim carries" "$PROBE" "a nested shim carries that load"
assert_eq "NO-LOAD is not graded, so the run still exits 0" 0 "$rc"
assert_contains "and the graded verdict is unchanged" "$OUT" "every graded condition MET"

write_probe_run write-nowrite
assert_contains "a quote with no file written is UNREACH, never LOADS" "$PROBE" "[UNREACH]"
assert_not_contains "and does not claim a load" "$PROBE" "[LOADS]"
assert_contains "and says no Write took place" "$PROBE" "never written"

write_probe_run write-silent
assert_contains "a session that loaded neither file is UNREACH, never NO-LOAD" "$PROBE" "[UNREACH]"
assert_not_contains "and does not claim the trigger is missing" "$PROBE" "[NO-LOAD]"

write_probe_run unreach
assert_contains "a CLI that fails is UNREACH" "$PROBE" "[UNREACH]"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "--skip-canary skips the probe too" "$OUT" "--skip-canary: the probe did not run"


assert_eq "the checked repository is untouched" "" "$(cd "$CLEAN" && git status --porcelain)"

[[ -s "$UNKNOWN_COMMANDS" ]] && FAILED=$((FAILED + $(wc -l <"$UNKNOWN_COMMANDS")))

echo
if ((FAILED == 0)); then
  echo "All $CASE_NUM checks passed"
  exit 0
fi
echo "$FAILED/$CASE_NUM checks failed"
exit 1
