#!/usr/bin/env bash
# A React app whose dialogs and menus use Radix primitives.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" package.json src
mkdir -p src/components
cat > package.json <<'JSON'
{ "name": "bookly", "private": true, "dependencies": { "react": "^19.0.0", "@radix-ui/react-dialog": "^1.1.0", "@radix-ui/react-dropdown-menu": "^2.1.0" } }
JSON
cat > src/components/BookingForm.tsx <<'TSX'
import * as Dialog from "@radix-ui/react-dialog";

export function BookingForm() {
  return (
    <Dialog.Root>
      <Dialog.Trigger>Book a table</Dialog.Trigger>
      <Dialog.Content>
        <label>Date <input name="date" /></label>
      </Dialog.Content>
    </Dialog.Root>
  );
}
TSX
