#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
printf '%s\n' 'def greet(name):' '    if name:' '        return "hello " + name' '    return "hello"' >greet.py
printf '%s\n' 'TN:' 'SF:greet.py' 'DA:1,1' 'DA:2,1' 'DA:3,1' 'DA:4,0' 'LF:4' 'LH:3' 'end_of_record' >lcov.info
git add greet.py lcov.info
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
printf '%s\n' '' 'def farewell(name):' '    return "bye " + name' >>greet.py
