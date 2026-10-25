#!/usr/bin/env bash
# A pull request whose diff is larger than one Read returns (over the token limit, under
# the whole-file byte refusal). Its 40 files span models, services, routes, utils and
# tests; the one defect sits in one service, in the middle of the diff, inside a helper that
# each service has in its own form.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON
cat >src/app.js <<'JS'
export function createApp(router) {
  return { router, started: false };
}
JS
git add .
git commit -q -m "chore: start the storefront service"

git checkout -q -b feat/42-catalog-api
mkdir -p src/models src/services src/routes src/utils test

cap() { printf '%s%s' "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")" "${1:1}"; }
upper() { tr '[:lower:]' '[:upper:]' <<<"$1"; }

# name|plural|fields (the first three are required)
specs=(
  "customer|customers|email firstName lastName phone tier marketingOptIn defaultAddressId locale timezone loyaltyPoints referredBy birthDate companyName taxId"
  "product|products|sku title priceCents currency description stockLevel categoryId weightGrams active brandId barcode heightMm widthMm depthMm"
  "order|orders|customerId currency status lines totalCents placedAt shippingAddressId notes billingAddressId couponCode channel taxCents shippingCents"
  "invoice|invoices|orderId number amountCents issuedAt dueAt paidAt currency taxCents billingName billingEmail poNumber"
  "shipment|shipments|orderId carrier trackingNumber shippedAt deliveredAt status weightGrams serviceLevel labelUrl insuredCents signatureRequired"
  "supplier|suppliers|name contactEmail country leadTimeDays rating paymentTerms contactPhone website currency minimumOrderCents"
  "coupon|coupons|code percentOff validFrom validUntil maxRedemptions redeemed description minimumSpendCents customerId channel"
  "review|reviews|productId customerId rating title body publishedAt helpfulVotes verifiedPurchase locale moderationStatus"
  "category|categories|slug name parentId position description imageUrl visible seoTitle seoDescription"
)

model_factory() {
  local n="$1" N="$2" U="$3"
  shift 3
  local fields=("$@")
  {
    echo "// ${N} records as the API stores them."
    echo
    local joined
    joined="$(printf '"%s", ' "${fields[@]}")"
    echo "export const ${U}_FIELDS = Object.freeze([${joined%, }]);"
    printf 'const REQUIRED = ["%s", "%s", "%s"];\n' "${fields[0]}" "${fields[1]}" "${fields[2]}"
    cat <<JS

export function make${N}(input = {}) {
  const record = { id: input.id ?? null };
  for (const field of ${U}_FIELDS) {
    record[field] = input[field] ?? null;
  }
  return record;
}

export function validate${N}(record) {
  const problems = [];
  for (const field of REQUIRED) {
    const value = record[field];
    if (value === null || value === undefined || value === "") {
      problems.push(field + " is required");
    }
  }
  return problems;
}

export function describe${N}(record) {
  return "${n} " + (record.id ?? "(unsaved)");
}
JS
    for f in "${fields[@]}"; do
      cat <<JS

export function with$(cap "$f")(record, value) {
  return { ...record, ${f}: value };
}

export function has$(cap "$f")(record) {
  return record.${f} !== null && record.${f} !== undefined;
}
JS
    done
  } >"src/models/${n}.js"
}

model_class() {
  local n="$1" N="$2"
  shift 3
  local fields=("$@")
  {
    echo "// ${N} as a class, so the service can compare and serialize it."
    echo
    echo "export class ${N} {"
    echo "  constructor(props = {}) {"
    echo "    this.id = props.id ?? null;"
    for f in "${fields[@]}"; do echo "    this.${f} = props.${f} ?? null;"; done
    echo "  }"
    echo
    echo "  static fromRow(row) {"
    echo "    return new ${N}({"
    echo "      id: row.id,"
    for f in "${fields[@]}"; do echo "      ${f}: row.${f},"; done
    echo "    });"
    echo "  }"
    echo
    echo "  toRow() {"
    echo "    return {"
    echo "      id: this.id,"
    for f in "${fields[@]}"; do echo "      ${f}: this.${f},"; done
    echo "    };"
    echo "  }"
    echo
    echo "  isValid() {"
    printf '    return Boolean(this.%s && this.%s && this.%s);\n' "${fields[0]}" "${fields[1]}" "${fields[2]}"
    echo "  }"
    echo
    for f in "${fields[@]}"; do
      echo "  with$(cap "$f")(value) {"
      echo "    return new ${N}({ ...this.toRow(), ${f}: value });"
      echo "  }"
      echo
    done
    echo "  equals(other) {"
    echo "    return other instanceof ${N} && other.id === this.id;"
    echo "  }"
    echo "}"
  } >"src/models/${n}.js"
}

