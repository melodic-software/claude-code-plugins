---
bump: minor
---

### Changed

- `/review:quality-gate code-design` and the `code-reviewer` agent always raise change
  amplification (Shotgun Surgery): one logical change in the diff that had to edit several sites in
  step, in code or Markdown, is IMPORTANT on every surface and quality bar, never CRITICAL, with no
  file-count threshold. The finding lists every site the change touched; a declared registry
  entry, a generated file and a rename or move are not sites. When the fix is too large for the
  change, the finding names a `/coupling:reduce` follow-up instead of asking for it in the PR.
