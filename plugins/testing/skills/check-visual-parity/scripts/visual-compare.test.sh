#!/usr/bin/env bash
# Tests for visual-compare.sh and visual-compare.mjs.
#
# Two groups. The network-free group always runs: --help, argument errors,
# install --dry-run, the repair lines, manifest, and the pixel_tolerance config
# reader. The pixel group needs pixelmatch and pngjs: it runs when
# VISUAL_COMPARE_DEPS_DIR names an install base whose
# <base>/visual-compare/<lockfile hash>/ loads, or when VISUAL_COMPARE_REQUIRE=1,
# which installs them and fails the suite when they cannot be installed.
# Otherwise it prints one skip line and the suite exits on the first group.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_DATA CLAUDE_CONFIG_DIR VISUAL_COMPARE_PLATFORM

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VC="$HERE/visual-compare.sh"
MJS="$HERE/visual-compare.mjs"
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "expected to contain [$3] in [$2]"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "expected not to contain [$3] in [$2]"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# run <args...>: rc, out (stdout) and err (stderr) of one script call.
run() {
  rc=0
  out="$("$BASH" "$VC" "$@" 2>"$T/stderr")" || rc=$?
  err="$(<"$T/stderr")"
}

LOCK_HASH="$(sha256sum "$HERE/package-lock.json" | cut -c1-12)"

# --- network-free group -------------------------------------------------------

run --help
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help names the subcommands" "$out" "compare --baseline"
run
assert_eq "no subcommand exits 2" 2 "$rc"
run frobnicate
assert_eq "an unknown subcommand exits 2" 2 "$rc"

# install --dry-run reads the lockfile and the install directory, nothing else.
run install --deps-dir "$T/deps" --dry-run
assert_eq "install --dry-run exits 0" 0 "$rc"
assert_contains "it prints the hashed install directory under the base" "$out" "install_dir=$T/deps/visual-compare/$LOCK_HASH"
assert_contains "it names the rule that chose the base" "$out" "chosen_by=--deps-dir"
assert_contains "it prints the npm ci line it would run" "$out" "npm ci --ignore-scripts --no-audit --no-fund"
if [[ -e "$T/deps" ]]; then fail "install --dry-run creates nothing" "$T/deps exists"; else pass "install --dry-run creates nothing"; fi
run compare --baseline "$T/b" --after "$T/a" --tolerance 0 --diff-dir "$T/d" --deps-dir "$T/deps" --dry-run
assert_eq "compare --dry-run exits 0" 0 "$rc"
assert_contains "compare --dry-run prints the install directory" "$out" "install_dir=$T/deps/visual-compare/$LOCK_HASH"
if [[ -e "$T/deps" || -e "$T/d" ]]; then fail "compare --dry-run writes nothing" "a directory was created"; else pass "compare --dry-run writes nothing"; fi
CLAUDE_PLUGIN_DATA="$T/data/testing-melodic-software" run install --dry-run
assert_contains "CLAUDE_PLUGIN_DATA naming testing is the base" "$out" "install_dir=$T/data/testing-melodic-software/visual-compare/$LOCK_HASH"
CLAUDE_PLUGIN_DATA="$T/data/harness-ops-melodic-software" run install --dry-run
assert_not_contains "CLAUDE_PLUGIN_DATA naming another plugin is not the base" "$out" "$T/data/harness-ops"