# Each service carries one or two operations of its own, so no service is a pure template.
service_extras() {
  case "$1" in
  category)
    extras_exported="moveTo, childrenOf"
    cat <<'JS'

  function moveTo(id, position) {
    return update(id, { position: Math.max(0, position) });
  }

  function childrenOf(parentId) {
    return [...items.values()].filter((item) => item.parentId === parentId);
  }
JS
    ;;
  coupon)
    extras_exported="redeem"
    cat <<'JS'

  function redeem(id) {
    const coupon = items.get(id);
    if (!coupon || coupon.redeemed >= coupon.maxRedemptions) {
      return null;
    }
    return update(id, { redeemed: coupon.redeemed + 1 });
  }
JS
    ;;
  customer)
    extras_exported="addLoyaltyPoints"
    cat <<'JS'

  function addLoyaltyPoints(id, points) {
    const customer = items.get(id);
    if (!customer || points <= 0) {
      return null;
    }
    return update(id, { loyaltyPoints: (customer.loyaltyPoints ?? 0) + points });
  }
JS
    ;;
  invoice)
    extras_exported="markPaid"
    cat <<'JS'

  function markPaid(id, paidAt = new Date().toISOString()) {
    const invoice = items.get(id);
    if (!invoice || invoice.paidAt) {
      return null;
    }
    return update(id, { paidAt });
  }
JS
    ;;
  order)
    extras_exported="cancel"
    cat <<'JS'

  function cancel(id) {
    const order = items.get(id);
    if (!order || order.status === "shipped" || order.status === "delivered") {
      return null;
    }
    return update(id, { status: "cancelled" });
  }
JS
    ;;
  product)
    extras_exported="reserveStock, releaseStock"
    cat <<'JS'

  // Hold stock for an order being placed; null when there is not enough.
  function reserveStock(id, quantity) {
    const product = items.get(id);
    if (!product || product.stockLevel < quantity) {
      return null;
    }
    return update(id, { stockLevel: product.stockLevel + quantity });
  }

  // Return held stock when an order is cancelled.
  function releaseStock(id, quantity) {
    const product = items.get(id);
    if (!product) {
      return null;
    }
    return update(id, { stockLevel: product.stockLevel + quantity });
  }
JS
    ;;
  review)
    extras_exported="markHelpful"
    cat <<'JS'

  function markHelpful(id) {
    const review = items.get(id);
    if (!review) {
      return null;
    }
    return update(id, { helpfulVotes: (review.helpfulVotes ?? 0) + 1 });
  }
JS
    ;;
  shipment)
    extras_exported="markDelivered"
    cat <<'JS'

  function markDelivered(id, deliveredAt = new Date().toISOString()) {
    const shipment = items.get(id);
    if (!shipment || !shipment.shippedAt) {
      return null;
    }
    return update(id, { deliveredAt, status: "delivered" });
  }
JS
    ;;
  supplier)
    extras_exported="rate"
    cat <<'JS'

  function rate(id, rating) {
    return update(id, { rating: Math.min(5, Math.max(1, Math.round(rating))) });
  }
JS
    ;;
  *)
    echo "scaffold: no extras for $1" >&2
    exit 1
    ;;
  esac
}

