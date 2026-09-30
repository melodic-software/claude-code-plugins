#!/usr/bin/env bash
# Read-only fleet prerequisite table. Never installs.
#
#   check-prerequisites.sh --plugin-root <dir> [--plugin-root <dir>...]
#   check-prerequisites.sh
#
# With no roots and a claude executable on PATH, read the enabled set and each
# install path from `claude plugin list --json`: user and managed rows, plus
# project and local rows whose projectPath is the current project
# ($CLAUDE_PROJECT_DIR, else the git toplevel); the most specific scope wins per
# id. When claude is absent or prints nothing, merge enabledPlugins
# from settings.json and settings.local.json in ~/.claude (or $CLAUDE_CONFIG_DIR)
# and the project's .claude directory instead, skipping a whole file whose
# enabledPlugins holds a non-Boolean value (Claude Code ignores that file's
# keys); that fallback does not read the managed scope. Output that is not a
# JSON list is an error (exit 2), never a fallback. Only when none of that
# state exists and this repo has plugins/*/prerequisites.json, scan those.
#
# Prints one TSV header and one row per declared tool:
#   tool plugin status check install
# Then `missing=N present=M`. Exit 0 when every tool is present, 1 when any
# is missing, 2 on a usage error.
set -uo pipefail

ROOTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --plugin-root)
    [[ $# -ge 2 ]] || { echo "check-prerequisites.sh: --plugin-root needs a directory" >&2; exit 2; }
    ROOTS+=("$2")
    shift 2
    ;;
  --help | -h)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "check-prerequisites.sh: unknown argument $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "check-prerequisites.sh: python3 is required to read the plugin listing and declarations" >&2
  exit 2
}

