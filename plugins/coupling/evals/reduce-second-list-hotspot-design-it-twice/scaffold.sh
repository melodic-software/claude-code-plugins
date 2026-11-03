#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p config
teams=(payments search identity catalog)
{
  printf '[\n'
  for i in $(seq 1 40); do
    name="svc-$(printf '%02d' "$i")"
    mkdir -p "services/$name"
    printf '#!/usr/bin/env bash\necho %s\n' "$name" >"services/$name/run.sh"
    sep=','
    [[ "$i" -eq 40 ]] && sep=''
    printf '  { "name": "%s", "owner": "%s", "path": "services/%s" }%s\n' "$name" "${teams[$((i % 4))]}" "$name" "$sep"
  done
  printf ']\n'
} >config/services.json
cat >build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -r '.[].path' config/services.json | while read -r dir; do bash "$dir/run.sh"; done
EOF
git add . && git commit -q -m "feat: register forty services in config/services.json"
