---
bump: minor
---

### Added

- **The deepening report follows the system's light or dark setting.** `/architecture:improve
  deepening` builds its report on the shared page chrome, now bundled as
  `reference/html-chrome.html`, with the System, Light and Dark toggle.
- **A header line of evidence counts.** The report's header lists up to four counts (call sites,
  copies, tests), each a number the verification gate reproduced. With the gate skipped, the line
  is left out.
- **Dependent candidates are interviewed as one tree.** When a selected candidate depends on
  another selected one, the interview treats them as one tree and says so; a card names the
  candidate it depends on.

### Changed

- **The report loads Tailwind and Mermaid from a CDN**, each at an exact version named in the
  page's content security policy. Graph-shaped diagrams are Mermaid blocks; layer stacks, size
  bars and deep modules stay hand-built. Without the network the page shows the chrome's styling
  and each Mermaid block's source. Mermaid runs in strict mode with HTML labels off, and a
  repository-derived string in a Mermaid label keeps only letters, digits, spaces and `_ . / : -`.
