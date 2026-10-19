#!/usr/bin/env bash
# main holds an app whose upload limit is MAX_UPLOAD_MB in src/config.js, read by the upload hint,
# and payment methods spread over three files: the method list, the labels and the icons. The
# branch adds an upload validator that hardcodes the same 25 instead of importing it, and adds
# paypal to each of the three payment files. No test ties the copies together. The base commit SHA
# is in .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p src/upload src/payments

cat >package.json <<'JSON'
{ "name": "shop", "type": "module", "private": true }
JSON

cat >src/config.js <<'JS'
export const MAX_UPLOAD_MB = 25;
JS

cat >src/upload/hint.js <<'JS'
import { MAX_UPLOAD_MB } from "../config.js";

export const uploadHint = `Files up to ${MAX_UPLOAD_MB} MB.`;
JS

cat >src/payments/options.js <<'JS'
export const METHODS = ["card", "bank"];
JS

cat >src/payments/labels.js <<'JS'
export const LABELS = {
  card: "Credit card",
  bank: "Bank transfer",
};
JS

cat >src/payments/icons.js <<'JS'
export const ICONS = {
  card: "card.svg",
  bank: "bank.svg",
};
JS

git add .
git commit -q -m "feat: upload hint and payment methods"
git rev-parse HEAD >.review-base
git checkout -q -b feat/upload-check-paypal

cat >src/upload/validate.js <<'JS'
export function checkUploadSize(bytes) {
  if (bytes > 25 * 1024 * 1024) {
    return "File is larger than 25 MB.";
  }
  return null;
}
JS

cat >src/payments/options.js <<'JS'
export const METHODS = ["card", "bank", "paypal"];
JS

cat >src/payments/labels.js <<'JS'
export const LABELS = {
  card: "Credit card",
  bank: "Bank transfer",
  paypal: "PayPal",
};
JS

cat >src/payments/icons.js <<'JS'
export const ICONS = {
  card: "card.svg",
  bank: "bank.svg",
  paypal: "paypal.svg",
};
JS

git add src
git commit -q -m "feat: upload size check and PayPal"
