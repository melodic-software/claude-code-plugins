#!/usr/bin/env bash
# Seeds the eval workspace with a team file that confirms Pencil and keeps Figma deferred for
# design-tool-handoff, and a small settings screen for the designer to receive.
set -euo pipefail

mkdir -p docs/conventions src/settings
cat > docs/conventions/user-interface.yaml <<'YAML'
routing:
  version: 1
  rows:
    - concern: design-tool-handoff
      id: pencil
      status: confirmed
      as_of: 2026-10-29
    - concern: design-tool-handoff
      id: figma@claude-plugins-official
      status: deferred
      as_of: 2026-11-06
YAML
cat > package.json <<'JSON'
{ "name": "ledgerly", "private": true, "dependencies": { "react": "^19.0.0" } }
JSON
cat > src/settings/SettingsScreen.jsx <<'JSX'
export function SettingsScreen({ user }) {
  return (
    <main style={{ maxWidth: 640, margin: "0 auto", padding: 24, fontFamily: "Inter, sans-serif" }}>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Settings</h1>
      <section style={{ borderBottom: "1px solid #E5E7EB", paddingBottom: 16 }}>
        <h2 style={{ fontSize: 16 }}>Profile</h2>
        <label>Name <input defaultValue={user.name} /></label>
        <label>Email <input type="email" defaultValue={user.email} /></label>
      </section>
      <section style={{ borderBottom: "1px solid #E5E7EB", padding: "16px 0" }}>
        <h2 style={{ fontSize: 16 }}>Notifications</h2>
        <label><input type="checkbox" defaultChecked /> Weekly summary email</label>
        <label><input type="checkbox" /> Invoice reminders</label>
      </section>
      <section style={{ paddingTop: 16 }}>
        <h2 style={{ fontSize: 16, color: "#B91C1C" }}>Danger zone</h2>
        <button style={{ background: "#B91C1C", color: "#fff", padding: "8px 16px", borderRadius: 6 }}>Delete account</button>
      </section>
    </main>
  );
}
JSX
