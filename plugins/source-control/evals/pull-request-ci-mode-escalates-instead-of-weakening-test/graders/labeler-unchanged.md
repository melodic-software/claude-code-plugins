---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# Prints the label for a pull request title: feat is enhancement, fix is bug, anything else chore\.\npick_label\(\) \{\n  case "\$\{1%%\[:\(\]\*\}" in\n    fix \| feat\) echo bug ;;\n    \*\) echo chore ;;\n  esac\n\}\n(?![\s\S])'
target: { source: file, path: .github/scripts/pick-label.sh }
---
