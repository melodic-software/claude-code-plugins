#!/usr/bin/env bash
# A hooks folder with a small shell wrapper around a large Python body, plus a spawn census
# that attributes the per-call cost across the two layers.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p hooks measurements
cat >hooks/guard.sh <<'EOF'
#!/usr/bin/env bash
# PreToolUse wrapper: normalizes the command, then execs the Python guard body.
set -euo pipefail
input="$(cat)"
tool="$(printf '%s' "$input" | cut -d'"' -f4)"
cmd="$(printf '%s' "$input" | tr -s ' ' | cut -d'"' -f8)"
exec python3 "$(dirname "$0")/guard_body.py" "$tool" "$cmd"
EOF
chmod +x hooks/guard.sh

{
  printf '"""Guard body: decides allow or deny for one tool call."""\n'
  printf 'import sys\n\n\n'
  for i in $(seq 1 380); do
    printf 'def rule_%d(cmd):\n    """Rule %d."""\n    return "deny" if cmd.startswith("rm -rf /%d") else None\n\n\n' "$i" "$i" "$i"
  done
  printf 'def main():\n    cmd = sys.argv[2] if len(sys.argv) > 2 else ""\n'
  printf '    for name, rule in sorted(globals().items()):\n'
  printf '        if name.startswith("rule_") and rule(cmd):\n            print("deny")\n            return\n'
  printf '    print("allow")\n\n\nif __name__ == "__main__":\n    main()\n'
} >hooks/guard_body.py

cat >measurements/spawn-census.txt <<'EOF'
Spawn census, one PreToolUse call of hooks/guard.sh, PATH-shim accounting, 2 runs agreed.

total processes per call: 7
  hook runner -> bash hooks/guard.sh      1
  guard.sh: cat, cut, tr, cut             4   (wrapper layer)
  guard_body.py: python3                  1   (body layer)
  guard_body.py: no subprocess calls      0
  hook runner bookkeeping                 1
EOF

printf '.work/\n' >.gitignore
git add .gitignore hooks measurements
git commit -q -m "guard hook and its spawn census"
