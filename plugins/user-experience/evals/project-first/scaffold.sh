#!/usr/bin/env bash
# Seeds a trucking app that holds its own interview synthesis and two personas.
set -euo pipefail

mkdir -p research personas src
cat > package.json <<'JSON'
{ "name": "haulwise", "private": true, "dependencies": { "expo": "^52.0.0", "react-native": "^0.76.0" } }
JSON
cat > src/App.tsx <<'TSX'
export default function App() {
  return null; // load board, driver check-in, detention log
}
TSX
cat > research/2026-q2-interview-synthesis.md <<'MD'
# Interview synthesis, Q2 (8 sessions, P1 to P8)

Evidence: evidence-based. Dispatchers P1 to P4, owner-operator drivers P5 to P8.

## Themes
1. Dispatchers re-enter load details from broker emails by hand (P1, P2, P3, P4).
2. Drivers miss detention pay because they cannot prove when they arrived (P5, P6, P8).
3. Night-shift dispatchers cannot tell which drivers are off duty, so calls wake drivers (P2, P4, P7).

## Open questions
- Would drivers accept location sharing only while on a load? No evidence yet.
MD
cat > personas/night-shift-dispatcher.md <<'MD'
# Persona: night-shift dispatcher

Built from P2 and P4. Runs 10 to 25 loads a night for a small fleet.
Needs: load details without retyping; to know who is off duty before calling.
MD
cat > personas/owner-operator.md <<'MD'
# Persona: owner-operator driver

Built from P5, P6 and P8. Drives their own truck under contract.
Needs: proof of arrival time for detention pay; fewer calls while off duty.
MD
