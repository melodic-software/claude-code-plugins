#!/usr/bin/env bash
# Decoy fixture page-links, with docs/conventions/review.yaml committed on main so the run reads
# fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch rewrites pageNumbers' loop to count 1-based pages with a <= bound. The change is
# correct: it pushes 1 through pageCount, as main did, and the tests pass on both commits.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/pagination.js <<'JS'
export const PAGE_SIZE = 20;

// Page numbers are 1-based, as they appear in ?page= URLs.
export function pageNumbers(totalItems) {
  const pageCount = Math.ceil(totalItems / PAGE_SIZE);
  const pages = [];
  for (let i = 0; i < pageCount; i++) {
    pages.push(i + 1);
  }
  return pages;
}
JS

cat >test/pagination.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { pageNumbers } from "../src/pagination.js";

test("no items, no pages", () => {
  assert.deepEqual(pageNumbers(0), []);
});

test("a partial last page counts", () => {
  assert.deepEqual(pageNumbers(41), [1, 2, 3]);
});

test("an exact multiple adds no empty page", () => {
  assert.deepEqual(pageNumbers(40), [1, 2]);
});
JS

cat >package.json <<'JSON'
{
  "name": "catalog-pager",
  "type": "module",
  "private": true,
  "scripts": { "test": "node --test" }
}
JSON

git add .
git commit -q -m "feat: page links for the catalog"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/page-numbers
cat >src/pagination.js <<'JS'
export const PAGE_SIZE = 20;

// Page numbers are 1-based, as they appear in ?page= URLs.
export function pageNumbers(totalItems) {
  const pageCount = Math.ceil(totalItems / PAGE_SIZE);
  const pages = [];
  for (let page = 1; page <= pageCount; page++) {
    pages.push(page);
  }
  return pages;
}
JS
git commit -q -am "refactor: count 1-based pages in pageNumbers

The loop now counts the page numbers it pushes instead of offsetting an index."
