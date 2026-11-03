#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# Two defects outside the commit's claim: buildOptions writes the bearer token into the shared
# DEFAULTS.headers object when a caller passes no headers, so later anonymous requests carry the last
# user's token; and retries now uses ||, so the unchanged charge call's retries: 0 becomes 3.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/http src/api docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/http/options.js <<'JS'
const DEFAULTS = {
  timeoutMs: 5000,
  retries: 3,
  headers: { "User-Agent": "shop/1.0" },
};

export function buildOptions(input = {}) {
  return {
    timeoutMs: input.timeoutMs ?? DEFAULTS.timeoutMs,
    retries: input.retries ?? DEFAULTS.retries,
    headers: { ...DEFAULTS.headers, ...input.headers },
  };
}
JS

cat >src/http/client.js <<'JS'
import { buildOptions } from "./options.js";

export async function request(url, init = {}, input = {}) {
  const opts = buildOptions(input);
  let lastError;
  for (let attempt = 0; attempt <= opts.retries; attempt += 1) {
    try {
      const res = await fetch(url, {
        ...init,
        headers: { ...opts.headers, ...init.headers },
        signal: AbortSignal.timeout(opts.timeoutMs),
      });
      if (res.status < 500) {
        return res;
      }
      lastError = new Error(`HTTP ${res.status}`);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}
JS

cat >src/api/payments.js <<'JS'
import { request } from "../http/client.js";

// Never retry a charge: a POST that timed out may already have charged the card, and a retry
// charges it again.
export function charge(token, amountCents) {
  return request(
    "https://payments.example.test/charges",
    { method: "POST", body: JSON.stringify({ amountCents }) },
    { retries: 0, headers: { Authorization: `Bearer ${token}` } },
  );
}
JS

cat >src/api/catalog.js <<'JS'
import { request } from "../http/client.js";

// Public price list; anonymous on purpose so it can be cached by the CDN.
export function priceList() {
  return request("https://catalog.example.test/prices");
}
JS

cat >package.json <<'JSON'
{ "name": "shop-http", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: shared HTTP client with retries and timeouts"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/request-token

cat >src/http/options.js <<'JS'
const DEFAULTS = {
  timeoutMs: 5000,
  retries: 3,
  headers: { "User-Agent": "shop/1.0" },
};

// input: { timeoutMs?, retries?, headers?, token? }; token is a signed-in user's access token.
export function buildOptions(input = {}) {
  const { token, ...rest } = input;
  const opts = { ...DEFAULTS, ...rest };
  if (rest.headers) {
    opts.headers = { ...DEFAULTS.headers, ...rest.headers };
  }
  opts.timeoutMs = Math.max(250, opts.timeoutMs);
  opts.retries = rest.retries || DEFAULTS.retries;
  if (token) {
    opts.headers.Authorization = `Bearer ${token}`;
  }
  return opts;
}
JS

cat >src/api/account.js <<'JS'
import { request } from "../http/client.js";

export async function profile(token) {
  const res = await request("https://account.example.test/me", {}, { token });
  if (!res.ok) {
    throw new Error(`profile: HTTP ${res.status}`);
  }
  return res.json();
}

export async function orders(token) {
  const res = await request("https://account.example.test/me/orders", {}, { token, timeoutMs: 10000 });
  if (!res.ok) {
    throw new Error(`orders: HTTP ${res.status}`);
  }
  return res.json();
}
JS

git add .
git commit -q -m "feat: pass a signed-in user's token through buildOptions

Account calls now hand buildOptions a token and get an Authorization
header back, instead of each caller building the header itself. The
timeout also gets a 250 ms floor so a typo cannot make every call fail."
