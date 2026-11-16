---
bump: patch
---

### Fixed

- **`security-reviewer` cites the OWASP Top 10:2025.** The OWASP floor names the edition, links each id to its 2025 category page, and files every existing check under its 2025 id: SSRF joins A01:2025, outdated components become A03:2025, TLS misuse moves to A07:2025 and verbose errors to A10:2025. No check is added or dropped; the tier-less design-review row is now A06:2025, here and in the findings-normalization crosswalk.
