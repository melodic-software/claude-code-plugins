#!/usr/bin/env bash
# Seed a small TypeScript repo whose read-only reconciler class carries a rejected name.
set -euo pipefail

mkdir -p src/ledger src/jobs
cat >src/ledger/reconcile.ts <<'TS'
import { BankLine, LedgerEntry, Mismatch } from "./types";

// Compares bank statement lines with ledger entries and returns the ones that do not match.
// Read-only: it never writes to the ledger or the bank feed.
export class LedgerSync {
  constructor(private readonly toleranceCents: number) {}

  compare(lines: BankLine[], entries: LedgerEntry[]): Mismatch[] {
    const byRef = new Map(entries.map((e) => [e.reference, e]));
    const out: Mismatch[] = [];
    for (const line of lines) {
      const entry = byRef.get(line.reference);
      if (!entry) {
        out.push({ reference: line.reference, reason: "missing-entry" });
      } else if (Math.abs(entry.amountCents - line.amountCents) > this.toleranceCents) {
        out.push({ reference: line.reference, reason: "amount-differs" });
      }
    }
    return out;
  }
}
TS
cat >src/ledger/types.ts <<'TS'
export interface BankLine { reference: string; amountCents: number }
export interface LedgerEntry { reference: string; amountCents: number }
export interface Mismatch { reference: string; reason: "missing-entry" | "amount-differs" }
TS
cat >src/ledger/ledger-writer.ts <<'TS'
// Posts approved entries to the ledger. The only class here that writes.
export class LedgerWriter {
  post(reference: string, amountCents: number): void {
    void reference;
    void amountCents;
  }
}
TS
cat >src/jobs/nightly.ts <<'TS'
import { LedgerSync } from "../ledger/reconcile";

export function runNightly(lines: never[], entries: never[]) {
  return new LedgerSync(1).compare(lines, entries);
}
TS
