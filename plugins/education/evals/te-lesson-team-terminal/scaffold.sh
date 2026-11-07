#!/usr/bin/env bash
# Seeds a git working tree whose team rendered-views file says medium: terminal, plus a rust-ownership
# topic workspace under learning/topic/.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
printf '%s\n' 'medium: terminal' >docs/conventions/rendered-views.yaml
ws=learning/topic/rust-ownership
mkdir -p "$ws/learning-records" "$ws/concepts"
cat >"$ws/MISSION.md" <<'EOF'
# Mission: Rust Ownership

## Why

I review Rust pull requests at work and keep missing borrow mistakes the compiler later rejects.

## Success Looks Like

- Predict whether a short function compiles, and say which borrow rule decides it
- Fix a "cannot borrow as mutable because it is also borrowed as immutable" error unaided

## Constraints

- About 20 minutes a day
EOF
cat >"$ws/RESOURCES.md" <<'EOF'
# Resources

- The Rust Programming Language, chapter 4 "Understanding Ownership":
  https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html (primary; checked last session)
EOF
cat >"$ws/NOTES.md" <<'EOF'
# Notes

- Prefers short code examples over prose.
EOF
cat >"$ws/learning-records/0001-moves-demonstrated.md" <<'EOF'
# Moves demonstrated

Predicted correctly that `let b = a;` moves a String and that using `a` afterwards fails to compile.

**Evidence**: three of three move predictions right. **Implications**: borrowing is the next frontier.
EOF
