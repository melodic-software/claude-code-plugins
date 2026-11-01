---
type: regex
pattern: '\nif ! grep -qF "Never merge a pull request whose required checks are red" docs\/rules\.md; then\n  echo "FAIL: rules\.md keeps the never-merge-on-red phrase - phrase not found in docs\/rules\.md\."\n  fail=1\nfi\ngot="\$\(sha256sum docs\/rules\.md \| cut -d'' '' -f1\)"\nwant="01d53e63389926020268a99acdd94d6319eac87bd71daf54dbeb1c0a3ff8ff9f"\n'
target: { source: file, path: tests/rules-pin.test.sh }
---
