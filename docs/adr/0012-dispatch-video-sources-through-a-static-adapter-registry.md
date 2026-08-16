# Dispatch video sources through a static adapter registry

- Status: accepted
- Date: 2026-08-16

## Context

The knowledge plugin's single-video digest pipeline (`video-digest`, formerly `youtube-digest`)
became source-agnostic: X (Twitter) joined YouTube behind an engine-layer source-adapter
contract, and more sources are expected. Something has to map a URL to the adapter that owns
it. The sibling `course-digest` skill already had the obvious alternative in-tree: a resolver
that computes a module path from configuration and dynamically imports it — a drop-in-adapter
design, and also a CWE-829/22 surface where configuration or input can steer module resolution.
The type lane is `checkJs` JSDoc, where an interpolated `import()` resolves to `any`, so the
checker is blind to exactly the code a dynamic resolver depends on.

## Decision

`extraction/adapters/registry.js` holds a frozen host-keyed map of **statically imported**
adapter modules — never a computed dynamic import in any spelling. Dispatch parses the URL
with WHATWG `new URL`, matches the hostname exact-or-`.<host>`-suffix against owned hosts
only, and fails closed (an unsupported-source error listing supported sources) for unknown
hosts and for owned-host URLs the adapter declines. Adapter regexes run only after host
ownership is established. Each adapter also declares a yt-dlp extractor allow-list
(`allowedExtractors`), so a spawn can never follow a delegated foreign URL the adapter does
not own.

The trade-off accepted: adding a source means editing the registry and shipping a plugin
release — there are no drop-in adapters. In exchange, module resolution is closed to input
and configuration, the import graph is fully visible to the type checker and to review, and a
registry-conformance test can assert the whole dispatch table (host collisions, canonical
example URLs) at CI time.
