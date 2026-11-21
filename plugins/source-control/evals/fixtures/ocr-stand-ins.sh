# shellcheck shell=bash
set -euo pipefail

usage="usage: bash ocr-stand-ins.sh <bin-dir>, the gh-forge bin a case puts first on PATH:"
usage+=" writes tesseract and ffmpeg stand-ins there, so the evidence step's OCR scan reads clean text offline"
bin="${1:?$usage}"
mkdir -p "$bin"
cat >"$bin/tesseract" <<'EOF'
#!/usr/bin/env bash
printf 'Cart total shown in currency\n'
EOF
cat >"$bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
input="" out="${*: -1}"
while (($#)); do
  [[ "$1" != -i ]] || input="$2"
  shift
done
case "$out" in
  *%06d.png) cp -- "$input" "${out%/*}/frame-000001.png" ;;
  *) cp -- "$input" "$out" ;;
esac
EOF
chmod +x "$bin/tesseract" "$bin/ffmpeg"