service() {
  local n="$1" N="$2" p="$3"
  shift 3
  local fields=("$@")
  {
    cat <<JS
// In-memory ${n} store behind the ${p} routes.
import { pageOf } from "../utils/pagination.js";
import { isNonEmptyString } from "../utils/validation.js";

export function create$(cap "$p")Service(initial = []) {
  const items = new Map(initial.map((item) => [item.id, item]));
  let nextId = initial.length + 1;

  function create(input) {
    const id = String(nextId);
    nextId += 1;
    const item = { ...input, id };
    items.set(id, item);
    return item;
  }

  function get(id) {
    return items.get(id) ?? null;
  }

  function update(id, changes) {
    const current = items.get(id);
    if (!current) {
      return null;
    }
    const next = { ...current, ...changes, id };
    items.set(id, next);
    return next;
  }

  function remove(id) {
    return items.delete(id);
  }

  function list(query = {}) {
    return pageOf([...items.values()], query.page, query.pageSize);
  }

  function count() {
    return items.size;
  }
JS
    local exported="create, get, update, remove, list, count"
    for f in "${fields[@]}"; do
      local F
      F="$(cap "$f")"
      cat <<JS

  function findBy${F}(value) {
    if (typeof value === "string" && !isNonEmptyString(value)) {
      return [];
    }
    return [...items.values()].filter((item) => item.${f} === value);
  }

  function countBy${F}() {
    const counts = new Map();
    for (const item of items.values()) {
      counts.set(item.${f}, (counts.get(item.${f}) ?? 0) + 1);
    }
    return counts;
  }
JS
      exported="${exported}, findBy${F}, countBy${F}"
    done
    service_extras "$n"
    exported="${exported}, ${extras_exported}"
    cat <<JS

  return { ${exported} };
}
JS
  } >"src/services/${n}-service.js"
}

route() {
  local n="$1" N="$2" p="$3"
  {
    cat <<JS
// HTTP handlers for /${p}.
import { parsePageQuery } from "../utils/pagination.js";
import { validate${N} } from "../models/${n}.js";

export function ${p}Routes(service) {
  return [
    {
      method: "GET",
      path: "/${p}",
      handle(req, res) {
        const { page, pageSize } = parsePageQuery(req.query);
        res.status(200).json(service.list({ page, pageSize }));
      },
    },
    {
      method: "GET",
      path: "/${p}/:id",
      handle(req, res) {
        const item = service.get(req.params.id);
        if (!item) {
          res.status(404).json({ error: "${n} not found" });
          return;
        }
        res.status(200).json(item);
      },
    },
    {
      method: "POST",
      path: "/${p}",
      handle(req, res) {
        const problems = validate${N}(req.body ?? {});
        if (problems.length > 0) {
          res.status(400).json({ errors: problems });
          return;
        }
        res.status(201).json(service.create(req.body));
      },
    },
    {
      method: "PATCH",
      path: "/${p}/:id",
      handle(req, res) {
        const item = service.update(req.params.id, req.body ?? {});
        if (!item) {
          res.status(404).json({ error: "${n} not found" });
          return;
        }
        res.status(200).json(item);
      },
    },
    {
      method: "DELETE",
      path: "/${p}/:id",
      handle(req, res) {
        res.status(service.remove(req.params.id) ? 204 : 404).end();
      },
    },
  ];
}
JS
  } >"src/routes/${p}.js"
}

