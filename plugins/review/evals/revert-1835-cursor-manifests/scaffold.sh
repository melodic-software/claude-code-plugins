#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../revert-cases.sh" scaffold revert-1835-cursor-manifests
