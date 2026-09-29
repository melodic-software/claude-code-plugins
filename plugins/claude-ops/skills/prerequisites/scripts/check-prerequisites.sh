#!/usr/bin/env bash
# Read-only fleet prerequisite table. Never installs.
#
#   check-prerequisites.sh --plugin-root <dir> [--plugin-root <dir>...]
#   check-prerequisites.sh
#
# With no roots, merge enabledPlugins from the user settings in ~/.claude (or
# $CLAUDE_CONFIG_DIR) and the project's .claude/settings.json and
# settings.local.json ($CLAUDE_PROJECT_DIR, else the git toplevel), then read
# each enabled install's prerequisites.json. Only when none of that state
# exists and this repo has plugins/*/prerequisites.json, scan those instead.
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
    sed -n '2,16p' "${BASH_SOURCE[0]}" >&2
    exit 0
    ;;
  *)
    echo "check-prerequisites.sh: unknown argument $1" >&2
    exit 2
    ;;
  esac
done

STATE_READ=0
if [[ ${#ROOTS[@]} -eq 0 ]]; then
  config="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  project="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  project="${project%$'\r'}"
  mapfile -t found < <(python3 - "$config" "$project" <<'PY'
import json, os, sys
config, project = sys.argv[1], sys.argv[2]
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
    for key, value in (doc.get("enabledPlugins") or {}).items():
        state[key] = bool(value)
enabled = {key for key, value in state.items() if value}
installed = os.path.join(config, "plugins", "installed_plugins.json")
if os.path.isfile(installed):
    read = True
if read:
    print("STATE_READ")
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
if found:
    print("\n".join(found))
PY
)
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
