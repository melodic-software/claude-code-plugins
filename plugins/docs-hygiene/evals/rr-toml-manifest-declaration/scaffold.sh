#!/usr/bin/env bash
set -euo pipefail

mkdir -p packages/ledger-bridge/src/ledger_bridge
cat >packages/ledger-bridge/pyproject.toml <<'TOML'
[project]
name = "ledger-sync"
version = "0.3.0"
description = "Copies settled bank ledger entries into the warehouse."
requires-python = ">=3.11"
TOML
cat >packages/ledger-bridge/README.md <<'MD'
# ledger-bridge

Copies settled bank ledger entries into the warehouse every night.
MD
printf '' >packages/ledger-bridge/src/ledger_bridge/__init__.py
cat >README.md <<'MD'
# Harbor

Services that move finance data between systems.

| Package | Path |
|---|---|
| ledger-bridge | `packages/ledger-bridge` |
MD
