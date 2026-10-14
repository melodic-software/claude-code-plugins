#!/usr/bin/env bash
# Seed two modules on an established Result error model and one new module that throws instead.
set -euo pipefail

mkdir -p src/lib notes
cat >src/lib/result.ts <<'TS'
export type Result<T> = { ok: true; value: T } | { ok: false; error: string };
export const ok = <T>(value: T): Result<T> => ({ ok: true, value });
export const err = <T = never>(error: string): Result<T> => ({ ok: false, error });
TS
cat >src/users.ts <<'TS'
import { ok, err, type Result } from "./lib/result";

export function findUser(id: string): Result<{ id: string }> {
  if (!id) return err("missing id");
  return ok({ id });
}
TS
cat >src/orders.ts <<'TS'
import { ok, err, type Result } from "./lib/result";

export function findOrder(id: string): Result<{ id: string }> {
  if (!id) return err("missing id");
  return ok({ id });
}
TS
cat >src/invoices.ts <<'TS'
export class InvoiceError extends Error {}

export function findInvoice(id: string): { id: string } {
  if (!id) throw new InvoiceError("missing id");
  return { id };
}
TS
cat >notes/worklog.md <<'MD'
# Work log (this session)

- Added src/invoices.ts for the invoice lookup.
MD
