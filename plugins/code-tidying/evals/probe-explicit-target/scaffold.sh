#!/usr/bin/env bash
# Seeds the eval workspace with app.sh and one commit.
set -euo pipefail

cp "$(dirname "${BASH_SOURCE[0]}")/fixture/app.sh.txt" app.sh
git init -q
git add app.sh
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add app"
