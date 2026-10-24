#!/usr/bin/env bash
# Stages the k36-cart-total project with tdd_refactor_step: on in the team layer.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../k36-cart-total/scaffold.sh"
mkdir -p docs/conventions
printf "tdd_refactor_step: 'on'\n" >docs/conventions/testing.yaml
git -c user.name=eval -c user.email=eval@example.invalid add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "Set the testing write settings"
