#!/usr/bin/env bash
# A pull request whose diff is larger than one Read returns (over the token limit, under
# the whole-file byte refusal), with its one defect in the last file of the diff.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON
cat >src/index.js <<'JS'
export const service = "storefront";
JS
git add .
git commit -q -m "chore: start the storefront service"

git checkout -q -b feat/31-domain-models
mkdir -p src/models src/reports

entities="account address basket brand campaign carrier category channel coupon courier
currency customer delivery discount invoice ledger listing locale manifest merchant
parcel partner payment payout pricebook product promotion receipt refund region
return review seller shipment sku stock store supplier tariff voucher warehouse"

for e in $entities; do
  E="$(tr '[:lower:]' '[:upper:]' <<<"${e:0:1}")${e:1}"
  U="$(tr '[:lower:]' '[:upper:]' <<<"$e")"
  cat >"src/models/$e.js" <<JS
// The $e record as the storefront stores it, plus the helpers that build and check it.

export const ${U}_STATUSES = Object.freeze(["draft", "active", "suspended", "archived"]);

export const ${U}_FIELDS = Object.freeze([
  "id",
  "name",
  "status",
  "createdAt",
  "updatedAt",
  "ownerId",
  "notes",
  "tags",
]);

export function create${E}(input) {
  const now = new Date().toISOString();
  return {
    id: String(input.id),
    name: String(input.name ?? "").trim(),
    status: input.status ?? "draft",
    createdAt: input.createdAt ?? now,
    updatedAt: now,
    ownerId: input.ownerId ?? null,
    notes: input.notes ?? "",
    tags: Array.isArray(input.tags) ? [...new Set(input.tags)] : [],
  };
}

export function validate${E}(record) {
  const errors = [];
  if (!record || typeof record !== "object") {
    return ["$e must be an object"];
  }
  if (!record.id) {
    errors.push("$e id is required");
  }
  if (!record.name) {
    errors.push("$e name is required");
  }
  if (!${U}_STATUSES.includes(record.status)) {
    errors.push(\`$e status must be one of \${${U}_STATUSES.join(", ")}\`);
  }
  if (record.ownerId !== null && typeof record.ownerId !== "string") {
    errors.push("$e ownerId must be a string or null");
  }
  if (!Array.isArray(record.tags)) {
    errors.push("$e tags must be an array");
  }
  return errors;
}

export function is${E}Active(record) {
  return record.status === "active";
}

export function activate${E}(record) {
  if (record.status === "archived") {
    throw new Error("an archived $e cannot be activated");
  }
  return { ...record, status: "active", updatedAt: new Date().toISOString() };
}

export function suspend${E}(record, reason) {
  if (!reason) {
    throw new Error("suspending a $e needs a reason");
  }
  return {
    ...record,
    status: "suspended",
    notes: [record.notes, \`suspended: \${reason}\`].filter(Boolean).join("\n"),
    updatedAt: new Date().toISOString(),
  };
}

export function archive${E}(record) {
  return { ...record, status: "archived", updatedAt: new Date().toISOString() };
}

export function rename${E}(record, name) {
  const trimmed = String(name ?? "").trim();
  if (!trimmed) {
    throw new Error("a $e name cannot be empty");
  }
  return { ...record, name: trimmed, updatedAt: new Date().toISOString() };
}

export function tag${E}(record, tag) {
  if (record.tags.includes(tag)) {
    return record;
  }
  return { ...record, tags: [...record.tags, tag], updatedAt: new Date().toISOString() };
}

export function untag${E}(record, tag) {
  return {
    ...record,
    tags: record.tags.filter((t) => t !== tag),
    updatedAt: new Date().toISOString(),
  };
}

export function ${e}ToRow(record) {
  return ${U}_FIELDS.map((field) => {
    const value = record[field];
    if (Array.isArray(value)) {
      return value.join("|");
    }
    return value ?? "";
  });
}

export function ${e}FromRow(row) {
  const record = {};
  ${U}_FIELDS.forEach((field, position) => {
    record[field] = row.at(position) ?? null;
  });
  record.tags = record.tags ? String(record.tags).split("|") : [];
  return record;
}

export function sort${E}sByName(records) {
  return [...records].sort((a, b) => a.name.localeCompare(b.name));
}

export function find${E}ById(records, id) {
  return records.find((record) => record.id === id) ?? null;
}

export function group${E}sByStatus(records) {
  const groups = Object.fromEntries(${U}_STATUSES.map((status) => [status, []]));
  for (const record of records) {
    groups[record.status]?.push(record);
  }
  return groups;
}
JS
done

cat >src/reports/sales-summary.js <<'JS'
// Summary figures for the daily sales report.

export function averageOrderValue(orders) {
  if (orders.length === 0) {
    return 0;
  }
  let total = 0;
  for (let i = 0; i <= orders.length; i++) {
    total += orders[i].total;
  }
  return total / orders.length;
}

export function largestOrder(orders) {
  return orders.reduce((best, order) => (best && best.total >= order.total ? best : order), null);
}
JS

git add .
git commit -q -m "feat(models): add the storefront domain models and the sales summary

Closes #31"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

# The case measures nothing unless the first Read returns a partial page: the diff must be
# over Read's token limit and under its whole-file byte refusal, with the defect in the
# diff's last file and well past the first page.
bytes="$(wc -c <.claude-lane/pr.diff)"
if ((bytes < 120000 || bytes > 250000)); then
  echo "scaffold: pr.diff is $bytes bytes, outside 120000-250000" >&2
  exit 1
fi
last="$(git diff --name-only main...HEAD | tail -n 1)"
if [[ "$last" != "src/reports/sales-summary.js" ]]; then
  echo "scaffold: the last file in the diff is $last" >&2
  exit 1
fi
offset="$(grep -b -o 'i <= orders.length' .claude-lane/pr.diff | cut -d: -f1)"
if ((offset * 4 < bytes * 3)); then
  echo "scaffold: the defect sits at byte $offset of $bytes, not past 75%" >&2
  exit 1
fi
