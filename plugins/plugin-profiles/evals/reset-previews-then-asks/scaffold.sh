#!/usr/bin/env bash
set -euo pipefail
here="$(pwd -P)"
home="$(cd "${HOME:-/nonexistent}" 2>/dev/null && pwd -P || true)"
run="$(dirname "${home:-/}")"
if [[ -z "${home}" || "$(basename "${home}")" != home || "$(basename "${run}")" != claude-eval-* || -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  echo "refusing to scaffold: HOME (${HOME:-unset}) is not a claude plugin eval run's temporary home" >&2
  exit 3
fi
case "${here}" in
  / | "${home}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
  *) ;;
esac

mkdir -p .git .claude
printf 'ref: refs/heads/main\n' >.git/HEAD
printf '{\n  "enabledPlugins": {\n    "songwriting@melodic-software": false\n  }\n}\n' >.claude/settings.local.json
node - "${here}" "${home}/.claude" <<'EOF'
const { createHash } = require("node:crypto");
const { mkdirSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");
const [folder, config] = process.argv.slice(2);
const sha = (text) => createHash("sha256").update(text).digest("hex");
const settingsFile = join(folder, ".claude", "settings.local.json");
const home = join(folder, ".git", "plugin-profiles");
const record = {
  schema: 1, profile: "build", target: "folder", settingsFile, appliedAt: "2026-11-01T00:00:00.000Z", pluginVersion: "0.6.1",
  phase: "applied", pending: {}, createdFile: false, createdFolder: false, containers: { enabledPlugins: true, skillOverrides: false },
  installed: [], entries: { "songwriting@melodic-software": { before: true, after: false } }, skillOverrides: {},
};
mkdirSync(join(home, "records"), { recursive: true });
writeFileSync(join(home, "records", `${sha(settingsFile)}.json`), `${JSON.stringify(record, null, 2)}\n`);
const pointers = join(config, "plugin-profiles-state", "repositories");
mkdirSync(pointers, { recursive: true });
writeFileSync(join(pointers, `${sha(home)}.json`), `${JSON.stringify({ home }, null, 2)}\n`);
EOF
