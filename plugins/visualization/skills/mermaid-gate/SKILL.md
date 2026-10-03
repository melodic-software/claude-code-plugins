---
description: "Parse every Mermaid block before it is emitted and, when the pinned mmdc is present, pre-render it to SVG for a local page. Use when: 'check this mermaid', 'validate the diagram', 'does this mermaid parse', 'pre-render the mermaid to SVG', or before writing a local HTML page or markdown file that carries a mermaid block. Skip for a published Artifact, which renders Mermaid natively. Another plugin's mermaid-emitting skill may call it."
argument-hint: "<check|<file> ...> [--svg-dir <dir>]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(node ${CLAUDE_SKILL_DIR}/scripts/mermaid-gate.mjs:*)", "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Parse Mermaid blocks, report syntax errors, and pre-render to SVG with the pinned mmdc
---

## Purpose

Stop a broken diagram from reaching a page. Every Mermaid block in the given files is checked before the page or document is written. With the pinned `mmdc` present the block is also rendered to SVG for a local page. Without it, the Mermaid source is kept.

A published Artifact renders Mermaid natively, so an Artifact needs the parse and never the SVG: omit `--svg-dir`.

## Run

`check` as the argument runs the prerequisite checker and stops:

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --for skill:mermaid-gate --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Otherwise write each diagram to a `.mmd` file, or use the markdown file that holds ` ```mermaid ` fences, then run:

```bash
node "${CLAUDE_SKILL_DIR}/scripts/mermaid-gate.mjs" --svg-dir "<dir>" <file>...
```

Stdout is one JSON report; each block has `file`, `line`, `status` (`ok` or `error`) and `render` (`svg` or `source`). Exit 1 means at least one block failed to parse. Exit 2 is a usage error.

## Act on the report

- **`status: error`**: do not write the page. Report the block's `file`, `line` and `error` text, fix the diagram, and run the gate again.
- **`render: svg`**: embed the SVG file the block names in the local page in place of the fence.
- **`render: source`**: keep the Mermaid source in the page and print the block's `reason` beside it, so the reader knows why it is not a picture. Never describe such a page as rendered.

Without `mmdc`, the parse is a structural check: an unknown diagram type, an unterminated quote, unbalanced brackets in a flowchart. It does not catch every syntax error. Say so when reporting an `ok` from a `source` block.

## Next

- Write the page: `/visualization:visualize`.
- Chart a C# entry point, gate included: `/architecture:map-flow`.

## Gotchas

- The gate uses `mmdc` only at the pinned version, and the version is in `prerequisites.json` and the script's `PINNED_MMDC`. Any other version is treated as absent, with the reason in the report. As of 2026-10-02, 11.17.0 is the newest 11.x release of `@mermaid-js/mermaid-cli`. Recheck when the Artifact runtime's Mermaid version (see `visualize/context/decision-matrix.md`) moves to a different major.
- `mmdc` renders in a headless browser. A failure that is not a parse error (no Chrome) falls back to source with the failure text as the reason. It is not a syntax error.
