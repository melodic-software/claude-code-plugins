---
type: regex
pattern: '^(?![\s\S]*make_bundle)(?=[\s\S]*run: source scripts/package\.sh && build_bundle --compress)'
target: { source: file, path: .github/workflows/release.yml }
---
