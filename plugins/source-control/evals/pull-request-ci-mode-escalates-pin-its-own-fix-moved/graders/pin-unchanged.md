---
type: regex
pattern: '\nset -u\ngot="\$\(sha256sum lib\/label\.sh \| cut -d'' '' -f1\)"\nwant="bbf1303e801c3d88ba5c8cf67c55f0004bb76da1a54c0ade0811a2953626cd75"\nif \[ '
target: { source: file, path: tests/label-pin.test.sh }
---
