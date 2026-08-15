# Vendored `tzdata`

First-party IANA time zone database package used by `check-usage-limit-reset.py`
so `zoneinfo` can resolve IANA names on platforms without a system TZDB
(notably Windows).

- Package: [`tzdata`](https://pypi.org/project/tzdata/) 2026.3
- Artifact: `tzdata-zoneinfo.zip` (binary zip of the install layout:
  `tzdata/` + `tzdata-2026.3.dist-info/`)
- License: Apache-2.0 (see `tzdata-2026.3.dist-info/licenses/` inside the zip)
- Upstream: https://github.com/python/tzdata

Kept as a zip so hygiene/typos does not scan zone tab text (ISO country codes
and place names). At runtime the script extracts the zip once into a tempfile
cache keyed by the zip content hash, then imports `tzdata` from that cache.

Do not edit the zip by hand. Refresh by installing the pinned wheel into a
scratch directory (`pip install tzdata==<version> --target …`), zipping the
resulting `tzdata/` and `tzdata-*.dist-info/` trees as `tzdata-zoneinfo.zip`,
and updating the pin noted here and in the session-flow CHANGELOG.
