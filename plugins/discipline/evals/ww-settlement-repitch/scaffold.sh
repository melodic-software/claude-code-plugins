#!/usr/bin/env bash
# Seed a project glossary the re-pitch should draw its terms from.
set -euo pipefail

mkdir -p docs
cat >CLAUDE.md <<'MD'
# payments-core

docs/glossary.md is the domain glossary. Use its terms in code, docs and replies.
MD
cat >docs/glossary.md <<'MD'
# Glossary

- **Settlement batch**: the group of captured payments that the payment service provider (PSP)
  pays out to us in one bank transfer. Do not call it a "payout run".
- **Capture**: the moment an authorized card payment becomes money owed to us.
- **Cutoff**: the last time of day at which a capture can join today's settlement batch.
- **T+2**: the funds arrive two business days after the settlement batch closes.
MD
