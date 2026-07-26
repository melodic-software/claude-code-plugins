# Changelog

All notable changes to the `ai-briefing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.2]

### Security

- **Source-URL schemes are allowlisted at every deck sink.** A shared
  `lib/url-policy.js` seam now exposes `isAllowedUrlScheme`, reused at schema
  validation and at each href/hyperlink sink. `http:`, `https:`, `mailto:`, and
  `tel:` — the schemes a legitimate briefing may contain, inert at every sink —
  are preserved and continue to render as working links. **Every other scheme is
  now rejected**: the `javascript:`, `data:`, and `file:` attack vectors that
  could inject script into the HTML deck or embed a local-file hyperlink in the
  PPTX, and — as deliberate fail-closed hardening — rarer schemes such as `ftp:`
  that the previous permissive `z.string().url()` accepted. Two layers: the Zod
  schema hard-fails a deck containing a disallowed scheme (loud fail-closed on an
  attack indicator), and the HTML and PPTX builders drop the individual unsafe
  link (defense-in-depth on the `--skip-emit` rebuild path).
- **Link-reachability checks refuse non-global hosts (SSRF guard).**
  `shouldSkipLinkCheck` now skips URLs whose literal host falls in any
  non-global block of the IANA special-purpose registries, not just RFC1918:
  loopback, private, link-local, shared address space (CGN), benchmarking,
  documentation TEST-NETs, IETF protocol assignments, multicast, and reserved
  (127/8, 10/8, 100.64/10, 172.16/12, 192.168/16, 169.254/16, 0/8, 192.0.0/24,
  192.0.2/24, 198.18/15, 198.51.100/24, 203.0.113/24, 224/4, 240/4,
  `localhost`/`*.localhost`; IPv6 `::`/`::1`/`fc00::/7`/`fe80::/10`/`ff00::/8`/
  `100::/64`/`2001:db8::/32`/`3fff::/20`, plus IPv4-mapped and NAT64
  `64:ff9b::/96` forms judged by their embedded IPv4 address), relying on
  WHATWG URL canonicalization of decimal/hex/octal/integer IPv4. A public hostname that resolves to a private
  address at fetch time (DNS rebind) is not covered — the checker resolves DNS
  itself, so that case remains outside this offline literal gate.

## [0.6.1]

### Changed

- **Setup now documents how to change `active_profile`, not only how it is read.** The skill
  resolved the key and reported the profile path, but named no route to a different stored value,
  so a consumer whose configured profile was wrong for the repository had nothing to act on and the
  `--profile` override looked like the only lever. `check` step 1 now names all three: the
  interactive `/plugin configure ai-briefing` flow, which is the only surface that changes the
  stored value; the headless `--config` path, with the caveat that it seeds on a fresh install only
  and is ignored once installed, so reconfiguring headlessly is uninstall-then-reinstall; and the
  per-run `--profile` for a one-off that should not touch stored config. This skill still never
  writes `pluginConfigs`.

## [0.6.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract.** The read-only `check`
  action verifies the resolved profile, `sources.md`, optional overlays, and the
  build-toolchain state (PASS/FAIL/INFO); `apply` scaffolds the profile. The
  verify-plus-install fusion behind `--with-build-deps` is split into an explicit
  `apply install-build-deps` subaction that runs the same locked build-toolchain
  install flow unchanged. `--profile <name>` still selects the profile for either
  action. README invocation references updated to the subaction.

## [0.5.2]

### Changed

- **Freshness rider on the Playwright environment matrix** (fleet conformance
  wave: volatile platform facts carry a verified-date + official link). The
  README matrix is dated and re-verified against Playwright's system
  requirements; the setup skill no longer restates the version matrix and
  defers to the linked page as authoritative.

## [0.5.1]

### Changed

- README states the POSIX-shell requirement of the `setup --with-build-deps`
  install step with its Windows path (Git Bash; the script's platform gate
  already accepts MINGW/MSYS/CYGWIN) — cross-platform declaration wave. The
  Node build pipeline is unchanged and remains shell-free.

## [0.5.0]

### Changed

- Renamed the `ai-briefing` skill → `generate`. Update any `/ai-briefing:ai-briefing` invocations to
  `/ai-briefing:generate`; the plugin ID (`ai-briefing`) is unchanged, only the skill's leaf name
  moved. `scripts/validate-plugin-contracts.mjs` retargeted to `skills/generate` for its
  active-profile and build-root checks.

## [0.4.0]

### Added

- Engine behavioral evals in `skills/ai-briefing/evals/evals.json`, covering: `retro` action
  routing and per-item acted/noted/skipped scoring against an archived briefing; `search`
  action full-text matching across archives; markdown-only output when `--format slides`/`html`
  is not explicitly requested; merge-not-append behavior when folding newly collected items into
  an already-open briefing window; the apolitical filter, pragmatic-use ranking lens, and
  profile-provided impact-lens annotation (via `references/audience-defaults.md`); and graceful,
  visibly-surfaced degradation when an optional collection source is unreachable, without
  aborting the run.
- Three supporting fixtures under `skills/ai-briefing/evals/fixtures/`: `archive-sample.md`,
  `open-window-sample.md`, and `candidate-items-sample.md` — neutral, synthetic AI-industry
  content with no real company, person, or consumer-specific references.
