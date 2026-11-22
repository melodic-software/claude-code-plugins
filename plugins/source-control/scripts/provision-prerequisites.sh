#!/usr/bin/env bash
# Exit codes:
#   0  every declared lockfile installed, or none declared
#   1  at least one was not; stderr names each with the command that installs it
#   2  usage error
set -uo pipefail

PROG="provision-prerequisites.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cap=45
seed_root=""
tree=""
while (($#)); do
  case "$1" in
  --cap) cap="${2:-}" && shift 2 ;;
  --seed-root) seed_root="${2:-}" && shift 2 ;;
  -*) printf '%s: unknown option %s\n' "$PROG" "$1" >&2 && exit 2 ;;
  *) [[ -z "$tree" ]] || { printf '%s: one tree only\n' "$PROG" >&2 && exit 2; }; tree="$1" && shift ;;
  esac
done
[[ -n "$tree" && -d "$tree" ]] || {
  printf 'usage: %s [--cap <seconds>] [--seed-root <dir>] <tree>\n' "$PROG" >&2
  exit 2
}
if [[ "$cap" =~ ^[0-9]+$ ]]; then cap=$((10#$cap)); else cap=45; fi
NPM_CI=(npm ci --ignore-scripts --no-audit --no-fund)

run_capped() {
  local limit="$1" pid ticks=0
  shift
  set -m
  "$@" &
  pid=$!
  set +m
  while kill -0 "$pid" 2>/dev/null; do
    if ((ticks >= limit * 10)); then
      kill -- -"$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

run_in() {
  # shellcheck disable=SC2016
  run_capped "$1" bash -c 'cd -- "$1" && shift && exec "$@"' _ "$2" "${NPM_CI[@]}" </dev/null >&2
}

started=$SECONDS
left() {
  local n=$((cap - (SECONDS - started)))
  ((n > 0)) || n=0
  printf '%s' "$n"
}

# Hard links, not a symlink: npm ci empties a symlinked node_modules' target
# (https://github.com/npm/cli/blob/v12.2.3/lib/commands/ci.js#L122-L129).
SEED_UNAVAILABLE=200

seed_key() {
  node -e '
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const dir = process.argv[1];
const read = (f) => { try { return fs.readFileSync(path.join(dir, f)); } catch { return null; } };
const raw = read("package.json");
if (raw) {
  const p = JSON.parse(raw), s = p.scripts || {};
  if (p.workspaces || ["preinstall", "install", "postinstall", "prepare", "prepublish"].some((k) => s[k])) process.exit(3);
  for (const d of ["dependencies", "devDependencies", "optionalDependencies"])
    for (const v of Object.values(p[d] || {})) if (/^(file|link):/.test(v)) process.exit(3);
}
const h = crypto.createHash("sha256");
h.update(process.argv.slice(2).join(" ") + "\0");
for (const f of ["package-lock.json", "package.json", ".npmrc"]) h.update(f + "\0").update(read(f) || "").update("\0");
h.update([process.versions.modules, process.platform, process.arch].join("-"));
for (const k of Object.keys(process.env).sort())
  if (k === "NODE_ENV" || /^npm_config_/i.test(k)) h.update("\0" + k + "=" + process.env[k]);
process.stdout.write(h.digest("hex"));
' "$1" "${NPM_CI[@]}"
}

prune_seeds() {
  local days="${WORKTREE_CREATE_NPM_SEED_DAYS:-14}" marker old
  [[ "$days" =~ ^[0-9]+$ ]] || days=14
  while IFS= read -r marker; do
    old=$(dirname "$marker")
    (exec 8>"$old.lock" && flock -n 8 && rm -rf -- "${old:?}" "${old:?}.lock") 2>/dev/null
  done < <(find "$seed_root" -mindepth 2 -maxdepth 2 -name .complete -mtime +"$((10#$days))" 2>/dev/null)
}

seed_install() {
  local dir="$1" key seed f rc n
  [[ -n "$seed_root" && "${WORKTREE_CREATE_NPM_SEED:-1}" != 0 ]] || return "$SEED_UNAVAILABLE"
  command -v flock >/dev/null 2>&1 && command -v node >/dev/null 2>&1 || return "$SEED_UNAVAILABLE"
  key=$(seed_key "$dir" 2>/dev/null) && [[ -n "$key" ]] || return "$SEED_UNAVAILABLE"
  seed="$seed_root/$key"
  mkdir -p "$seed_root" && exec 9>"$seed.lock" || return "$SEED_UNAVAILABLE"
  if ! flock -w "$(left)" 9; then
    exec 9>&-
    return "$SEED_UNAVAILABLE"
  fi
  if [[ ! -f "$seed/.complete" ]]; then
    n=$(left)
    if ((n == 0)); then
      exec 9>&-
      return 124
    fi
    rm -rf -- "${seed:?}" "${seed:?}.tmp"
    mkdir -p "$seed.tmp"
    for f in package.json package-lock.json npm-shrinkwrap.json .npmrc; do
      [[ -f "$dir/$f" ]] && cp -p -- "$dir/$f" "$seed.tmp/"
    done
    printf '%s: running %s into the shared seed (capped at %ss)\n' "$PROG" "${NPM_CI[*]}" "$cap" >&2
    run_in "$n" "$seed.tmp"
    rc=$?
    if ((rc != 0)); then
      rm -rf -- "${seed:?}.tmp"
      exec 9>&-
      ((rc == 124)) && return 124
      return "$SEED_UNAVAILABLE"
    fi
    [[ -d "$seed.tmp/node_modules" ]] && find "$seed.tmp/node_modules" -type f -exec chmod a-w {} + 2>/dev/null
    : >"$seed.tmp/.complete" && mv -- "$seed.tmp" "$seed"
  fi
  rc=0
  if [[ -d "$seed/node_modules" ]]; then
    rm -rf -- "${dir:?}/node_modules"
    cp -al -- "$seed/node_modules" "$dir/node_modules" 2>/dev/null || rc=$SEED_UNAVAILABLE
  fi
  touch -- "$seed/.complete"
  exec 9>&-
  ((rc == 0)) && printf '%s: linked node_modules from the shared seed %s\n' "$PROG" "$seed" >&2
  prune_seeds
  return "$rc"
}

install_one() {
  local dir="$1" rc n
  seed_install "$dir"
  rc=$?
  ((rc == SEED_UNAVAILABLE)) || return "$rc"
  n=$(left)
  ((n > 0)) || return 124
  printf '%s: running %s in %s (capped at %ss)\n' "$PROG" "${NPM_CI[*]}" "$dir" "$cap" >&2
  run_in "$n" "$dir"
}

command -v node >/dev/null 2>&1 || {
  printf '%s: warning: node is not on PATH, so the ecosystem records were not read and nothing was provisioned\n' "$PROG" >&2
  exit 1
}
plan="$(node "$HERE/provision-prerequisites.mjs" list "$tree")" || exit 1
[[ -n "$plan" ]] || exit 0

status=0
while IFS=$'\t' read -r rel names lockfile; do
  dir="$tree/$rel"
  [[ "$rel" == "." ]] && dir="$tree"
  remedy="run ${NPM_CI[*]} in $dir"
  if ! command -v npm >/dev/null 2>&1; then
    printf '%s: warning: npm is not on PATH; %s (%s) not provisioned. To provide it, %s\n' "$PROG" "$names" "$lockfile" "$remedy" >&2
    status=1
    continue
  fi
  install_one "$dir"
  rc=$?
  if ((rc == 124)); then
    printf '%s: warning: npm ci did not finish within %ss and was stopped; %s (%s) may be partial. To provide it, %s\n' \
      "$PROG" "$cap" "$names" "$lockfile" "$remedy" >&2
    status=1
  elif ((rc != 0)); then
    printf '%s: warning: npm ci failed (exit %d); %s (%s) not provisioned. To provide it, %s\n' \
      "$PROG" "$rc" "$names" "$lockfile" "$remedy" >&2
    status=1
  fi
done <<<"$plan"
exit "$status"
