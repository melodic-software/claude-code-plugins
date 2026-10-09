#!/usr/bin/env bash
# Seeds the eval workspace with a small app whose colors are hard-coded in each component.
set -euo pipefail

mkdir -p src/components
cat > package.json <<'JSON'
{ "name": "fieldnotes", "private": true, "dependencies": { "react": "^19.0.0" } }
JSON
cat > src/components/Toast.jsx <<'JSX'
export const Toast = ({ text }) => <div style={{ background: "#2E7D32", color: "#fff", padding: 12, borderRadius: 6 }}>{text}</div>;
JSX
cat > src/components/Badge.jsx <<'JSX'
export const Badge = ({ text }) => <span style={{ background: "#C62828", color: "#fff", padding: "2px 8px", borderRadius: 10 }}>{text}</span>;
JSX
cat > src/components/Card.jsx <<'JSX'
export const Card = ({ children }) => <div style={{ border: "1px solid #DDD", padding: 16, borderRadius: 4 }}>{children}</div>;
JSX