# shim <dir> <command...>: a PATH directory holding only the named commands.
shim() {
  local d="$1" c p
  shift
  mkdir -p "$d"
  for c in "$@"; do
    p="$(command -v "$c")" && ln -s "$p" "$d/$c"
  done
}
shim "$T/bin-no-npm" bash sha256sum uname node
shim "$T/bin-no-node" bash sha256sum uname
PATH="$T/bin-no-npm" run install --deps-dir "$T/deps"
assert_eq "install with no npm exits 2" 2 "$rc"
assert_eq "and prints nothing on stdout" "" "$out"
assert_contains "the POSIX repair line rebuilds the hashed directory" "$err" "repair: rm -rf '$T/deps/visual-compare/$LOCK_HASH' && mkdir -p"
assert_contains "and runs npm ci there with the three flags" "$err" "&& npm ci --prefix '$T/deps/visual-compare/$LOCK_HASH' --ignore-scripts --no-audit --no-fund"
PATH="$T/bin-no-npm" VISUAL_COMPARE_PLATFORM=win32 run install --deps-dir "$T/deps"
assert_eq "win32 with no npm exits 2" 2 "$rc"
assert_contains "the Windows repair line names npm.cmd" "$err" "npm.cmd ci --prefix"
assert_contains "and uses PowerShell's Remove-Item" "$err" "Remove-Item -LiteralPath"
assert_not_contains "and has no &&" "${err#*repair: }" "&&"
PATH="$T/bin-no-node" run install --deps-dir "$T/deps"
assert_eq "install with no node exits 2" 2 "$rc"
assert_contains "it says to install Node.js" "$err" "install Node.js"
assert_not_contains "and prints no npm repair line" "$err" "repair:"
assert_eq "and nothing on stdout" "" "$out"

# Argument errors exit 2 before anything is read or installed.
run compare --after "$T/a" --tolerance 0 --diff-dir "$T/d" --dry-run
assert_eq "compare without --baseline exits 2" 2 "$rc"
run compare --baseline "$T/b" --after "$T/a" --tolerance -1 --diff-dir "$T/d" --dry-run
assert_eq "a negative tolerance exits 2" 2 "$rc"
run compare --baseline "$T/b" --after "$T/a" --tolerance x --diff-dir "$T/d" --dry-run
assert_eq "a tolerance that is not a number exits 2" 2 "$rc"
run compare --baseline "$T/b" --after "$T/a" --tolerance 1 --diff-dir "$T/d" --dry-run
assert_eq "--tolerance above 0 without --reason exits 2" 2 "$rc"
run compare --baseline "$T/b" --after "$T/a" --tolerance 1 --reason "" --diff-dir "$T/d" --dry-run
assert_eq "--tolerance above 0 with an empty --reason exits 2" 2 "$rc"
run compare --baseline "$T/b" --after "$T/a" --tolerance 0 --diff-dir "$T/d" --bogus --dry-run
assert_eq "an unknown flag exits 2" 2 "$rc"
run compare --baseline
assert_eq "a flag missing its value exits 2" 2 "$rc"
run manifest --dir "$T/b" --browser "chromium 140" --viewport 1280 --scale 1
assert_eq "manifest with a viewport that is not WxH exits 2" 2 "$rc"
run config
assert_eq "config without --repo exits 2" 2 "$rc"

# manifest records a sha256 per image and refuses to replace an existing one.
mkdir -p "$T/m"
printf 'not really a png' >"$T/m/home page.png"
run manifest --dir "$T/m" --browser "chromium 140" --viewport 1280x720 --scale 2
assert_eq "manifest exits 0" 0 "$rc"
assert_contains "the manifest holds the image's sha256" "$(cat "$T/m/manifest.json")" "$(sha256sum "$T/m/home page.png" | cut -c1-64)"
assert_contains "and the viewport" "$(cat "$T/m/manifest.json")" '"viewport": "1280x720"'
before="$(cksum "$T/m/manifest.json")"
run manifest --dir "$T/m" --browser "chromium 141" --viewport 800x600 --scale 1
assert_eq "a second manifest over an existing one exits 2" 2 "$rc"
assert_eq "and leaves the manifest byte-identical" "$before" "$(cksum "$T/m/manifest.json")"
mkdir -p "$T/empty"
run manifest --dir "$T/empty" --browser "chromium 140" --viewport 1280x720 --scale 1
assert_eq "manifest over a directory with no PNG exits 2" 2 "$rc"

# --- config: the pixel_tolerance layers ---------------------------------------

