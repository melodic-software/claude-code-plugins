#!/usr/bin/env bash
# Seed a two-plugin marketplace where one plugin's skill path-cites the other's script, and CI calls the same script.
set -euo pipefail

mkdir -p .claude-plugin .github/workflows \
  plugins/lint-kit/.claude-plugin plugins/lint-kit/skills/check/scripts \
  plugins/release-kit/.claude-plugin plugins/release-kit/skills/ship

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-tools",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "lint-kit", "source": "./plugins/lint-kit" },
    { "name": "release-kit", "source": "./plugins/release-kit" }
  ]
}
JSON

printf '{ "name": "lint-kit", "version": "1.3.0" }\n' >plugins/lint-kit/.claude-plugin/plugin.json
printf '{ "name": "release-kit", "version": "0.9.2" }\n' >plugins/release-kit/.claude-plugin/plugin.json

cat >plugins/lint-kit/skills/check/SKILL.md <<'MD'
---
name: check
description: Run the repository's lint and format checks. Use before committing or releasing.
---

# Check

Run `scripts/run-checks.sh`; pass `--strict` to treat warnings as failures.
MD

cat >plugins/lint-kit/skills/check/scripts/run-checks.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "checks passed"
SH
chmod +x plugins/lint-kit/skills/check/scripts/run-checks.sh

cat >plugins/release-kit/skills/ship/SKILL.md <<'MD'
---
name: ship
description: Cut a release of the current repository. Use when the user asks to ship or tag a release.
---

# Ship

1. Run `plugins/lint-kit/skills/check/scripts/run-checks.sh --strict` and stop on any failure.
2. Bump the version in the manifest.
3. Tag the commit and push the tag.
MD

cat >plugins/release-kit/README.md <<'MD'
# release-kit

Cuts releases. Install with `claude plugin install release-kit@acme-tools`.
MD

cat >.github/workflows/ci.yml <<'YML'
name: ci
on: [pull_request]
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash plugins/lint-kit/skills/check/scripts/run-checks.sh --strict
YML

cat >README.md <<'MD'
# acme-tools

A marketplace of two plugins:

- `claude plugin install lint-kit@acme-tools`
- `claude plugin install release-kit@acme-tools`
MD
