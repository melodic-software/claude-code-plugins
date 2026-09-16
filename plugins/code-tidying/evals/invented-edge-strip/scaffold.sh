#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" scripts/restoration-markers.txt scripts/check-markers.sh src/edge-marker.sh src/edge_docstring.py src/edge-paired.sh tests/edge-paired.test.sh
