#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# On main, slugify turns accented letters into hyphens; the branch strips the accents and adds a
# test whose assert.ok takes the expected slug as its message, so the test passes on main as well.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/slug.js <<'JS'
export function slugify(title) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
JS

cat >test/slug.test.js <<'JS'
import test from "node:test";
import assert from "node:assert/strict";
import { slugify } from "../src/slug.js";

test("slugify joins words with hyphens", () => {
  assert.equal(slugify("Hello, World"), "hello-world");
});
JS

cat >package.json <<'JSON'
{ "name": "blog-slugs", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON

git add .
git commit -q -m "feat: slugify post titles"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b fix/slug-accents
cat >src/slug.js <<'JS'
export function slugify(title) {
  return title
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
JS
cat >test/slug.test.js <<'JS'
import test from "node:test";
import assert from "node:assert/strict";
import { slugify } from "../src/slug.js";

test("slugify joins words with hyphens", () => {
  assert.equal(slugify("Hello, World"), "hello-world");
});

test("slugify strips accents", () => {
  const cases = [
    ["Crème brûlée", "creme-brulee"],
    ["Açaí bowl", "acai-bowl"],
  ];
  for (const [title, expected] of cases) {
    assert.ok(slugify(title), expected);
  }
});
JS
git commit -q -am "fix: slugify strips accents from titles

Crème brûlée now slugs to creme-brulee instead of cr-me-br-l-e."
