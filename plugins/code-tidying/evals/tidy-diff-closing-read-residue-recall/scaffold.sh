#!/usr/bin/env bash
# Commits an http helper and an email normalizer on main, adds an uncommitted src/reminders.ts carrying seven low-salience residue kinds, and writes the lines file naming all 18 of its lines.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >src/http.ts <<'EOF'
export async function fetchJson(url: string): Promise<unknown> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`GET ${url} failed: ${response.status}`);
  return response.json();
}
EOF
cat >src/strings.ts <<'EOF'
export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}
EOF
git add src/http.ts src/strings.ts
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add http and string helpers"
cat >src/reminders.ts <<'EOF'
import { fetchJson } from "./http";

export type Invoice = { id: string; paid: boolean; customer: { email: string } };

type LoadOptions = { includePaid: boolean };

export async function loadInvoiceEmailsV2(url: string, options: LoadOptions): Promise<string[]> {
  console.log("entering loadInvoiceEmailsV2");
  const invoices = (await fetchJson(url)) as unknown as Invoice[];
  return invoices
    .filter((invoice) => options.includePaid === true || invoice.paid === false)
    .map((invoice) => (invoice.customer?.email ?? "").trim().toLowerCase());
}

export async function countReminders(url: string): Promise<number> {
  const emails = await loadInvoiceEmailsV2(url, { includePaid: false });
  return emails.length;
}
EOF
printf '1\t18\tsrc/reminders.ts\n' >changed-lines.tsv
