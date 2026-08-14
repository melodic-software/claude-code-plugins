# Node manifest format (`node-manifest/v1`)

Owner doc for the manifest `extract_nodes.py` emits. The manifest is the corpus mapper's coverage
denominator: node identity comes from this deterministic script over an immutable snapshot, never
from an agent, so "every node has a verdict" is a claim about the whole snapshot, not about what an
agent chose to enumerate.

## Invariants (what a gate may rely on)

1. **Partition.** `nodes` is a non-overlapping, contiguous byte partition of the snapshot:
   `nodes[0].start_byte == 0`, each `end_byte == next.start_byte`, last `end_byte ==
   snapshot.byte_length`, every span non-empty. Every snapshot byte belongs to exactly one node.
2. **Determinism.** Two runs over one snapshot produce byte-identical manifests. No timestamps,
   machine paths, locale-dependent text, or unordered collections enter the output. The snapshot is
   recorded by basename only.
3. **Self-verifying spans.** `content_sha256` is SHA-256 over the raw snapshot bytes
   `[start_byte, end_byte)`. `snapshot.sha256` is SHA-256 over the whole snapshot as fetched (the
   Brief's captured content-hash assumption).
4. **Document order.** `nodes` is ordered by `start_byte`; `index` is the 0-based position.
5. **Fail loudly.** Empty snapshot, unreadable file, unknown extension, non-UTF-8 BOM, CR-only
   line endings, or a partition self-check failure exits non-zero with a message. The extractor
   never emits a manifest that violates invariant 1 or 3.
6. **Encoding contract.** Snapshots are expected to be UTF-8 (or ASCII-compatible) text. A UTF-8
   BOM is tolerated: the scanners skip it and its 3 bytes land in the first node's span. UTF-16 and
   UTF-32 BOMs are rejected loudly — the byte-level scanners would otherwise silently miss every
   heading, re-coarsening the coverage denominator to page level, which is the exact glossing
   failure this pipeline exists to prevent. Markdown snapshots with CR-only (classic Mac) line
   endings are rejected for the same reason; LF and CRLF are both supported. The fetch channel owns
   delivering UTF-8. BOM-less non-UTF-8 encodings are indistinguishable from odd bytes and pass
   through; their spans and hashes stay correct, only heading detection may degrade.

## Manifest shape

```json
{
  "schema": "node-manifest/v1",
  "extractor": {"name": "extract_nodes.py", "version": "1.0.0"},
  "snapshot": {
    "basename": "source.md",
    "format": "markdown",
    "byte_length": 12345,
    "sha256": "<hex64>"
  },
  "node_count": 7,
  "nodes": [
    {
      "id": "n0000-1a2b3c4d",
      "index": 0,
      "kind": "frontmatter",
      "level": 0,
      "title": "",
      "parent_id": null,
      "start_byte": 0,
      "end_byte": 89,
      "byte_length": 89,
      "content_sha256": "<hex64>"
    }
  ]
}
```

Serialization: JSON, `indent=2`, keys sorted, ASCII-escaped, trailing newline, UTF-8, LF only.

## Node fields

- `id` — `n<index 4-digit zero-padded>-<first 8 hex of content_sha256>`. Deterministic for one
  snapshot; NOT stable across snapshot revisions (an upstream edit re-partitions). Cross-revision
  identity is out of scope for v1.
- `kind` — `frontmatter` | `preamble` | `section` | `document`.
  - `frontmatter`: a leading `---`-fenced block (markdown only).
  - `preamble`: bytes between frontmatter (or byte 0) and the first heading.
  - `section`: a heading plus its body, running to the next heading of ANY level. Sections are
    leaf-granular; coarser granularity is a downstream roll-up over `level`/`parent_id`, never a
    re-extraction.
  - `document`: the whole snapshot, used when the format yields no outline (opaque formats, or a
    markdown/HTML file with no headings).
- `level` — heading level 1–6 for `section`; 0 otherwise.
- `title` — heading text, UTF-8-decoded (`errors=replace`), whitespace-normalized, display-only.
  Never use `title` for identity or matching; use `id`.
- `parent_id` — nearest preceding `section` with a lower `level`, else `null`. Encodes the outline
  tree over the flat partition.

## Format handlers and the extension seam

`FORMAT_HANDLERS` / `EXTENSION_FORMATS` in `extract_nodes.py` are the seam: a new format registers
a handler returning heading boundaries as raw byte offsets, and its extensions. Unregistered
extensions fail loudly; `--format` overrides per run. `.pdf` is deliberately mapped to an error —
extract nodes from the fetched text extraction (`source.txt`, opaque) beside it, never the binary.

### markdown (`.md`, `.markdown`, `.mdx`)

Byte-level line scan (no decode for boundary detection, so byte offsets are exact for any encoding
and CRLF is preserved in spans):

- ATX headings `#`–`######` (≤3 leading spaces), fence-aware: headings inside ` ``` `/`~~~` fences
  are content, not boundaries; an unclosed fence deterministically runs to EOF. 4-space-indented
  code is excluded by the ≤3-spaces rule.
- Setext headings (`===`/`---` underline, previous line non-blank and not already consumed):
  boundary at the previous line's start.
- Leading `---` frontmatter closed by `---`/`...` becomes the `frontmatter` node; unclosed means
  no frontmatter.

Documented deterministic simplifications (chosen over full CommonMark for auditability):

- A setext heading claims only its immediately preceding line as heading text; CommonMark would
  claim the whole paragraph. The partition boundary moves at most a line, coverage is unaffected.
- `---` after a non-blank line resolves to a setext h2 even where CommonMark would need paragraph
  context to decide against a thematic break.
- MDX/JSX constructs are not parsed; a `#` line inside an unfenced JSX block would be read as a
  heading. Acceptable for v1; a real MDX handler is a new registry entry.

### html (`.html`, `.htm`)

Byte-regex over a length-preserving masked copy (comments, `script`, `style`, `pre`, `textarea`
masked; unclosed masked regions mask to EOF). `<h1>`–`<h6>` open tags are boundaries; titles are
tag-stripped inner text. Limitation: this is not a DOM parse — malformed nesting or headings
constructed by JS are invisible. Docs-site HTML is expected to be tame; anything worse should be
fetched via a markdown channel instead.

### opaque (`.txt`, `.json`, unknown-with-override)

Single `document` node spanning the whole file. Correct for JSON schemas, licenses, and PDF text
extractions where outline structure either does not exist or is not recoverable deterministically.

## Non-goals (v1)

- Cross-revision node identity (see `id`).
- Sub-heading granularity (paragraph/sentence nodes). The partition floor is the heading section;
  finer evidence lives in evidence-token spans INSIDE a node's byte range.
- Format sniffing. The extension map (or `--format`) is trusted absolutely; content is never
  sniffed beyond the BOM checks above. An unknown extension fails loudly instead of guessing —
  but a wrong extension (binary bytes named `.html`) is honored, deterministically yielding a
  whole-`document` node.
