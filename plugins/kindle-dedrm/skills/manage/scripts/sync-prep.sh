#!/usr/bin/env bash
# sync-prep.sh — prepare for re-syncing new Kindle books.
# Disables the firewall block, prints the user-driven steps, waits for input.
#
# Pairs with sync-finalize.sh which closes the window after the user is done.
#
# Usage: sync-prep.sh [--dry-run]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

echo "=== kindle-dedrm: sync prep ==="

# Pre-flight: status check
if [[ -x "${SCRIPT_DIR}/status.sh" ]]; then
  echo "[sync-prep] current state:"
  bash "${SCRIPT_DIR}/status.sh"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  cat <<'EOF'

[DRY-RUN] Would do:
  1. Disable firewall rule "Block Kindle for PC (lock 2.8.0)" (admin pwsh).
  2. Wait for user to: open Kindle for PC, sync, double-click new books, quit Kindle.
  3. Hand off to sync-finalize.sh:
     - Delete cached installer at %LOCALAPPDATA%\Amazon\Kindle\updates\
     - Re-enable firewall rule.
     - Re-run keyfinder to extract keys + import + convert new books.

EOF
  exit 0
fi

# Disable firewall rule (requires admin)
echo "[sync-prep] disabling firewall rule (admin required)..."
echo
echo "  Open elevated PowerShell and run:"
echo "    Disable-NetFirewallRule -DisplayName 'Block Kindle for PC (lock 2.8.0)'"
echo
echo "  Or run this skill's wrapper from elevated pwsh:"
echo "    pwsh -File '${SCRIPT_DIR}/firewall.ps1' -Action disable"
echo

cat <<EOF
=== USER STEPS (do not skip) ===

1. Confirm firewall is now disabled (see message above).

2. Open Kindle for PC.

3. **CRITICAL:** if Kindle prompts to upgrade, REFUSE.
   - Close prompt via X if no Skip option.
   - DO NOT click "Update now" — it will install 2.9.x and break your setup.

4. Click Sync (cloud icon top-left).

5. Double-click each new book to download. Wait for the "New" overlay
   to clear (downloaded checkmark).

6. **Quit Kindle entirely** (File → Exit). Verify no tray icon remains.

7. When Kindle is fully quit, run:
     bash "${SCRIPT_DIR}/sync-finalize.sh"

=== END USER STEPS ===
EOF

exit 0
