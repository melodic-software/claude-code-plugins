#!/usr/bin/env bash
# Seeds a repository where "Account" already names a sign-in identity, in the code and the glossary.
set -euo pipefail

mkdir -p src/auth src/billing docs
cat >src/auth/account.ts <<'TS'
// An Account is one person's sign-in identity: email, password hash, MFA state.
export interface Account {
  id: string;
  email: string;
  passwordHash: string;
  mfaEnabled: boolean;
}
TS
cat >src/billing/invoice.ts <<'TS'
export interface Invoice {
  id: string;
  accountId: string;
  amountCents: number;
}
TS
cat >docs/glossary.md <<'MD'
# Glossary

- **Account**: one person's sign-in identity (email, password, MFA). Never shared between people.
- **Member**: a person enrolled in the gym, linked to exactly one Account.
MD
cat >AGENTS.md <<'MD'
# gym-portal

Domain vocabulary lives in docs/glossary.md.
MD
