#!/usr/bin/env bash
# Seeds an app whose team UX file is malformed (an unclosed flow sequence), so it cannot be applied.
set -euo pipefail

mkdir -p docs/conventions research src
cat > package.json <<'JSON'
{ "name": "fernway", "private": true, "dependencies": { "react": "^19.0.0" } }
JSON
cat > src/App.tsx <<'TSX'
export default function App() {
  return null; // trip journal: add a stop, attach photos, share the trip
}
TSX
cat > research/onboarding-notes.md <<'MD'
# Onboarding notes (support inbox, last month)

- O1: several people asked how to add a trip they already took.
- O2: photo import fails silently when the library is large.
- O3: people expect to share a trip before finishing it.
MD
cat > docs/conventions/user-experience.yaml <<'YAML'
version: 1
routing:
  version: 1
  rows: []
  disable: []
  deny: [whiteboard-tool
jtbd_school: outcome-driven-innovation
research_paths:
  - research/
YAML
