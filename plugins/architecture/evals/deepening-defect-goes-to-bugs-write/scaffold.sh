#!/usr/bin/env bash
# A parcel-quote path of three one-step classes. The fuel surcharge is added in both
# QuoteService.quote and RateTable.price, so a 2 kg zone B parcel is quoted 7.50 against the
# published 6.75, and the committed test states 6.75. LabelPrinter is imported by nothing.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git parcels labels tests
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p parcels labels tests
: >parcels/__init__.py
: >labels/__init__.py
: >tests/__init__.py

cat >parcels/rates.py <<'PY'
FUEL_SURCHARGE = 0.75
PER_KG = {"A": 2.50, "B": 3.00, "C": 4.25}
PY

cat >parcels/zones.py <<'PY'
class ZoneLookup:
    def zone_for(self, postcode):
        return postcode[0].upper()
PY

cat >parcels/rate_table.py <<'PY'
from parcels.rates import FUEL_SURCHARGE, PER_KG


class RateTable:
    def price(self, zone, weight_kg):
        return round(weight_kg * PER_KG[zone] + FUEL_SURCHARGE, 2)
PY

cat >parcels/quote_service.py <<'PY'
from parcels.rate_table import RateTable
from parcels.rates import FUEL_SURCHARGE
from parcels.zones import ZoneLookup


class QuoteService:
    def __init__(self, zones=None, rates=None):
        self.zones = zones or ZoneLookup()
        self.rates = rates or RateTable()

    def quote(self, parcel):
        zone = self.zones.zone_for(parcel["postcode"])
        return round(self.rates.price(zone, parcel["weight_kg"]) + FUEL_SURCHARGE, 2)
PY

cat >labels/label_printer.py <<'PY'
class LabelPrinter:
    def render(self, parcel):
        return f"{parcel['postcode']} / {parcel['weight_kg']} kg"
PY

cat >tests/test_quote.py <<'PY'
import unittest

from parcels.quote_service import QuoteService


class QuoteTest(unittest.TestCase):
    def test_zone_b_two_kilos_matches_published_rate(self):
        # Published rate card: 3.00 per kg in zone B plus a 0.75 fuel surcharge.
        self.assertEqual(QuoteService().quote({"postcode": "B12 4QT", "weight_kg": 2}), 6.75)


if __name__ == "__main__":
    unittest.main()
PY

git add parcels labels tests
git commit -q -m "feat: parcel quotes"
