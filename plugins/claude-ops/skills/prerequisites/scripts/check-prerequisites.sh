#!/usr/bin/env bash
# Read-only fleet prerequisite table. Never installs.
#
#   check-prerequisites.sh --plugin-root <dir> [--plugin-root <dir>...]
#   check-prerequisites.sh
#
# With no roots, read enabled plugins from ~/.claude (or $CLAUDE_CONFIG_DIR)
# and each install's prerequisites.json. When that state is absent and this
# repo has plugins/*/prerequisites.json, scan those instead.
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

if [[ ${#ROOTS[@]} -eq 0 ]]; then
  config="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  mapfile -t ROOTS < <(python3 - "$config" <<'PY'
import json, os, sys
config = sys.argv[1]
enabled = set()
for name in ("settings.json", "settings.local.json"):
    path = os.path.join(config, name)
    if not os.path.isfile(path):
        continue
    try:
        doc = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue
    for key, value in (doc.get("enabledPlugins") or {}).items():
        if value:
            enabled.add(key)
installed = os.path.join(config, "plugins", "installed_plugins.json")
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
fi

if [[ ${#ROOTS[@]} -eq 0 ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  repo="${repo%$'\r'}"
  if [[ -n "$repo" && -d "$repo/plugins" ]]; then
    while IFS= read -r decl; do
      ROOTS+=("$(dirname "$decl")")
    done < <(find "$repo/plugins" -mindepth 2 -maxdepth 2 -name prerequisites.json | sort)
  fi
fi

if [[ ${#ROOTS[@]} -eq 0 ]]; then
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