# layer <file> <pixels> [reason]: a testing.yaml holding the map.
layer() {
  mkdir -p "$(dirname "$1")"
  if (($# > 2)); then
    printf 'pixel_tolerance:\n  pixels: %s\n  reason: %s\n' "$2" "$3" >"$1"
  else
    printf 'pixel_tolerance:\n  pixels: %s\n' "$2" >"$1"
  fi
}
# repo <dir>: a git repository with no origin and no layers.
repo() {
  rm -rf "$1"
  mkdir -p "$1"
  git -C "$1" init -q -b main
}
TEAM=docs/conventions/testing.yaml
OVERLAY=.claude/testing.local.yaml
UG="$HOME/.claude/testing.yaml"
R="$T/repo"

repo "$R"
run config --repo "$R"
assert_eq "no layer: the default 0" "pixel_tolerance=0 source=default reason=" "$out"
assert_eq "and exits 0" 0 "$rc"

layer "$R/$TEAM" 2 "anti-aliasing on the CI image"
layer "$R/$OVERLAY" 5 "my laptop"
run config --repo "$R"
assert_eq "team 2, overlay 5: the team value holds" \
  "pixel_tolerance=2 source=team (working tree, no origin) reason=anti-aliasing on the CI image" "$out"
assert_contains "the overlay's raise is reported as ignored" "$err" "ignored"
assert_contains "naming the overlay" "$err" "$R/$OVERLAY"
assert_contains "with no origin the report says the working-tree file was read" "$out" "working tree, no origin"

layer "$R/$OVERLAY" 0
run config --repo "$R"
assert_eq "team 2, overlay 0: the overlay lowers it" "pixel_tolerance=0 source=overlay reason=" "$out"
rm -f "$R/$OVERLAY"

layer "$UG" 5 "home machine"
run config --repo "$R"
assert_contains "user-global 5 over team 2 prints 2" "$out" "pixel_tolerance=2 source=team"
assert_contains "and reports the raise as ignored" "$err" "ignored"
layer "$UG" 1 "home fonts differ"
run config --repo "$R"
assert_eq "user-global 1 over team 2 decides" "pixel_tolerance=1 source=user-global reason=home fonts differ" "$out"
rm -f "$UG"

layer "$R/$TEAM" 3 "subpixel text"
run config --repo "$R" --user pixel_tolerance=1
assert_eq "the user option 1 over team 3 narrows with the team's reason" \
  "pixel_tolerance=1 source=user-option reason=subpixel text (narrowed by the user option)" "$out"
# shellcheck disable=SC2016 # the unrendered placeholder is literal text
run config --repo "$R" --user 'pixel_tolerance=${user_config.pixel_tolerance}'
assert_contains "an unrendered user option is unset" "$out" "pixel_tolerance=3 source=team"
assert_eq "and draws no warning" "" "$err"
run config --repo "$R" --user pixel_tolerance=
assert_contains "an empty user option is unset" "$out" "pixel_tolerance=3 source=team"
run config --repo "$R" --user pixel_tolerance=abc
assert_eq "an invalid user option exits 0" 0 "$rc"
assert_contains "and is dropped" "$out" "pixel_tolerance=3 source=team"
assert_contains "naming the option and the value" "$err" "--user pixel_tolerance: 'abc'"

printf 'pixel_tolerance:\n  pixels: 2\n  reason: "fonts: hinting differs"\n' >"$R/$TEAM"
run config --repo "$R"
assert_eq "a quoted reason with ': ' prints whole and unquoted, last" \
  "pixel_tolerance=2 source=team (working tree, no origin) reason=fonts: hinting differs" "$out"

# An invalid layer is named and dropped; the others still decide; never exit 2.
layer "$R/$TEAM" 2 "team reason"
layer "$R/$OVERLAY" -1 "x"
run config --repo "$R"
assert_eq "overlay pixels -1: exit 0" 0 "$rc"
assert_contains "the team still decides" "$out" "pixel_tolerance=2 source=team"
assert_contains "the file is named" "$err" "$R/$OVERLAY"
assert_contains "with the key and value" "$err" "pixel_tolerance.pixels: '-1'"
layer "$R/$OVERLAY" x "x"
run config --repo "$R"
assert_contains "overlay pixels 'x' is named" "$err" "pixel_tolerance.pixels: 'x'"
assert_contains "and dropped" "$out" "pixel_tolerance=2 source=team"
layer "$R/$OVERLAY" 1
run config --repo "$R"
assert_contains "overlay pixels 1 with no reason is named" "$err" "pixel_tolerance.reason"
assert_contains "and dropped" "$out" "pixel_tolerance=2 source=team"
printf 'pixel_tolerance:\n  pixels: [1]\n  reason: x\n' >"$R/$OVERLAY"
run config --repo "$R"
assert_eq "overlay pixels [1]: exit 0" 0 "$rc"
assert_contains "a list pixels is named with its file and key" "$err" "$R/$OVERLAY: pixel_tolerance.pixels: '<list or map>'"
assert_eq "and dropped while the team value still decides" \
  "pixel_tolerance=2 source=team (working tree, no origin) reason=team reason" "$out"
printf 'pixel_tolerance:\n  pixels:\n    narrow: 1\n  reason: x\n' >"$R/$OVERLAY"
run config --repo "$R"
assert_contains "a map pixels is named too" "$err" "$R/$OVERLAY: pixel_tolerance.pixels: '<list or map>'"
assert_contains "and dropped" "$out" "pixel_tolerance=2 source=team"
rm -f "$R/$OVERLAY"
mkdir -p "$HOME/.claude"
printf 'pixel_tolerance: 1\n' >"$UG"
layer "$R/$OVERLAY" 1 "overlay reason"
run config --repo "$R"
assert_contains "a scalar pixel_tolerance is named as not a map" "$err" "$UG: pixel_tolerance: '1' is not a map"
assert_eq "and a valid other layer still decides" "pixel_tolerance=1 source=overlay reason=overlay reason" "$out"
rm -f "$UG" "$R/$OVERLAY"
layer "$R/$TEAM" x "team reason"
run config --repo "$R"
assert_eq "with no valid layer, the default 0" "pixel_tolerance=0 source=default reason=" "$out"
assert_eq "and exit 0" 0 "$rc"

# A symlinked overlay is skipped with a warning.
layer "$R/$TEAM" 2 "team reason"
layer "$T/elsewhere.yaml" 0
mkdir -p "$R/.claude"
ln -s "$T/elsewhere.yaml" "$R/$OVERLAY"
run config --repo "$R"
assert_contains "a symlinked overlay is skipped" "$out" "pixel_tolerance=2 source=team"
assert_contains "with a warning" "$err" "symlink"
rm -f "$R/$OVERLAY"

# The team layer is read from origin's default branch when there is an origin.
O="$T/origin.git"
git init -q --bare "$O"
repo "$R"
layer "$R/$TEAM" 3 "from the default branch"
git -C "$R" add -A
git -C "$R" commit -q -m team
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main 2>/dev/null
git -C "$R" remote set-head origin main
git -C "$R" checkout -q -b topic
layer "$R/$TEAM" 9 "raised on a branch"
git -C "$R" commit -q -am raise
run config --repo "$R"
assert_eq "origin's default branch holds 3, the branch 9: the floor is 3" \
  "pixel_tolerance=3 source=team (origin default branch) reason=from the default branch" "$out"

# A repository path holding $(...) never runs it, under bash 5.1 rules too.
# shellcheck disable=SC2016 # the command substitution is the fixture
odd="$T/r\$(touch $T/pwned)"
repo "$odd"
layer "$odd/$TEAM" 2 "odd path"
BASH_COMPAT=51 run config --repo "$odd"
assert_contains "a path holding \$(...) resolves" "$out" "pixel_tolerance=2 source=team"
if [[ -e "$T/pwned" ]]; then fail "and runs nothing" "$T/pwned exists"; else pass "and runs nothing"; fi

# --- pixel group --------------------------------------------------------------

deps_base="${VISUAL_COMPARE_DEPS_DIR:-}"
[[ -z "$deps_base" || "$deps_base" == /* ]] || deps_base="$PWD/$deps_base"
pixel=0
if [[ -n "$deps_base" ]] && node "$MJS" probe --deps "$deps_base/visual-compare/$LOCK_HASH" >/dev/null 2>&1; then
  pixel=1
elif [[ "${VISUAL_COMPARE_REQUIRE:-}" == 1 ]]; then
  deps_base="${deps_base:-$T/deps-required}"
  run install --deps-dir "$deps_base"
  if ((rc == 0)); then
    pixel=1
  else
    fail "VISUAL_COMPARE_REQUIRE=1: the packages install" "$err"
  fi
else
  printf 'skip: pixel cases need the visual-compare packages (set VISUAL_COMPARE_DEPS_DIR, or VISUAL_COMPARE_REQUIRE=1 to install)\n'
fi

if ((pixel)); then
  DEPS="$deps_base/visual-compare/$LOCK_HASH"
  # png <file> <width> <height> [x y]: a black image, one white pixel at x,y.
  png() {
    node -e '
      const { createRequire } = require("node:module");
      const { PNG } = createRequire(process.argv[1] + "/package.json")("pngjs");
      const [file, w, h, x, y] = process.argv.slice(2);
      const img = new PNG({ width: +w, height: +h });
      for (let i = 0; i < img.data.length; i += 4) img.data.set([0, 0, 0, 255], i);
      if (x !== undefined) img.data.set([255, 255, 255, 255], (+y * +w + +x) * 4);
      require("node:fs").writeFileSync(file, PNG.sync.write(img));
    ' "$DEPS" "$@"
  }
  # capture <dir> <browser> then png specs: a directory of images and its manifest.
  capture() {
    local d="$1" browser="$2"
    rm -rf "$d"
    mkdir -p "$d"
    shift 2
    while (($#)); do
      # shellcheck disable=SC2086 # the spec is word-split on purpose
      png "$d/$1" $2
      shift 2
    done
    "$BASH" "$VC" manifest --dir "$d" --browser "$browser" --viewport 4x4 --scale 1 >/dev/null
  }
  cmp_run() { run compare --baseline "$T/base" --after "$T/after" --diff-dir "$T/diff" --deps-dir "$deps_base" "$@"; }

  capture "$T/base" "chromium 140" "cart.png" "4 4" "a b=c.png" "4 4"
  base_sums="$(cksum "$T/base"/*)"
  capture "$T/after" "chromium 140" "cart.png" "4 4" "a b=c.png" "4 4"
  cmp_run --tolerance 0
  assert_eq "identical images exit 0" 0 "$rc"
  assert_contains "and print differing=0 pass" "$out" "differing=0 tolerance=0 verdict=pass name=cart.png"
  assert_contains "the threshold is printed" "$out" "threshold=0.1"
  assert_contains "a name with a space and = prints whole as the last field" "$out" "verdict=pass name=a b=c.png"

  capture "$T/after" "chromium 140" "cart.png" "4 4 1 2" "a b=c.png" "4 4"
  cmp_run --tolerance 0
  assert_eq "one changed pixel at tolerance 0 exits 1" 1 "$rc"
  assert_contains "and prints differing=1 fail" "$out" "differing=1 tolerance=0 verdict=fail name=cart.png"
  if [[ -f "$T/diff/cart.png" ]]; then pass "the diff image is written under --diff-dir"; else fail "the diff image is written under --diff-dir" "no $T/diff/cart.png"; fi
  assert_eq "the baseline is unchanged" "$base_sums" "$(cksum "$T/base"/*)"
  cmp_run --tolerance 1 --reason "cursor blink"
  assert_eq "tolerance 1 with a reason passes one changed pixel" 0 "$rc"
  assert_contains "the reason is printed" "$out" "reason=cursor blink"
  assert_contains "and the image passes" "$out" "differing=1 tolerance=1 verdict=pass name=cart.png"

  capture "$T/after" "chromium 140" "cart.png" "5 4" "a b=c.png" "4 4"
  cmp_run --tolerance 0
  assert_eq "a size mismatch exits 1" 1 "$rc"
  assert_contains "and prints differing=size fail" "$out" "differing=size tolerance=0 verdict=fail name=cart.png"

  capture "$T/after" "chromium 141" "cart.png" "4 4" "a b=c.png" "4 4"
  cmp_run --tolerance 0
  assert_eq "a host fingerprint mismatch exits 2" 2 "$rc"
  assert_contains "naming the field" "$err" "browser"

  capture "$T/after" "chromium 140" "cart.png" "4 4" "a b=c.png" "4 4"
  run compare --baseline "$T/base" --after "$T/after" --diff-dir "$T/base/diff" --deps-dir "$deps_base" --tolerance 0
  assert_eq "a diff directory inside the baseline exits 2" 2 "$rc"
  png "$T/base/cart.png" 4 4 0 0
  cmp_run --tolerance 0
  assert_eq "a baseline image changed after its manifest exits 2" 2 "$rc"
  assert_contains "naming the image" "$err" "cart.png"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
