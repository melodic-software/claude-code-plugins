# TypeScript/JavaScript security checklist

Loaded on demand by this plugin's `security-reviewer` agent when the change set touches TypeScript
or JavaScript code. The OWASP table and the cross-ecosystem list in the agent body are the floor
for every review; these are the ecosystem-specific additions that floor does not cover.

- **XSS**: `innerHTML`, `dangerouslySetInnerHTML`, unescaped template literals in the DOM
- **Prototype pollution**: merges/spreads of untrusted input
- **Input validation**: external inputs (HTTP, MCP tool parameters) validated with schemas at the entry point
