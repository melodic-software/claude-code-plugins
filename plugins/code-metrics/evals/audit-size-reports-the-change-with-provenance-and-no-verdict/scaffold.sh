#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
printf '%s\n' 'def greet(name):' '    return "hello " + name' >greet.py
printf '%s\n' '# demo' 'A small fixture project.' >README.md
git add greet.py README.md
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
printf '%s\n' '' 'def farewell(name):' '    return "bye " + name' >>greet.py
printf '%s\n' '#!/usr/bin/env bash' 'echo "deploying"' >deploy.sh
for i in $(seq 1 1200); do
  printf 'SETTING_%d = %d\n' "$i" "$i"
done >settings.py
