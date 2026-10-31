#!/usr/bin/env bash
# Seeds a finished explore-directions mockup and the project's decision-record convention.
set -euo pipefail
mkdir -p docs/decisions mockup-run
cat > docs/decisions/README.md <<'MD'
# Decisions

UI decisions: one file per screen, `docs/decisions/ui-<screen>.md` (for `/shipments`,
`docs/decisions/ui-shipments.md`).
MD
cat > mockup-run/explore-directions.html <<'HTML'
<!doctype html>
<html><head><title>/shipments variants</title></head><body>
<section data-variant="A" data-variant-label="Ledger">
  <table data-testid="shipments-parcel-table"><tr><th>Parcel</th><th>Status</th></tr></table>
  <button data-testid="shipments-export">Export</button>
</section>
<section data-variant="B" data-variant-label="Cards">
  <article data-testid="shipments-parcel-card"><h3>Arrives Tue 14 May</h3><p>In transit</p></article>
  <p data-testid="shipments-empty">No parcels in transit. <a>Track a parcel</a></p>
</section>
<section data-variant="C" data-variant-label="Map">
  <div class="map"></div>
  <select data-testid="shipments-region-filter"><option>All regions</option></select>
</section>
</body></html>
HTML