STATE_READ=0
if [[ ${#ROOTS[@]} -eq 0 ]]; then
  config="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  project="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  project="${project%$'\r'}"
  listing_file="$(mktemp)"
  found_file="$(mktemp)"
  trap 'rm -f "$listing_file" "$found_file"' EXIT
  if command -v claude >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      timeout 30 claude plugin list --json >"$listing_file" 2>/dev/null || true
    else
      claude plugin list --json >"$listing_file" 2>/dev/null || true
    fi
  fi
  if ! python3 - "$config" "$project" "$listing_file" >"$found_file" <<'PY'
import json, os, sys
config, project, listing_path = sys.argv[1], sys.argv[2], sys.argv[3]
RANK = {"user": 0, "project": 1, "local": 2, "managed": 3}

def same_dir(a, b):
    return bool(a and b) and os.path.realpath(a) == os.path.realpath(b)

def from_cli(rows):
    best = {}
    for row in rows:
        if not isinstance(row, dict) or not row.get("id"):
            continue
        scope = row.get("scope")
        if scope not in RANK:
            continue
        if scope in ("project", "local") and not same_dir(row.get("projectPath") or "", project):
            continue
        key = row["id"]
        if key not in best or RANK[scope] >= RANK[best[key]["scope"]]:
            best[key] = row
    return [row["installPath"] for _, row in sorted(best.items())
            if row.get("enabled") is True and row.get("installPath")]

def from_settings():
    # User, then project, then local: a later scope's true/false wins.
    scopes = [os.path.join(config, "settings.json"), os.path.join(config, "settings.local.json")]
    if project:
        scopes += [os.path.join(project, ".claude", "settings.json"),
                   os.path.join(project, ".claude", "settings.local.json")]
    state = {}
    read = False
    for path in scopes:
        if not os.path.isfile(path):
            continue
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        read = True
        plugins = doc.get("enabledPlugins") if isinstance(doc, dict) else None
        if not isinstance(plugins, dict) or not all(isinstance(v, bool) for v in plugins.values()):
            continue
        state.update(plugins)
    enabled = {key for key, value in state.items() if value}
    installed = os.path.join(config, "plugins", "installed_plugins.json")
    if os.path.isfile(installed):
        read = True
    found = []
    if enabled and os.path.isfile(installed):
        try:
            doc = json.load(open(installed, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            doc = {}
        plugins = doc.get("plugins") or {}
        for key in sorted(enabled):
            records = plugins.get(key) or []
            if isinstance(records, dict):
                records = [records]
            path = ""
            for record in records:
                if isinstance(record, dict) and record.get("installPath"):
                    path = record["installPath"]
                    if record.get("scope") == "user":
                        break
            if path:
                found.append(path)
    return read, found

with open(listing_path, encoding="utf-8") as handle:
    text = handle.read()
if text.strip():
    try:
        rows = json.loads(text)
        detail = "not a JSON list"
    except json.JSONDecodeError as exc:
        rows, detail = None, exc
    if not isinstance(rows, list):
        print(f"check-prerequisites.sh: claude plugin list --json: {detail}", file=sys.stderr)
        sys.exit(2)
    read, found = True, from_cli(rows)
else:
    read, found = from_settings()
if read:
    print("STATE_READ")
if found:
    print("\n".join(found))
PY
  then
    echo "check-prerequisites.sh: could not read the plugin listing" >&2
    exit 2
  fi
  mapfile -t found <"$found_file"
  for line in "${found[@]}"; do
    if [[ "$line" == "STATE_READ" ]]; then STATE_READ=1; else ROOTS+=("$line"); fi
  done
fi

# The repository scan stands in only when no settings or install state exists;
# a read state with nothing enabled is an empty fleet, not a reason to scan.
if [[ ${#ROOTS[@]} -eq 0 && "$STATE_READ" -eq 0 ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  repo="${repo%$'\r'}"
  if [[ -n "$repo" && -d "$repo/plugins" ]]; then
    while IFS= read -r decl; do
      ROOTS+=("$(dirname "$decl")")
    done < <(find "$repo/plugins" -mindepth 2 -maxdepth 2 -name prerequisites.json | sort)
  fi
fi

if [[ ${#ROOTS[@]} -eq 0 && "$STATE_READ" -eq 0 ]]; then
  echo "check-prerequisites.sh: no plugin roots to read" >&2
  exit 2
fi

export PREREQ_ROOTS
PREREQ_ROOTS="$(printf '%s\n' "${ROOTS[@]}")"
python3 - <<'PY'
import json, os, shutil, sys

roots = [line for line in os.environ["PREREQ_ROOTS"].splitlines() if line]
rows = []

def present(name, local_bin):
    if shutil.which(name):
        return True
    if not local_bin:
        return False
    directory = os.getcwd()
    for _ in range(8):
        candidate = os.path.join(directory, local_bin)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return True
        parent = os.path.dirname(directory)
        if parent == directory:
            break
        directory = parent
    return False

for root in roots:
    manifest = os.path.join(root, ".claude-plugin", "plugin.json")
    plugin = os.path.basename(root.rstrip("/"))
    if os.path.isfile(manifest):
        try:
            plugin = json.load(open(manifest, encoding="utf-8")).get("name") or plugin
        except (OSError, json.JSONDecodeError):
            pass
    decl_path = os.path.join(root, "prerequisites.json")
    if not os.path.isfile(decl_path):
        continue
    try:
        declared = json.load(open(decl_path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"check-prerequisites.sh: {decl_path}: {exc}", file=sys.stderr)
        sys.exit(2)
    for tool in declared.get("tools") or []:
        name = str(tool.get("name") or "")
        if not name:
            continue
        status = "present" if present(name, tool.get("local_bin") or "") else "missing"
        rows.append((name, plugin, status, tool.get("check") or "", tool.get("install") or ""))

def cell(value):
    return str(value).replace("\t", " ").replace("\n", " ")

print("tool\tplugin\tstatus\tcheck\tinstall")
missing = 0
for row in rows:
    if row[2] == "missing":
        missing += 1
    print("\t".join(cell(part) for part in row))
present_count = len(rows) - missing
print(f"missing={missing} present={present_count}")
sys.exit(1 if missing else 0)
PY