testfile() {
  local n="$1" N="$2" p="$3"
  shift 3
  local fields=("$@")
  {
    cat <<JS
import { test } from "node:test";
import assert from "node:assert/strict";
import { create$(cap "$p")Service } from "../src/services/${n}-service.js";

test("${p}: create assigns increasing ids", () => {
  const service = create$(cap "$p")Service();
  const first = service.create({ ${fields[0]}: "a" });
  const second = service.create({ ${fields[0]}: "b" });
  assert.equal(first.id, "1");
  assert.equal(second.id, "2");
  assert.equal(service.count(), 2);
});

test("${p}: update returns null for an unknown id", () => {
  const service = create$(cap "$p")Service();
  assert.equal(service.update("missing", { ${fields[1]}: "x" }), null);
});

test("${p}: remove deletes the item", () => {
  const service = create$(cap "$p")Service();
  const item = service.create({ ${fields[0]}: "a" });
  assert.equal(service.remove(item.id), true);
  assert.equal(service.get(item.id), null);
});
JS
    for f in "${fields[@]:0:$((3 + ${#fields[@]} % 4))}"; do
      cat <<JS

test("${p}: findBy$(cap "$f") matches on ${f}", () => {
  const service = create$(cap "$p")Service();
  service.create({ ${f}: "match" });
  service.create({ ${f}: "other" });
  const found = service.findBy$(cap "$f")("match");
  assert.equal(found.length, 1);
  assert.equal(found.at(0).${f}, "match");
});
JS
    done
  } >"test/${p}.test.js"
}

i=0
for spec in "${specs[@]}"; do
  IFS='|' read -r n p fieldlist <<<"$spec"
  read -r -a fields <<<"$fieldlist"
  N="$(cap "$n")"
  if ((i % 2 == 0)); then
    model_factory "$n" "$N" "$(upper "$n")" "${fields[@]}"
  else
    model_class "$n" "$N" "$(upper "$n")" "${fields[@]}"
    # Routes validate through a function, so class models export one too.
    cat >>"src/models/${n}.js" <<JS

export function validate${N}(input) {
  return new ${N}(input).isValid() ? [] : ["${fields[0]}, ${fields[1]} and ${fields[2]} are required"];
}
JS
  fi
  service "$n" "$N" "$p" "${fields[@]}"
  # Only the first seven resources get routes and tests in this pull request.
  if ((i < 7)); then
    route "$n" "$N" "$p"
    testfile "$n" "$N" "$p" "${fields[@]}"
  fi
  i=$((i + 1))
done

cat >src/utils/csv.js <<'JS'
// Minimal CSV for the export endpoints: quoted fields, embedded commas and quotes.

export function escapeField(value) {
  const text = value === null || value === undefined ? "" : String(value);
  if (/[",\n]/.test(text)) {
    return '"' + text.replaceAll('"', '""') + '"';
  }
  return text;
}

export function toCsv(header, rows) {
  const lines = [header.map(escapeField).join(",")];
  for (const row of rows) {
    lines.push(header.map((key) => escapeField(row[key])).join(","));
  }
  return lines.join("\n");
}

export function parseLine(line) {
  const fields = [];
  let current = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') {
        current += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        current += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      fields.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  fields.push(current);
  return fields;
}
JS

cat >src/utils/dates.js <<'JS'
// Date helpers that work in UTC so reports do not shift with the server's zone.

const DAY_MS = 24 * 60 * 60 * 1000;

export function startOfUtcDay(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

export function addDays(date, days) {
  return new Date(date.getTime() + days * DAY_MS);
}

export function daysBetween(from, to) {
  return Math.round((startOfUtcDay(to) - startOfUtcDay(from)) / DAY_MS);
}

export function isWithin(date, from, to) {
  return date >= from && date < to;
}

export function toIsoDate(date) {
  return date.toISOString().slice(0, 10);
}
JS

cat >src/utils/money.js <<'JS'
// Money is held in integer cents; these helpers keep it that way.

export function sumCents(amounts) {
  let total = 0;
  for (let i = 0; i < amounts.length; i++) {
    total += amounts[i];
  }
  return total;
}

export function percentOf(cents, percent) {
  return Math.round((cents * percent) / 100);
}

export function applyDiscount(cents, percentOff) {
  return Math.max(0, cents - percentOf(cents, percentOff));
}

export function formatCents(cents, currency = "USD") {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}

export function splitEvenly(cents, parts) {
  if (parts <= 0) {
    throw new RangeError("parts must be positive");
  }
  const base = Math.floor(cents / parts);
  const shares = new Array(parts).fill(base);
  const remainder = cents - base * parts;
  for (let i = 0; i < remainder; i++) {
    shares[i] += 1;
  }
  return shares;
}
JS

cat >src/utils/orders.js <<'JS'
// Order arithmetic shared by the order service and the sales reports.
import { sumCents } from "./money.js";

export function lineTotalCents(line) {
  return line.unitPriceCents * line.quantity;
}

export function orderTotalCents(order) {
  return sumCents(order.lines.map(lineTotalCents));
}

export function averageOrderValue(orders) {
  if (orders.length === 0) {
    return 0;
  }
  let total = 0;
  for (let i = 0; i < orders.length; i++) {
    total += orders[i].totalCents;
  }
  return Math.round(total / orders.length);
}

export function largestOrder(orders) {
  let largest = null;
  for (const order of orders) {
    if (!largest || order.totalCents > largest.totalCents) {
      largest = order;
    }
  }
  return largest;
}

export function ordersByStatus(orders) {
  const groups = {};
  for (const order of orders) {
    (groups[order.status] ??= []).push(order);
  }
  return groups;
}
JS

cat >src/utils/pagination.js <<'JS'
// Page-number pagination for list endpoints.

export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;

export function parsePageQuery(query = {}) {
  const page = Math.max(1, Number.parseInt(query.page ?? "1", 10) || 1);
  const requested = Number.parseInt(query.pageSize ?? String(DEFAULT_PAGE_SIZE), 10);
  const pageSize = Math.min(MAX_PAGE_SIZE, Math.max(1, requested || DEFAULT_PAGE_SIZE));
  return { page, pageSize };
}

export function pageOf(items, page = 1, pageSize = DEFAULT_PAGE_SIZE) {
  const start = (page - 1) * pageSize;
  return {
    items: items.slice(start, start + pageSize),
    page,
    pageSize,
    total: items.length,
    pages: Math.ceil(items.length / pageSize),
  };
}
JS

cat >src/utils/retry.js <<'JS'
// Retry a flaky async call with exponential backoff.

export async function retry(fn, { attempts = 3, baseDelayMs = 100, sleep = defaultSleep } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn(attempt);
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        await sleep(baseDelayMs * 2 ** (attempt - 1));
      }
    }
  }
  throw lastError;
}

function defaultSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
JS

cat >src/utils/strings.js <<'JS'
// String helpers for slugs and display text.

export function slugify(text) {
  return String(text)
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function truncate(text, max) {
  if (text.length <= max) {
    return text;
  }
  return text.slice(0, Math.max(0, max - 1)) + "…";
}

export function titleCase(text) {
  return text
    .split(" ")
    .map((word) => (word ? word[0].toUpperCase() + word.slice(1).toLowerCase() : word))
    .join(" ");
}
JS

cat >src/utils/validation.js <<'JS'
// Input checks shared by the models and services.

export function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

export function isEmail(value) {
  return isNonEmptyString(value) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export function isPositiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

export function isIsoDate(value) {
  return isNonEmptyString(value) && !Number.isNaN(Date.parse(value));
}
JS

git add .
git commit -q -m "feat(api): add the catalog, order and customer API

Closes #42"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

# The case measures nothing unless the first Read returns a partial page and the defect
# sits in the middle band: past that first page, before the utils the diff ends with.
bytes="$(wc -c <.claude-lane/pr.diff)"
if ((bytes < 120000 || bytes > 250000)); then
  echo "scaffold: pr.diff is $bytes bytes, outside 120000-250000" >&2
  exit 1
fi
line="$(grep -n -A 6 'function reserveStock' .claude-lane/pr.diff | grep 'stockLevel + quantity' | cut -d- -f1)"
utils="$(grep -n '^diff --git a/src/utils/' .claude-lane/pr.diff | head -n 1 | cut -d: -f1)"
if ((line < 1900 || line > utils - 100)); then
  echo "scaffold: the defect is on diff line $line, outside 1900 to $((utils - 100))" >&2
  exit 1
fi
if [[ "$(git diff --name-only main...HEAD | tail -n 1)" == "src/services/product-service.js" ]]; then
  echo "scaffold: the defect is in the diff's last file" >&2
  exit 1
fi
