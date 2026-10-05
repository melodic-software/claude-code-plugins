#!/usr/bin/env bash
# A small JavaScript library whose one export, buildToc(markdown, options), hides heading parsing,
# slug de-duplication and nesting. The internals are imported only by index.js, and the tests call
# only buildToc.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test

cat > package.json <<'JSON'
{
  "name": "md-toc",
  "version": "1.4.0",
  "type": "module",
  "main": "src/index.js",
  "exports": { ".": "./src/index.js" },
  "scripts": { "test": "node --test test/" }
}
JSON

cat > src/index.js <<'JS'
import { parseHeadings } from './parse.js';
import { createSlugger } from './slug.js';
import { nest, render } from './tree.js';

/**
 * Build a Markdown table of contents for a document.
 * @param {string} markdown
 * @param {{ minDepth?: number, maxDepth?: number, bullet?: string }} [options]
 * @returns {string}
 */
export function buildToc(markdown, { minDepth = 1, maxDepth = 3, bullet = '-' } = {}) {
  const slugger = createSlugger();
  const headings = parseHeadings(markdown)
    .filter((h) => h.depth >= minDepth && h.depth <= maxDepth)
    .map((h) => ({ ...h, slug: slugger(h.text) }));
  return render(nest(headings), bullet);
}
JS

cat > src/parse.js <<'JS'
const ATX = /^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$/;
const FENCE = /^(```|~~~)/;

export function parseHeadings(markdown) {
  const headings = [];
  let fence = null;
  const lines = markdown.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const open = line.match(FENCE);
    if (open) {
      if (fence === null) fence = open[1];
      else if (open[1] === fence) fence = null;
      continue;
    }
    if (fence !== null) continue;
    const atx = line.match(ATX);
    if (atx) {
      headings.push({ depth: atx[1].length, text: stripInline(atx[2]) });
      continue;
    }
    const next = lines[i + 1] ?? '';
    if (line.trim() && /^=+\s*$/.test(next)) headings.push({ depth: 1, text: stripInline(line.trim()) });
    else if (line.trim() && /^-+\s*$/.test(next)) headings.push({ depth: 2, text: stripInline(line.trim()) });
  }
  return headings;
}

function stripInline(text) {
  return text
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/[*_]{1,3}([^*_]+)[*_]{1,3}/g, '$1');
}
JS

cat > src/slug.js <<'JS'
export function createSlugger() {
  const seen = new Map();
  return (text) => {
    const base = text
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^\p{L}\p{N}\s-]/gu, '')
      .trim()
      .replace(/\s+/g, '-');
    const count = seen.get(base) ?? 0;
    seen.set(base, count + 1);
    return count === 0 ? base : `${base}-${count}`;
  };
}
JS

cat > src/tree.js <<'JS'
export function nest(headings) {
  const root = { depth: 0, children: [] };
  const stack = [root];
  for (const heading of headings) {
    const node = { ...heading, children: [] };
    while (stack.length > 1 && stack[stack.length - 1].depth >= heading.depth) stack.pop();
    stack[stack.length - 1].children.push(node);
    stack.push(node);
  }
  return root.children;
}

export function render(nodes, bullet, indent = '') {
  return nodes
    .map((n) => [`${indent}${bullet} [${n.text}](#${n.slug})`, render(n.children, bullet, `${indent}  `)]
      .filter(Boolean)
      .join('\n'))
    .join('\n');
}
JS

cat > test/toc.test.js <<'JS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildToc } from '../src/index.js';

test('nests by heading depth', () => {
  assert.equal(buildToc('# A\n## B\n## C\n# D'), '- [A](#a)\n  - [B](#b)\n  - [C](#c)\n- [D](#d)');
});

test('repeated headings get numbered slugs', () => {
  assert.equal(buildToc('## Usage\n## Usage'), '- [Usage](#usage)\n- [Usage](#usage-1)');
});

test('headings inside code fences are ignored', () => {
  assert.equal(buildToc('# Real\n```\n# not a heading\n```'), '- [Real](#real)');
});

test('setext headings count', () => {
  assert.equal(buildToc('Title\n=====\nPart\n----'), '- [Title](#title)\n  - [Part](#part)');
});

test('maxDepth drops deeper headings', () => {
  assert.equal(buildToc('# A\n## B\n### C', { maxDepth: 2 }), '- [A](#a)\n  - [B](#b)');
});

test('inline code and links are stripped from the text', () => {
  assert.equal(buildToc('## Use `run()` with [docs](x.md)'), '- [Use run() with docs](#use-run-with-docs)');
});
JS

cat > README.md <<'MD'
# md-toc

`buildToc(markdown, { minDepth, maxDepth, bullet })` returns a Markdown table of contents.
Run the tests with `npm test`.
MD

git add .
git commit -q -m "feat: markdown table of contents"
