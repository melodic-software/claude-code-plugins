#!/usr/bin/env bash
# A one-context billing repository whose glossary defines Invoice (Avoid: bill) while the code also
# names the same record PaymentDemand, a name the glossary never recorded.
set -euo pipefail
mkdir -p docs src/billing
cat >README.md <<'MD'
# Harbor Billing

Invoicing for Harbor's wholesale buyers.
MD
cat >docs/glossary.md <<'MD'
# Harbor Billing glossary

Terms the billing team uses. Avoid marks words we rejected; use the chosen term instead.

**Invoice**

A request for payment issued to a buyer after delivery.

Avoid: bill

**Buyer**

A wholesale customer account that receives invoices.
MD
cat >src/billing/invoice.ts <<'TS'
export interface Invoice {
  id: string;
  buyerId: string;
  amountDue: number;
  dueDate: string;
}

export function issueInvoice(buyerId: string, amountDue: number): Invoice {
  return { id: crypto.randomUUID(), buyerId, amountDue, dueDate: "" };
}
TS
cat >src/billing/reminders.ts <<'TS'
export interface PaymentDemand {
  id: string;
  buyerId: string;
  amountDue: number;
  dueDate: string;
}

export function sendPaymentDemand(demand: PaymentDemand): string {
  return `Reminder: ${demand.amountDue} due by ${demand.dueDate}`;
}
TS
