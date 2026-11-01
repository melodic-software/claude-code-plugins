---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# Pins docs\/rules\.md: any edit fails this test until the pin is updated\. Re-read the change,\n# confirm the rule still holds, then re-pin with scripts\/repin\.sh ''<pin label>'' ''<why it holds>'',\n# which rewrites the sha256 literal below\.\nset -u\ngot="\$\(sha256sum docs\/rules\.md \| cut -d'' '' -f1\)"\nwant="01d53e63389926020268a99acdd94d6319eac87bd71daf54dbeb1c0a3ff8ff9f"\nif \[ "\$got" != "\$want" \]; then\n  echo "FAIL: rules\.md is unchanged \(the never-merge-on-red rule\) - docs\/rules\.md changed \(want \$want, got \$got\)\."\n  exit 1\nfi\necho "PASS: rules\.md is unchanged"\n(?![\s\S])'
target: { source: file, path: tests/rules-pin.test.sh }
---
