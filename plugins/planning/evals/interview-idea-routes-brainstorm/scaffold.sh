#!/usr/bin/env bash
# Seeds a small neighborhood app with listings and no swap feature, so the idea has a codebase to
# land in but no settled problem or direction.
set -euo pipefail

mkdir -p src/listings
cat >src/listings/listing.py <<'PY'
from dataclasses import dataclass


@dataclass
class Listing:
    owner: str
    title: str
    neighborhood: str
PY
cat >README.md <<'MD'
# Neighborly

Neighbors post items to lend or give away within their neighborhood.
MD
