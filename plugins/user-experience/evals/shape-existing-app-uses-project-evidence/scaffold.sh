#!/usr/bin/env bash
# A shipping app with onboarding interview notes and an analytics SDK.
set -euo pipefail
here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
mkdir -p research src
cat >package.json <<'JSON'
{ "name": "plankit", "private": true, "dependencies": { "react": "^19.0.0", "mixpanel-browser": "^2.55.0" } }
JSON
printf 'export default function App() {\n  return null; // team task planner: boards, due dates, invites\n}\n' >src/App.tsx
cat >research/onboarding-interviews.md <<'MD'
# Onboarding interviews (sessions I1 to I5)

- I1: team lead; skipped the product tour and could not find where to import tasks from a spreadsheet.
- I2: team lead; wanted to invite two teammates before setting anything up, and the invite step comes last.
- I3: new member; landed on an empty board with no hint of what to do first.
- I4: team lead; stopped at the calendar permission prompt because it did not say why it was needed.
- I5: new member; liked starting from a template board instead of a blank one.
MD
