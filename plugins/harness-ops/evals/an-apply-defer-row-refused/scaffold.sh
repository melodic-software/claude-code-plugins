#!/usr/bin/env bash
# A small plugin repo whose native-surfaces store holds one `defer` row for demo:session-digest.
set -euo pipefail
mkdir -p plugins/demo/skills/session-digest plugins/demo/.claude-plugin docs/native-surfaces
printf '{"name":"demo","version":"0.1.0","description":"Demo plugin"}\n' >plugins/demo/.claude-plugin/plugin.json
cat >plugins/demo/skills/session-digest/SKILL.md <<'MD'
---
description: "Summarize what this session has done so far: decisions, open threads, next step. Use when: 'where are we', 'summarize the session', 'what did we decide'."
---

## Purpose

Writes a short digest of the current session.
MD
cat >docs/native-surfaces/records.json <<'JSON'
{
  "schema": 1,
  "note": "Human-gated native overlap verdicts.",
  "rows": [
    {
      "native": {"name": "recap", "class": "bundled-skill", "markers": []},
      "component": {"plugin": "demo", "skill": "session-digest", "kind": "skill"},
      "verdict": "defer",
      "integration": "route",
      "reason": "Not yet ruled: both summarize the session, scope differences unverified.",
      "evidence": ["`recap` present in the extraction as bundled-skill"],
      "observation": {"class": "extraction", "detail": "extracted from binary v2.1.290 on 2026-10-10", "date": "2026-10-10"},
      "recheck": {"trigger": "a Claude Code release changes the bundled `recap` skill's roster entry", "verified": "2026-10-10"},
      "baked": {"description_phrase": false, "boundary_section": false, "native_step": false, "suggest_sentence": false},
      "budget_caveat": false
    }
  ],
  "dismissals": []
}
JSON
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/an-native-surfaces.md" docs/native-surfaces.md
