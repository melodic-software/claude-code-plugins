#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../revert-cases.sh" scaffold revert-12162-dometrain-sync-body
