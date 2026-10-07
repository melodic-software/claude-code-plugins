#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/acr-seed.sh" \
  acr-deploy.sh=scripts/deploy.sh \
  acr-gen_client.py=scripts/gen_client.py \
  acr-NOTES.md=scripts/NOTES.md
