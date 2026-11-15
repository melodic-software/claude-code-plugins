#!/usr/bin/env bash
# main has a CI check script that fails when a plugin changes with no CHANGELOG.md change. The
# branch makes the check stricter, as the issue asks: the CHANGELOG.md must also hold a dated
# heading. A stricter check is not a loosening.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p scripts plugins/mail review-input

cat >scripts/check-changelog.mjs <<'JS'
// Fails when a changed plugin has no CHANGELOG.md change in the same diff.
// Usage: node scripts/check-changelog.mjs <changed path>...
const changed = process.argv.slice(2);
const missing = new Set();
for (const file of changed) {
  const match = file.match(/^plugins\/([^/]+)\//);
  if (!match) continue;
  if (!changed.includes(`plugins/${match[1]}/CHANGELOG.md`)) missing.add(match[1]);
}
for (const name of missing) console.error(`plugins/${name}: changed with no CHANGELOG.md entry`);
process.exit(missing.size ? 1 : 0);
JS

cat >plugins/mail/CHANGELOG.md <<'MD'
# Changelog

## 1.0.0 - 2026-09-01

- First release.
MD

git add .
git commit -q -m "feat: changelog check"

git checkout -q -b ci/74-dated-changelog-heading
cat >scripts/check-changelog.mjs <<'JS'
// Fails when a changed plugin has no CHANGELOG.md change in the same diff, or when
// that CHANGELOG.md has no dated "## <version> - <YYYY-MM-DD>" heading.
// Usage: node scripts/check-changelog.mjs <changed path>...
import { readFileSync } from "node:fs";

const DATED_HEADING = /^## \S+ - \d{4}-\d{2}-\d{2}$/m;
const changed = process.argv.slice(2);
const missing = new Set();
const undated = new Set();
for (const file of changed) {
  const match = file.match(/^plugins\/([^/]+)\//);
  if (!match) continue;
  const changelog = `plugins/${match[1]}/CHANGELOG.md`;
  if (!changed.includes(changelog)) missing.add(match[1]);
  else if (!DATED_HEADING.test(readFileSync(changelog, "utf8"))) undated.add(match[1]);
}
for (const name of missing) console.error(`plugins/${name}: changed with no CHANGELOG.md entry`);
for (const name of undated) console.error(`plugins/${name}: CHANGELOG.md has no dated heading`);
process.exit(missing.size || undated.size ? 1 : 0);
JS

git add .
git commit -q -m "ci: require a dated CHANGELOG heading"

git diff main...HEAD >review-input/change.diff

cat >review-input/issue.md <<'MD'
# #74 Require a dated CHANGELOG heading

Make `scripts/check-changelog.mjs` also fail when a changed plugin's `CHANGELOG.md` has no
`## <version> - <YYYY-MM-DD>` heading, so every release note carries its date.

## Done when

- [ ] A changed plugin whose CHANGELOG.md has no dated heading fails the check with a message
      naming the plugin.
MD

cat >review-input/pr-body.md <<'MD'
The changelog check now also requires a dated heading, as #74 asks.

Closes #74
MD

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/spec-author.sh" 74 4101 counts
