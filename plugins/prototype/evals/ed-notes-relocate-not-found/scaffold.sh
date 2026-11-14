#!/usr/bin/env bash
# A /shipments mockup in a private run directory, mockup-run/, and one note the person pinned from
# the notes host before the mockup was reworked. The note is on variant B's Export button, which
# the rework removed: no element carries its test id and its path finds nothing, so the session
# must report it not found, give only its stored position, ask, and edit nothing. Needs no live
# notes host: `notes-bridge.sh status` reads actions.json with no server. The note is synthetic.
set -euo pipefail

mkdir -m 700 mockup-run
cat >mockup-run/explore-directions.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'">
<title>/shipments variants</title>
</head>
<body>
<main>
  <section data-variant="A" data-variant-label="Ledger">
    <table data-testid="shipments-parcel-table"><tr><th>Parcel</th><th>Expected</th></tr>
      <tr data-testid="shipments-parcel-row"><td>PT-1001</td><td>Nov 3</td></tr></table>
  </section>
  <section data-variant="B" data-variant-label="Cards">
    <div class="toolbar">
      <button type="button" data-testid="shipments-filter">Filter</button>
    </div>
    <div class="cards">
      <article data-testid="shipments-parcel-card"><strong>Nov 3</strong> · PT-1001 · In transit</article>
      <article data-testid="shipments-parcel-card"><strong>Nov 5</strong> · PT-1002 · Delayed</article>
    </div>
  </section>
</main>
</body>
</html>
HTML
cat >mockup-run/actions.json <<'JSON'
{
  "seq": 1,
  "events": [
    {
      "seq": 1,
      "at": "2026-11-12T15:04:05Z",
      "kind": "element",
      "variant": {"key": "B"},
      "anchor": {"testid": "shipments-export", "testidIndex": 0, "tag": "button", "cssPath": "div:nth-of-type(1) > button:nth-of-type(2)"},
      "rect": {"x": 71.5, "y": 6.25, "w": 9, "h": 3.5},
      "text": "Make this button the primary color so it stands out."
    }
  ]
}
JSON
chmod 600 mockup-run/actions.json
